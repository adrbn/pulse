import Foundation

public enum Format {
    /// "4 h 06 m", "2 d 3 h", "12 m"
    public static func uptime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, h = m / 60, d = h / 24
        if d > 0 { return "\(d) d \(h % 24) h" }
        if h > 0 { return "\(h) h " + String(format: "%02d m", m % 60) }
        return "\(m) m"
    }

    /// "2 h ago", "5 min ago", "just now"
    public static func ago(_ date: Date, now: Date = .now) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return s < 10 ? "just now" : "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }

    /// "Updated 5 s ago"
    public static func updated(_ date: Date, now: Date = .now) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "Updated \(s) s ago" }
        return "Updated " + ago(date, now: now)
    }

    /// Splits a rate into value and unit: (2.4, "MB/s"), (310, "KB/s").
    public static func rate(_ bps: Double) -> (value: String, unit: String) {
        switch bps {
        case ..<1_000: return (String(format: "%.0f", bps), "B/s")
        case ..<1_000_000: let k = bps / 1_000; return (k < 10 ? String(format: "%.1f", k) : String(format: "%.0f", k), "KB/s")
        case ..<1_000_000_000: let m = bps / 1_000_000; return (m < 10 ? String(format: "%.1f", m) : String(format: "%.0f", m), "MB/s")
        default: return (String(format: "%.1f", bps / 1_000_000_000), "GB/s")
        }
    }

    public static func rateString(_ bps: Double) -> String { let r = rate(bps); return "\(r.value) \(r.unit)" }

    public static func pct(_ v: Double) -> String { String(format: "%.0f", v.rounded()) }

    public static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    public static func load(_ v: Double) -> String { String(format: "%.2f", v) }

    public static func containerDetail(_ c: Container, now: Date = .now) -> String {
        switch c.state {
        case .stopped:
            let code = c.exitCode.map { "Exited (\($0))" } ?? "Stopped"
            return c.stoppedAt.map { "\(code) · \(ago($0, now: now))" } ?? code
        case .unhealthy: return "Unhealthy"
        case .restarting: return "Restarting"
        case .running: return String(format: "%.1f%% CPU", c.cpu)
        }
    }
}
