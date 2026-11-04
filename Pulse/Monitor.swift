import Foundation
import Observation
import PulseKit
import WidgetKit

/// Polls the server (5 s while the popover is open, 30 s otherwise), keeps history and events,
/// publishes the snapshot for the UI and the widgets, and drives notifications.
@MainActor @Observable
final class Monitor {
    private(set) var snapshot: Snapshot?
    private(set) var status = Status(level: .offline, reasons: ["Not connected yet"])
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    var popoverOpen = false { didSet { if popoverOpen != oldValue { restartLoop() } } }

    private var history = Store.loadHistory()
    private var source: ServerDataSource?
    private var lastSuccess: Date?
    private var loop: Task<Void, Never>?
    private var lastWidgetReload = Date.distantPast
    private var lastWidgetKey = ""
    private let notifier = Notifier()
    private var defaultsObserver: NSObjectProtocol?

    init() {
        snapshot = Store.loadSnapshot()
        lastSuccess = snapshot.map(\.server.lastSeen)
        if let snapshot { status = StatusEngine.evaluate(snapshot, treatStoppedAsWarning: prefs.bool(forKey: Pref.stoppedIsWarning), now: .now) }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    var prefs: UserDefaults { AppGroup.defaults }

    func start() {
        notifier.requestAuthorization()
        restartLoop()
    }

    /// Credentials or endpoints changed: rebuild the source on the next poll.
    func resetSource() { source = nil; restartLoop() }

    private var lastSettingsKey = ""
    private func settingsChanged() {
        let keys = [Pref.source, Pref.displayName, Pref.beszelURL, Pref.beszelEmail, Pref.beszelSystem, Pref.dockerURL,
                    Pref.proxmoxURL, Pref.proxmoxNode, Pref.proxmoxTokenID, Pref.proxmoxInsecure]
        let key = keys.map { "\(prefs.object(forKey: $0) ?? "")" }.joined(separator: "|")
        if key != lastSettingsKey, !lastSettingsKey.isEmpty { source = nil }
        lastSettingsKey = key
        if let snapshot { status = StatusEngine.evaluate(snapshot, treatStoppedAsWarning: prefs.bool(forKey: Pref.stoppedIsWarning), now: .now) }
        reloadWidgets(force: false)
    }

    private func restartLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval: Duration = (self?.popoverOpen ?? false) ? .seconds(5) : .seconds(30)
                try? await Task.sleep(for: interval)
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let now = Date.now
        do {
            if source == nil { source = try makeSource() }
            guard let source else { return }
            let reading = try await source.fetch()
            lastError = nil
            apply(reading, now: now)
        } catch {
            if lastError != error.localizedDescription { NSLog("Pulse: refresh failed: \(error)") }
            lastError = error.localizedDescription
            markUnreachable(now: now)
        }
    }

