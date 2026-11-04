import Foundation

public struct Reading: Sendable {
    public var server: Server
    public var containers: [Container]
    public var canStart: Bool
}

public protocol ServerDataSource: Sendable {
    func fetch() async throws -> Reading
    func start(_ container: String) async throws
}

/// Beszel hub (PocketBase REST). Field names checked against hub 0.21 / agent 0.21:
/// systems.info {cpu, mp, dp, dt, la, u}, system_details {cpu, cores},
/// system_stats(1m).stats.b = [sent, recv] bytes/s, containers {name, image, status, health, cpu, memory(MB)}.
public actor BeszelSource: ServerDataSource {
    let base: URL
    let email: String
    let password: String
    let systemName: String?
    let displayName: String?
    let docker: DockerClient?
    let http = HTTP()
    private var token: String?

    public init(base: URL, email: String, password: String, systemName: String?, displayName: String?, docker: DockerClient?) {
        self.base = base; self.email = email; self.password = password
        self.systemName = systemName; self.displayName = displayName; self.docker = docker
    }

    // MARK: Wire types

    struct List<T: Decodable & Sendable>: Decodable, Sendable { let items: [T] }
    struct Auth: Decodable, Sendable { let token: String }
    struct System: Decodable, Sendable {
        struct Info: Decodable, Sendable {
            let cpu: Double?; let mp: Double?; let dp: Double?; let dt: Double?
            let la: [Double]?; let u: Double?; let t: Int?
        }
        let id: String; let name: String; let status: String; let updated: String; let info: Info
    }
    struct Details: Decodable, Sendable { let cpu: String?; let cores: Int?; let threads: Int? }
    struct Stats: Decodable, Sendable {
        struct S: Decodable, Sendable { let b: [Double]? }
        let stats: S
    }
    struct BContainer: Decodable, Sendable {
        let name: String; let image: String?; let status: String?; let health: Int?
        let cpu: Double?; let memory: Double?
    }

    // MARK: Fetch

    public func fetch() async throws -> Reading {
        let system = try await pickSystem()
        async let details = try? get(List<Details>.self, "system_details", filter: "system='\(system.id)'")
        async let stats = try? get(List<Stats>.self, "system_stats", filter: "system='\(system.id)' && type='1m'",
                                   extra: ["sort": "-created", "perPage": "1"])
        async let bContainers = try? get(List<BContainer>.self, "containers", filter: "system='\(system.id)'",
                                         extra: ["perPage": "500"])
        async let dockerList: [Container]? = try? await docker?.containers()

        let d = await details?.items.first
        let server = Self.server(system, details: d, bandwidth: await stats?.items.first?.stats.b,
                                 displayName: displayName, now: .now)
        let beszelItems = await bContainers?.items
        let fromDocker = await dockerList
        // Both lists failing (network blip) is not "0 containers": keep the last good reading instead.
        if beszelItems == nil && fromDocker == nil { throw SourceError.noContainers }
        let fromBeszel = Self.containers(beszelItems ?? [])
        let containers = fromDocker.map { Self.merge(docker: $0, beszel: fromBeszel) } ?? fromBeszel
        return Reading(server: server, containers: containers, canStart: fromDocker != nil)
    }

    public func start(_ container: String) async throws {
        guard let docker else { throw SourceError.notConfigured("Docker endpoint") }
        try await docker.start(container)
    }

    private func pickSystem() async throws -> System {
        let systems = try await get(List<System>.self, "systems", filter: nil, extra: ["perPage": "50"]).items
        if let name = systemName, !name.isEmpty {
            guard let s = systems.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame })
            else { throw SourceError.noSystem }
            return s
        }
        guard let s = systems.first else { throw SourceError.noSystem }
        return s
    }

    private func get<T: Decodable & Sendable>(_ type: T.Type, _ collection: String, filter: String?, extra: [String: String] = [:]) async throws -> T {
        var q = extra
        if let filter { q["filter"] = "(\(filter))" }
        let url = base.appending(path: "api/collections/\(collection)/records", query: q)
        do {
            return try await http.json(T.self, url, headers: ["Authorization": try await authToken()])
        } catch SourceError.http(let code, _) where code == 401 || code == 403 {
            token = nil
            return try await http.json(T.self, url, headers: ["Authorization": try await authToken()])
        }
    }

    private func authToken() async throws -> String {
        if let token { return token }
        guard !email.isEmpty, !password.isEmpty else { throw SourceError.notConfigured("Beszel email and password") }
        let body = try JSONSerialization.data(withJSONObject: ["identity": email, "password": password])
        // Beszel keeps the admin in `_superusers` with the same email and often a different password: try both.
        var lastCode = 0
        for collection in ["users", "_superusers"] {
            do {
                let auth = try await http.json(Auth.self, base.appending(path: "api/collections/\(collection)/auth-with-password"),
                                               method: "POST", body: body)
                token = auth.token
                return auth.token
            } catch SourceError.http(let code, _) {
                lastCode = code
            }
        }
        throw SourceError.auth(lastCode == 400 ? "wrong email or password" : "hub answered \(lastCode)")
    }

    // MARK: Mapping (static, unit-tested against real hub responses)

    static func server(_ s: System, details: Details?, bandwidth: [Double]?, displayName: String?, now: Date) -> Server {
        let la = s.info.la ?? []
        let online = s.status == "up"
        return Server(
            name: displayName.flatMap { $0.isEmpty ? nil : $0 } ?? s.name,
            cpuModel: (details?.cpu ?? "").replacingOccurrences(of: "(R)", with: "").replacingOccurrences(of: "(TM)", with: ""),
            cores: details?.cores ?? s.info.t ?? 1,
            online: online,
            lastSeen: online ? now : (Dates.parse(s.updated) ?? now),
            uptime: s.info.u ?? 0,
            cpu: s.info.cpu ?? 0, ram: s.info.mp ?? 0, disk: s.info.dp ?? 0,
            cpuTempC: s.info.dt,
            load1: la.count > 0 ? la[0] : 0, load5: la.count > 1 ? la[1] : 0, load15: la.count > 2 ? la[2] : 0,
            netInBps: (bandwidth?.count ?? 0) > 1 ? bandwidth![1] : 0,
            netOutBps: bandwidth?.first ?? 0)
    }

    static func containers(_ items: [BContainer]) -> [Container] {
        items.map { c in
            let health: ContainerHealth = c.health == 3 ? .unhealthy : c.health == 2 ? .healthy : .none
            let up = (c.status ?? "Up").hasPrefix("Up")
            let state: ContainerState = !up ? .stopped : health == .unhealthy ? .unhealthy
                : (c.status ?? "").contains("Restarting") ? .restarting : .running
            return Container(name: c.name, image: c.image ?? "", state: state, health: health,
                             cpu: c.cpu ?? 0, memBytes: (c.memory ?? 0) * 1_048_576)
        }
    }

    /// Docker knows state, exit code and stack; Beszel knows per-container CPU and memory.
    static func merge(docker: [Container], beszel: [Container]) -> [Container] {
        let usage = Dictionary(beszel.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        return docker.map { c in
            var c = c
            if let b = usage[c.name] { c.cpu = b.cpu; c.memBytes = b.memBytes }
            return c
        }
    }
}
