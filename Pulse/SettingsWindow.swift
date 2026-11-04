import AppKit
import PulseKit
import ServiceManagement
import SwiftUI

/// 640 pt settings window with toolbar tabs (General, Servers, Appearance, Alerts).
@MainActor
final class SettingsWindowController: NSWindowController {
    init(monitor: Monitor) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        func tab<V: View>(_ title: String, _ symbol: String, _ view: V) -> NSTabViewItem {
            let host = NSHostingController(rootView: view.frame(width: 640))
            host.sizingOptions = [.preferredContentSize]
            host.title = title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            return item
        }
        tabs.addTabViewItem(tab("General", "gearshape", GeneralTab(monitor: monitor)))
        tabs.addTabViewItem(tab("Servers", "server.rack", ServersTab(monitor: monitor)))
        tabs.addTabViewItem(tab("Appearance", "circle.lefthalf.filled", AppearanceTab(monitor: monitor)))
        tabs.addTabViewItem(tab("Alerts", "bell", AlertsTab(monitor: monitor)))
        tabs.selectedTabViewItemIndex = 2
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        window?.center()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Shared layout

/// Grouped list: fill background, radius 14, 0.5 pt separators inset 14.
struct GroupedList<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Rectangle().fill(p.separator).frame(height: 0.5).padding(.horizontal, 14) }
                    row.padding(.horizontal, 14).frame(minHeight: 44)
                }
            }
        }
        .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).pulseFont(13).foregroundStyle(p.text)
                if let subtitle { Text(subtitle).pulseFont(11).foregroundStyle(p.text3) }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 6)
    }
}

struct TabPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct SectionTitle: View {
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View { Text(text).pulseFont(13, .semibold).foregroundStyle(Palette(scheme).text) }
}

// MARK: - Appearance

struct AppearanceTab: View {
    let monitor: Monitor
    @AppStorage(Pref.style, store: AppGroup.defaults) private var style = PulseStyle.halo
    @AppStorage(Pref.containerRing, store: AppGroup.defaults) private var ring = ContainerRing.ticks
    @AppStorage(Pref.iconMode, store: AppGroup.defaults) private var iconMode = IconMode.status
    @AppStorage(Pref.widgetsFollowStyle, store: AppGroup.defaults) private var widgetsFollow = true
    @AppStorage(Pref.stoppedIsWarning, store: AppGroup.defaults) private var stoppedWarns = false
    @AppStorage(Pref.appearance, store: AppGroup.defaults) private var appearance = AppearanceMode.system

