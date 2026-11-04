import AppKit
import PulseKit
@preconcurrency import UserNotifications

/// Offline / back online / unhealthy / stopped alerts, grouped by server, 15-minute cool-down per alert.
@MainActor
final class Notifier {
    static let cooldown: TimeInterval = 15 * 60
    private var lastSent: [String: Date] = [:]
    private var alertedOutage: Date?
    private var prefs: UserDefaults { AppGroup.defaults }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Pulse: notification authorization failed: \(error)") }
        }
    }

    func unreachable(_ snap: Snapshot, since: Date, style: PulseStyle, events: [PulseEvent]) {
        guard prefs.bool(forKey: Pref.alertOffline), alertedOutage != since else { return }
        alertedOutage = since
        let mins = max(3, Int(Date.now.timeIntervalSince(since) / 60))
        var body = "No response since \(Format.clock(since)). Last reading: \(snap.running) of \(snap.total) containers running."
        if style == .memory, let pattern = Self.outagePattern(events, now: .now) { body = "No response since \(Format.clock(since)). \(pattern)" }
        send(key: "offline", title: "\(snap.server.name) unreachable for \(mins) min", body: body,
             server: snap.server.name, glyph: style, cooldown: false)
    }

    func backOnline(server: String, downFor: TimeInterval, running: Int, total: Int) {
        alertedOutage = nil
        guard prefs.bool(forKey: Pref.alertBackOnline), downFor >= Thresholds.offlineAlertAfter else { return }
        send(key: "online", title: "\(server) is back · down \(Int(downFor / 60)) min",
             body: "\(running) of \(total) containers running.", server: server, glyph: nil, cooldown: false)
    }

    func containerChanges(previous: [Container]?, current: [Container], server: String, alertStopped: Bool, alertUnhealthy: Bool) {
        guard let previous else { return }
        let before = Dictionary(previous.map { ($0.name, $0.state) }, uniquingKeysWith: { a, _ in a })
        for c in current {
            guard let old = before[c.name], old != c.state else { continue }
            if c.state == .unhealthy, alertUnhealthy {
                send(key: "unhealthy-\(c.name)", title: "\(c.name) is unhealthy", body: "\(server) · health check failing",
                     server: server, glyph: nil)
            }
            // "Unexpectedly": it was running and exited with a non-zero code.
            if c.state == .stopped, old == .running, alertStopped, (c.exitCode ?? 1) != 0 {
                send(key: "stopped-\(c.name)", title: "\(c.name) stopped",
                     body: "\(server) · " + (c.exitCode.map { "Exited (\($0))" } ?? "Exited"), server: server, glyph: nil)
            }
        }
    }

    /// "Third outage this week, all after 14:00."
    static func outagePattern(_ events: [PulseEvent], now: Date) -> String? {
        let week = events.filter { $0.kind == .offline && now.timeIntervalSince($0.time) < 7 * 86400 }
        guard week.count >= 2 else { return nil }
        let ordinals = ["", "First", "Second", "Third", "Fourth", "Fifth"]
        let n = week.count
        var text = (n < ordinals.count ? ordinals[n] : "\(n)th") + " outage this week"
        let hours = week.map { Calendar.current.component(.hour, from: $0.time) }
        if let minHour = hours.min(), minHour >= 6 { text += ", all after \(String(format: "%02d", minHour)):00" }
        return text + "."
    }

    private func send(key: String, title: String, body: String, server: String, glyph: PulseStyle?, cooldown: Bool = true) {
        let now = Date.now
        if cooldown, let last = lastSent[key], now.timeIntervalSince(last) < Self.cooldown { return }
        lastSent[key] = now
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = server
        content.sound = .default
        if let glyph, let att = Self.attachment(style: glyph) { content.attachments = [att] }
        let req = UNNotificationRequest(identifier: "\(key)-\(Int(now.timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error { NSLog("Pulse: notification failed: \(error)") }
        }
    }

    private static func attachment(style: PulseStyle) -> UNNotificationAttachment? {
        let kind: MenuBarIcon.Kind = style == .live ? .live(cpu: 0, ram: 0, disk: 0) : style == .halo ? .halo : .rings
        let img = MenuBarIcon.notificationTile(kind)
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-offline-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: "glyph", url: url)
        } catch {
            NSLog("Pulse: attachment failed: \(error)")
            return nil
        }
    }

    func sendTest(server: String, style: PulseStyle) {
        send(key: "test", title: "\(server) unreachable for 3 min",
             body: "No response since \(Format.clock(.now.addingTimeInterval(-180))). This is a test alert.",
             server: server, glyph: style, cooldown: false)
    }
}
