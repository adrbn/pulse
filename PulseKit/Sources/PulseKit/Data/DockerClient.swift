import Foundation

/// Docker Engine API, reached through the restricted socket proxy on the server
/// (list, inspect and start only).
public struct DockerClient: Sendable {
    public let base: URL
    let http: HTTP

    public init(base: URL, http: HTTP = HTTP()) { self.base = base; self.http = http }

    struct Item: Decodable, Sendable {
        let Id: String
        let Names: [String]
        let Image: String
        let State: String
        let Status: String
        let Labels: [String: String]?
    }

    struct Inspect: Decodable, Sendable {
        struct S: Decodable, Sendable { let FinishedAt: String; let ExitCode: Int }
        let State: S
    }

    public func containers() async throws -> [Container] {
        let items = try await http.json([Item].self, base.appending(path: "containers/json", query: ["all": "1"]))
        var out = Self.map(items)
        // Only stopped containers need an inspect call (for the stop time); there are few.
        for i in out.indices where out[i].state == .stopped {
            guard let id = items.first(where: { Self.name($0) == out[i].name })?.Id,
                  let info = try? await http.json(Inspect.self, base.appending(path: "containers/\(id)/json")) else { continue }
            out[i].stoppedAt = Dates.parse(info.State.FinishedAt)
            out[i].exitCode = info.State.ExitCode
        }
        return out
    }

    public func start(_ name: String) async throws {
        _ = try await http.data(base.appending(path: "containers/\(name)/start"), method: "POST")
    }

    static func name(_ i: Item) -> String {
        let n = i.Names.first ?? String(i.Id.prefix(12))
        return n.hasPrefix("/") ? String(n.dropFirst()) : n
    }

    static func map(_ items: [Item]) -> [Container] {
        items.map { i in
            let status = i.Status.lowercased()
            let health: ContainerHealth = status.contains("(unhealthy)") ? .unhealthy
                : status.contains("(healthy)") ? .healthy : .none
            let state: ContainerState
            switch i.State {
            case "running": state = health == .unhealthy ? .unhealthy : .running
            case "restarting": state = .restarting
            default: state = .stopped
            }
            return Container(name: name(i), image: i.Image,
                             stack: i.Labels?["com.docker.compose.project"].flatMap { $0.isEmpty ? nil : $0 } ?? "other",
                             state: state, health: health, exitCode: exitCode(i.Status))
        }
    }

    /// "Exited (137) 5 hours ago" -> 137
    static func exitCode(_ status: String) -> Int? {
        guard let r = status.range(of: #"Exited \((-?\d+)\)"#, options: .regularExpression) else { return nil }
        return Int(status[r].filter { $0.isNumber || $0 == "-" })
    }
}
