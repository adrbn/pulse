import Foundation

/// Proxmox VE API for host vitals plus the Docker proxy for containers.
/// The PVE API has no CPU temperature, so the Temp tile shows "–" in this mode.
public struct ProxmoxSource: ServerDataSource {
    let base: URL
    let node: String?
    let tokenID: String       // user@realm!tokenname
    let secret: String
    let displayName: String?
    let docker: DockerClient?
    let http: HTTP

    public init(base: URL, node: String?, tokenID: String, secret: String, insecure: Bool,
                displayName: String?, docker: DockerClient?) {
        self.base = base; self.node = node; self.tokenID = tokenID; self.secret = secret
        self.displayName = displayName; self.docker = docker
        self.http = HTTP(insecureHost: insecure ? base.host() : nil)
    }

    struct Envelope<T: Decodable & Sendable>: Decodable, Sendable { let data: T }
    struct Node: Decodable, Sendable { let node: String }
    struct Status: Decodable, Sendable {
        struct Mem: Decodable, Sendable { let used: Double; let total: Double }
        struct CPUInfo: Decodable, Sendable { let model: String?; let cpus: Int? }
        let cpu: Double; let memory: Mem; let rootfs: Mem; let uptime: Double
        let loadavg: [String]; let cpuinfo: CPUInfo
    }
    struct RRD: Decodable, Sendable { let netin: Double?; let netout: Double? }

    var auth: [String: String] { ["Authorization": "PVEAPIToken=\(tokenID)=\(secret)"] }

    public func fetch() async throws -> Reading {
        guard !tokenID.isEmpty, !secret.isEmpty else { throw SourceError.notConfigured("Proxmox API token") }
        let name: String
        if let node, !node.isEmpty { name = node }
        else {
            let nodes = try await http.json(Envelope<[Node]>.self, base.appending(path: "api2/json/nodes"), headers: auth)
            guard let first = nodes.data.first?.node else { throw SourceError.noSystem }
            name = first
        }
        async let status = http.json(Envelope<Status>.self, base.appending(path: "api2/json/nodes/\(name)/status"), headers: auth)
        async let rrd = try? http.json(Envelope<[RRD]>.self,
                                       base.appending(path: "api2/json/nodes/\(name)/rrddata", query: ["timeframe": "hour"]),
                                       headers: auth)
        async let dockerList: [Container]? = try? await docker?.containers()

        let s = try await status.data
        let net = await rrd?.data.last { $0.netin != nil }
        let la = s.loadavg.compactMap(Double.init)
        let server = Server(
            name: displayName.flatMap { $0.isEmpty ? nil : $0 } ?? name,
            cpuModel: (s.cpuinfo.model ?? "").replacingOccurrences(of: "(R)", with: ""),
            cores: s.cpuinfo.cpus ?? 1, online: true, lastSeen: .now, uptime: s.uptime,
            cpu: s.cpu * 100, ram: s.memory.used / max(1, s.memory.total) * 100,
            disk: s.rootfs.used / max(1, s.rootfs.total) * 100, cpuTempC: nil,
            load1: la.first ?? 0, load5: la.count > 1 ? la[1] : 0, load15: la.count > 2 ? la[2] : 0,
            netInBps: net?.netin ?? 0, netOutBps: net?.netout ?? 0)
        let containers = await dockerList
        if docker != nil && containers == nil { throw SourceError.noContainers }
        return Reading(server: server, containers: containers ?? [], canStart: containers != nil)
    }

    public func start(_ container: String) async throws {
        guard let docker else { throw SourceError.notConfigured("Docker endpoint") }
        try await docker.start(container)
    }
}
