import Foundation

public enum StatusLevel: String, Codable, Sendable { case healthy, warning, offline, connecting }   // connecting: just woke up, no answer yet — unknown, not down

public struct Status: Sendable, Equatable {
    public var level: StatusLevel
    public var reasons: [String]
    public init(level: StatusLevel, reasons: [String]) { self.level = level; self.reasons = reasons }
}

public enum Thresholds {
    public static let offlineAfter: TimeInterval = 60
    public static let offlineAlertAfter: TimeInterval = 180
    public static let reconnectGrace: TimeInterval = 90
    public static let sustainedCPU: TimeInterval = 300

    public static let cpuWarn = 90.0, cpuCrit = 98.0
    public static let ramWarn = 90.0, ramCrit = 95.0
    public static let diskWarn = 85.0, diskCrit = 95.0
    public static let tempWarn = 85.0
}

public enum Metric: Sendable { case cpu, ram, disk }
public enum Severity: Sendable { case normal, warning, critical }

public enum StatusEngine {
    /// Ring colour level. CPU warns only when sustained, so callers pass `cpuSustained`.
    public static func severity(_ metric: Metric, value: Double, cpuSustained: Bool = true) -> Severity {
        switch metric {
        case .cpu:
            if value > Thresholds.cpuCrit { return .critical }
            return value > Thresholds.cpuWarn && cpuSustained ? .warning : .normal
        case .ram:
            if value > Thresholds.ramCrit { return .critical }
            return value > Thresholds.ramWarn ? .warning : .normal
        case .disk:
            if value > Thresholds.diskCrit { return .critical }
            return value > Thresholds.diskWarn ? .warning : .normal
        }
    }

    /// True when every reading over the last 5 minutes is above the CPU warning line
    /// and the readings actually cover 5 minutes.
    public static func cpuSustainedHigh(current: Double, history: [Sample], now: Date) -> Bool {
        guard current > Thresholds.cpuWarn else { return false }
        let window = history.filter { now.timeIntervalSince($0.time) <= Thresholds.sustainedCPU }
        guard let oldest = window.map(\.time).min(),
              now.timeIntervalSince(oldest) >= Thresholds.sustainedCPU - 1 else { return false }
        return window.allSatisfy { $0.cpu > Thresholds.cpuWarn }
    }

    public static func isOffline(lastSeen: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastSeen) > Thresholds.offlineAfter
    }

    public static func evaluate(_ snap: Snapshot, treatStoppedAsWarning: Bool, now: Date) -> Status {
        let s = snap.server
        if !s.online || isOffline(lastSeen: s.lastSeen, now: now) {
            return Status(level: .offline, reasons: ["\(s.name) unreachable"])
        }
        var reasons: [String] = []
        let unhealthy = snap.containers.filter { $0.state == .unhealthy }
        if !unhealthy.isEmpty { reasons.append("\(unhealthy.count) unhealthy") }
        if cpuSustainedHigh(current: s.cpu, history: snap.history, now: now) { reasons.append("CPU above 90%") }
        if s.ram > Thresholds.ramWarn { reasons.append("Memory above 90%") }
        if s.disk > Thresholds.diskWarn { reasons.append("Disk above 85%") }
        if let t = s.cpuTempC, t > Thresholds.tempWarn { reasons.append("Temperature above 85°C") }
        if treatStoppedAsWarning, !snap.stopped.isEmpty { reasons.append("\(snap.stopped.count) stopped") }
        return Status(level: reasons.isEmpty ? .healthy : .warning, reasons: reasons)
    }
}
