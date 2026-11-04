import Foundation

public struct Server: Codable, Sendable, Equatable {
    public var name: String
    public var cpuModel: String
    public var cores: Int
    public var online: Bool
    public var lastSeen: Date
    public var uptime: TimeInterval
    public var cpu: Double          // percent 0...100
    public var ram: Double
    public var disk: Double
    public var cpuTempC: Double?
    public var load1: Double
    public var load5: Double
    public var load15: Double
    public var netInBps: Double
    public var netOutBps: Double

    public init(name: String, cpuModel: String, cores: Int, online: Bool, lastSeen: Date, uptime: TimeInterval,
                cpu: Double, ram: Double, disk: Double, cpuTempC: Double?, load1: Double, load5: Double, load15: Double,
                netInBps: Double, netOutBps: Double) {
        self.name = name; self.cpuModel = cpuModel; self.cores = cores; self.online = online
        self.lastSeen = lastSeen; self.uptime = uptime; self.cpu = cpu; self.ram = ram; self.disk = disk
        self.cpuTempC = cpuTempC; self.load1 = load1; self.load5 = load5; self.load15 = load15
        self.netInBps = netInBps; self.netOutBps = netOutBps
    }
}

public enum ContainerState: String, Codable, Sendable { case running, stopped, unhealthy, restarting }
public enum ContainerHealth: String, Codable, Sendable { case healthy, unhealthy, none }

public struct Container: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var image: String
    public var stack: String
    public var state: ContainerState
    public var health: ContainerHealth
    public var exitCode: Int?
    public var stoppedAt: Date?
    public var cpu: Double
    public var memBytes: Double

    public init(name: String, image: String = "", stack: String = "other", state: ContainerState,
                health: ContainerHealth = .none, exitCode: Int? = nil, stoppedAt: Date? = nil,
                cpu: Double = 0, memBytes: Double = 0) {
        self.name = name; self.image = image; self.stack = stack; self.state = state; self.health = health
        self.exitCode = exitCode; self.stoppedAt = stoppedAt; self.cpu = cpu; self.memBytes = memBytes
    }

    public var isRunning: Bool { state == .running }
    /// Shown under "Needs attention": anything not plainly running.
    public var needsAttention: Bool { state != .running }
}

public struct Sample: Codable, Sendable, Equatable {
    public var time: Date
    public var cpu: Double
    public var ram: Double
    public var disk: Double
    public var temp: Double?
    public init(time: Date, cpu: Double, ram: Double, disk: Double, temp: Double?) {
        self.time = time; self.cpu = cpu; self.ram = ram; self.disk = disk; self.temp = temp
    }
}

public enum EventKind: String, Codable, Sendable { case exited, unhealthy, boot, cpuSpike, offline, online }

public struct PulseEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var time: Date
    public var text: String
    public var kind: EventKind
    public var container: String?
    public init(id: String, time: Date, text: String, kind: EventKind, container: String? = nil) {
        self.id = id; self.time = time; self.text = text; self.kind = kind; self.container = container
    }
}

/// Everything a surface (popover, widget, icon) needs, in one value. Written to the App Group for widgets.
public struct Snapshot: Codable, Sendable, Equatable {
    public var server: Server
    public var containers: [Container]       // alphabetical
    public var netIn: [Double]                // last 60 s, oldest first
    public var netOut: [Double]
    public var history: [Sample]              // last 24 h, 1 per minute
    public var events: [PulseEvent]           // newest first
    public var updatedAt: Date
    public var canStart: Bool                 // a Docker endpoint is configured

    public init(server: Server, containers: [Container], netIn: [Double] = [], netOut: [Double] = [],
                history: [Sample] = [], events: [PulseEvent] = [], updatedAt: Date, canStart: Bool = false) {
        self.server = server
        self.containers = containers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.netIn = netIn; self.netOut = netOut; self.history = history; self.events = events
        self.updatedAt = updatedAt; self.canStart = canStart
    }

    public var running: Int { containers.filter(\.isRunning).count }
    public var total: Int { containers.count }
    public var stopped: [Container] { containers.filter { $0.state == .stopped } }
    public var problems: [Container] {
        containers.filter(\.needsAttention).sorted { ($0.state == .unhealthy ? 0 : 1) < ($1.state == .unhealthy ? 0 : 1) }
    }
    public var healthyCount: Int { containers.filter { $0.health == .healthy }.count }
    public var noCheckCount: Int { containers.filter { $0.health == .none && $0.state == .running }.count }
}