    var body: some View {
        TabPage {
            SectionTitle(text: "Style")
            HStack(spacing: 10) {
                ForEach(PulseStyle.allCases, id: \.self) { s in
                    StyleCard(style: s, selected: style == s) {
                        style = s
                        monitor.reloadWidgets(force: true)
                    }
                }
            }
            GroupedList {
                SettingRow(title: "Container ring", subtitle: "Halo style only") {
                    Picker("", selection: $ring) {
                        Text("Segments").tag(ContainerRing.segments); Text("Ticks").tag(ContainerRing.ticks)
                        Text("Beads").tag(ContainerRing.beads); Text("Inner").tag(ContainerRing.inner)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().disabled(style != .halo)
                }
                SettingRow(title: "Menu bar icon") {
                    Picker("", selection: $iconMode) { Text("Status").tag(IconMode.status); Text("Live values").tag(IconMode.live) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                SettingRow(title: "Widgets follow this style") { Toggle("", isOn: $widgetsFollow).toggleStyle(.switch).labelsHidden() }
                SettingRow(title: "Treat stopped containers as a warning") { Toggle("", isOn: $stoppedWarns).toggleStyle(.switch).labelsHidden() }
                SettingRow(title: "Appearance") {
                    Picker("", selection: $appearance) {
                        Text("System").tag(AppearanceMode.system); Text("Light").tag(AppearanceMode.light); Text("Dark").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
        }
        .onChange(of: ring) { monitor.reloadWidgets(force: true) }
        .onChange(of: widgetsFollow) { monitor.reloadWidgets(force: true) }
    }
}

struct StyleCard: View {
    let style: PulseStyle, selected: Bool, action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme)
        let (name, caption) = Self.names[style]!
        Button(action: action) {
            VStack(spacing: 0) {
                StylePreview(style: style).frame(height: 68)
                Text(name).pulseFont(12, .semibold).foregroundStyle(p.text).padding(.top, 10)
                Text(caption).pulseFont(11).foregroundStyle(p.text3)
            }
            .padding(.top, 16).padding(.horizontal, 8).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .background(p.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? p.blue : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(caption)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static let names: [PulseStyle: (String, String)] = [
        .rings: ("Rings", "Capacity"), .halo: ("Halo", "+ containers"),
        .memory: ("Memory", "+ 24 h peaks"), .live: ("Live", "By stack"),
    ]
}

/// 68 pt hero thumbnails, drawn from the reference data.
struct StylePreview: View {
    let style: PulseStyle
    var body: some View {
        let snap = Fixtures.snapshot()
        switch style {
        case .rings: TripleRings(server: snap.server, size: 68, radii: (30, 22.5, 15), stroke: 7)
        case .halo:
            HaloDrawing(snap: snap, variant: .segments, size: 68,
                        geometry: HaloGeometry(haloRadius: 84, haloStroke: 9, rings: (64, 49, 34), ringStroke: 15), showCount: false)
        case .memory: TripleRings(server: snap.server, size: 68, radii: (30, 22.5, 15), stroke: 7, peaks: (71, 63, 61), peakStroke: 9)
        case .live:
            HStack(spacing: 5) {
                ForEach([(snap.server.cpu, Metric.cpu), (snap.server.ram, .ram), (snap.server.disk, .disk)], id: \.0) { v, m in
                    MiniRing(value: v, metric: m)
                }
            }
        }
    }
}

private struct MiniRing: View {
    let value: Double, metric: Metric
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        Ring(value: value, radius: 11, stroke: 3, color: p.ring(metric).0, track: p.ring(metric).1).frame(width: 26, height: 26)
    }
}

// MARK: - General

struct GeneralTab: View {
    let monitor: Monitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        TabPage {
            GroupedList {
                SettingRow(title: "Launch at login", subtitle: loginError) {
                    Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
                SettingRow(title: "Refresh", subtitle: "Every 5 s while the popover is open, every 30 s otherwise") {
                    Button("Refresh Now") { Task { await monitor.refresh() } }
                }
                SettingRow(title: "Last update", subtitle: monitor.lastError) {
                    Text(monitor.snapshot.map { Format.updated($0.updatedAt) } ?? "Never").pulseFont(12).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: launchAtLogin) { _, on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = error.localizedDescription
            }
        }
    }
}

// MARK: - Servers

struct ServersTab: View {
    let monitor: Monitor
    @AppStorage(Pref.source, store: AppGroup.defaults) private var source = SourceKind.beszel
    @AppStorage(Pref.displayName, store: AppGroup.defaults) private var displayName = ""
    @AppStorage(Pref.beszelURL, store: AppGroup.defaults) private var beszelURL = ""
    @AppStorage(Pref.beszelEmail, store: AppGroup.defaults) private var beszelEmail = ""
    @AppStorage(Pref.beszelSystem, store: AppGroup.defaults) private var beszelSystem = ""
    @AppStorage(Pref.dockerURL, store: AppGroup.defaults) private var dockerURL = ""
    @AppStorage(Pref.proxmoxURL, store: AppGroup.defaults) private var proxmoxURL = ""
    @AppStorage(Pref.proxmoxNode, store: AppGroup.defaults) private var proxmoxNode = ""
    @AppStorage(Pref.proxmoxTokenID, store: AppGroup.defaults) private var proxmoxTokenID = ""
    @AppStorage(Pref.proxmoxInsecure, store: AppGroup.defaults) private var proxmoxInsecure = true
    @State private var password = Keychain.get(Keychain.beszelPassword) ?? ""
    @State private var secret = Keychain.get(Keychain.proxmoxSecret) ?? ""
    @State private var testing = false

    var body: some View {
        TabPage {
            if let snap = monitor.snapshot, monitor.lastError == nil { ConnectedCard(snap: snap, status: monitor.status) }
            GroupedList {
                SettingRow(title: "Name") { field("homelab", $displayName) }
                SettingRow(title: "Source") {
                    Picker("", selection: $source) { Text("Beszel hub").tag(SourceKind.beszel); Text("Proxmox + Docker").tag(SourceKind.direct) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            if source == .beszel {
                SectionTitle(text: "Beszel hub")
                GroupedList {
                    SettingRow(title: "Hub URL") { field("http://host:8090", $beszelURL) }
                    SettingRow(title: "Email") { field("you@example.com", $beszelEmail) }
                    SettingRow(title: "Password", subtitle: "Stored in the Keychain") {
                        SecureField("", text: $password).textFieldStyle(.roundedBorder).frame(width: 260)
                    }
                    SettingRow(title: "System", subtitle: "Blank = first system on the hub") { field("hömelab", $beszelSystem) }
                }
            } else {
                SectionTitle(text: "Proxmox VE")
                GroupedList {
                    SettingRow(title: "API URL") { field("https://host:8006", $proxmoxURL) }
                    SettingRow(title: "Node", subtitle: "Blank = first node") { field("pve", $proxmoxNode) }
                    SettingRow(title: "Token ID") { field("pulse@pve!monitor", $proxmoxTokenID) }
                    SettingRow(title: "Token secret", subtitle: "Stored in the Keychain") {
                        SecureField("", text: $secret).textFieldStyle(.roundedBorder).frame(width: 260)
                    }
                    SettingRow(title: "Accept self-signed certificate") { Toggle("", isOn: $proxmoxInsecure).toggleStyle(.switch).labelsHidden() }
                }
            }
            SectionTitle(text: "Docker")
            GroupedList {
                SettingRow(title: "Engine API", subtitle: "Socket proxy allowing list, inspect and start") { field("http://host:8772", $dockerURL) }
                if source == .beszel {
                    SettingRow(title: "Open Proxmox link") { field("https://host:8006", $proxmoxURL) }
                }
            }
            HStack {
                Button(testing ? "Connecting…" : "Save and Connect") { save() }.disabled(testing)
                if let err = monitor.lastError { Text(err).pulseFont(11).foregroundStyle(.orange).lineLimit(2) }
            }
        }
    }

    private func field(_ prompt: String, _ text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(prompt)).textFieldStyle(.roundedBorder).frame(width: 260)
    }

    private func save() {
        Keychain.set(password, for: Keychain.beszelPassword)
        Keychain.set(secret, for: Keychain.proxmoxSecret)
        testing = true
        monitor.resetSource()
        Task { await monitor.refresh(); testing = false }
    }
}

/// Live summary shown once the source answers: mini halo, machine, container count, freshness.
struct ConnectedCard: View {
    let snap: Snapshot, status: Status
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        let dot = status.level == .healthy ? p.green : status.level == .warning ? p.orange : p.red
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 16) {
                HaloDrawing(snap: snap, variant: .segments, size: 64, showCount: false).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snap.server.name).pulseFont(17, .semibold).foregroundStyle(p.text)
                    Text("\(snap.server.cpuModel) · \(snap.server.cores) cores · up \(Format.uptime(snap.server.uptime))")
                        .pulseFont(12).foregroundStyle(p.text2)
                    HStack(spacing: 6) {
                        Circle().fill(dot).frame(width: 7, height: 7)
                        Text(status.level == .healthy ? "Connected · \(snap.running) of \(snap.total) running"
                                                      : status.reasons.joined(separator: " · "))
                        Text("· " + Format.updated(snap.updatedAt, now: ctx.date)).foregroundStyle(p.text3)
                    }
                    .pulseFont(12).foregroundStyle(p.text2)
                }
                Spacer()
            }
            .padding(16)
            .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Alerts

struct AlertsTab: View {
    let monitor: Monitor
    @AppStorage(Pref.alertOffline, store: AppGroup.defaults) private var offline = true
    @AppStorage(Pref.alertBackOnline, store: AppGroup.defaults) private var back = true
    @AppStorage(Pref.alertUnhealthy, store: AppGroup.defaults) private var unhealthy = true
    @AppStorage(Pref.alertStopped, store: AppGroup.defaults) private var stopped = false
    @AppStorage(Pref.style, store: AppGroup.defaults) private var style = PulseStyle.halo

    var body: some View {
        TabPage {
            GroupedList {
                SettingRow(title: "Server unreachable", subtitle: "After 3 minutes without a response") { toggle($offline) }
                SettingRow(title: "Server back online") { toggle($back) }
                SettingRow(title: "Container becomes unhealthy") { toggle($unhealthy) }
                SettingRow(title: "Container stops unexpectedly", subtitle: "Exits with a non-zero code") { toggle($stopped) }
            }
            HStack {
                Button("Send Test Alert") { Notifier().sendTest(server: monitor.snapshot?.server.name ?? "homelab", style: style) }
                Text("Repeats of the same alert wait 15 minutes.").pulseFont(11).foregroundStyle(.secondary)
            }
        }
    }

    private func toggle(_ b: Binding<Bool>) -> some View { Toggle("", isOn: b).toggleStyle(.switch).labelsHidden() }
}