    func startContainer(_ name: String) {
        Task {
            do {
                try await source?.start(name)
                try? await Task.sleep(for: .seconds(1))
                await refresh()
            } catch {
                lastError = "Could not start \(name): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Applying readings

    private func apply(_ reading: Reading, now: Date) {
        let previous = snapshot
        var server = reading.server
        if server.online { server.lastSeen = now; lastSuccess = now }

        let wasOffline = previous.map { !$0.server.online || StatusEngine.isOffline(lastSeen: $0.server.lastSeen, now: now) } ?? false
        var newEvents: [PulseEvent] = []
        if wasOffline, server.online, let prev = previous {
            newEvents.append(PulseEvent(id: "online-\(Int(now.timeIntervalSince1970))", time: now,
                                        text: "\(server.name) back online", kind: .online))
            notifier.backOnline(server: server.name, downFor: now.timeIntervalSince(prev.server.lastSeen),
                                running: reading.containers.filter(\.isRunning).count, total: reading.containers.count)
        }

        history = Store.appending(Sample(time: now, cpu: server.cpu, ram: server.ram, disk: server.disk, temp: server.cpuTempC), to: history)
        newEvents += EventDetector.detect(previous: previous?.containers, current: reading, samples: history.samples,
                                          existing: history.events, now: now)
        history.events = EventDetector.merge(history.events, newEvents)
        Store.save(history)

        let netIn = Array(((previous?.netIn ?? []) + [server.netInBps]).suffix(12))
        let netOut = Array(((previous?.netOut ?? []) + [server.netOutBps]).suffix(12))
        let day = history.samples.filter { now.timeIntervalSince($0.time) <= 86400 }
        let snap = Snapshot(server: server, containers: reading.containers, netIn: netIn, netOut: netOut,
                            history: day, events: history.events, updatedAt: now, canStart: reading.canStart)
        publish(snap, previous: previous, now: now)
    }

    private func markUnreachable(now: Date) {
        guard var snap = snapshot else { status = Status(level: .offline, reasons: [lastError ?? "Unreachable"]); return }
        let since = lastSuccess ?? snap.server.lastSeen
        if StatusEngine.isOffline(lastSeen: since, now: now) {
            if snap.server.online {
                history.events = EventDetector.merge(history.events, [PulseEvent(
                    id: "offline-\(Int(since.timeIntervalSince1970))", time: since,
                    text: "\(snap.server.name) unreachable", kind: .offline)])
                Store.save(history)
            }
            snap.server.online = false
            snap.server.lastSeen = since
            snap.events = history.events
        }
        let previous = snapshot
        publish(snap, previous: previous, now: now)
        if now.timeIntervalSince(since) >= Thresholds.offlineAlertAfter {
            notifier.unreachable(snap, since: since, style: prefs.value(Pref.style, default: PulseStyle.halo), events: history.events)
        }
    }

    private func publish(_ snap: Snapshot, previous: Snapshot?, now: Date) {
        snapshot = snap
        status = StatusEngine.evaluate(snap, treatStoppedAsWarning: prefs.bool(forKey: Pref.stoppedIsWarning), now: now)
        Store.save(snap)
        notifier.containerChanges(previous: previous?.containers, current: snap.containers, server: snap.server.name,
                                  alertStopped: prefs.bool(forKey: Pref.alertStopped),
                                  alertUnhealthy: prefs.bool(forKey: Pref.alertUnhealthy))
        reloadWidgets(force: false)
    }

    /// WidgetKit has a refresh budget: reload on visible changes, at most every 10 min otherwise.
    func reloadWidgets(force: Bool) {
        guard let s = snapshot else { return }
        let key = [status.level.rawValue, "\(s.running)/\(s.total)", prefs.string(forKey: Pref.style) ?? "",
                   prefs.string(forKey: Pref.containerRing) ?? "", "\(prefs.bool(forKey: Pref.widgetsFollowStyle))"].joined(separator: "|")
        let now = Date.now
        if force || key != lastWidgetKey || now.timeIntervalSince(lastWidgetReload) > 600 {
            lastWidgetKey = key
            lastWidgetReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Source

    private func makeSource() throws -> ServerDataSource {
        let d = prefs
        let name = d.string(forKey: Pref.displayName)
        let docker = url(d.string(forKey: Pref.dockerURL)).map { DockerClient(base: $0) }
        switch d.value(Pref.source, default: SourceKind.beszel) {
        case .beszel:
            guard let base = url(d.string(forKey: Pref.beszelURL)) else { throw SourceError.notConfigured("Beszel hub URL") }
            return BeszelSource(base: base, email: d.string(forKey: Pref.beszelEmail) ?? "",
                                password: Keychain.get(Keychain.beszelPassword) ?? "",
                                systemName: d.string(forKey: Pref.beszelSystem), displayName: name, docker: docker)
        case .direct:
            guard let base = url(d.string(forKey: Pref.proxmoxURL)) else { throw SourceError.notConfigured("Proxmox URL") }
            return ProxmoxSource(base: base, node: d.string(forKey: Pref.proxmoxNode), tokenID: d.string(forKey: Pref.proxmoxTokenID) ?? "",
                                 secret: Keychain.get(Keychain.proxmoxSecret) ?? "", insecure: d.bool(forKey: Pref.proxmoxInsecure),
                                 displayName: name, docker: docker)
        }
    }

    private func url(_ s: String?) -> URL? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty, let u = URL(string: s), u.scheme != nil else { return nil }
        return u
    }
}
