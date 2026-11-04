import SwiftUI

/// What the popover can ask the app to do.
public struct PopoverActions {
    public var start: (String) -> Void
    public var openProxmox: () -> Void
    public var openSettings: () -> Void
    public init(start: @escaping (String) -> Void = { _ in }, openProxmox: @escaping () -> Void = {},
                openSettings: @escaping () -> Void = {}) {
        self.start = start; self.openProxmox = openProxmox; self.openSettings = openSettings
    }
}

/// Header line 2: "● Online · up 4 h 06 m".
struct StatusLine: View {
    let snap: Snapshot
    let status: Status
    let now: Date
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        let (color, text): (Color, String) = switch status.level {
        case .healthy: (p.green, "Online · up \(Format.uptime(snap.server.uptime))")
        case .warning: (p.orange, "Warning · " + (status.reasons.first ?? "check containers"))
        case .offline: (p.red, "Offline · last seen \(Format.ago(snap.server.lastSeen, now: now))")
        }
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).pulseFont(12).foregroundStyle(p.text2)
        }
    }
}

struct Header<Accessory: View>: View {
    let snap: Snapshot, status: Status, now: Date
    @ViewBuilder var accessory: Accessory
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snap.server.name).pulseFont(15, .semibold).foregroundStyle(p.text)
                StatusLine(snap: snap, status: status, now: now)
            }
            Spacer(minLength: 8)
            accessory
        }
        .accessibilityElement(children: .combine)
    }
}

struct Footer: View {
    let updated: Date, now: Date
    var link: String? = nil            // Memory style: "All containers ›"
    var linkAction: () -> Void = {}
    let actions: PopoverActions
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        VStack(spacing: 10) {
            Rectangle().fill(p.separator).frame(height: 0.5)
            HStack(spacing: 14) {
                Text(Format.updated(updated, now: now))
                Spacer()
                if let link { Button(link, action: linkAction).buttonStyle(.plain) }
                icon("server.rack", "Open Proxmox", actions.openProxmox)
                icon("gearshape", "Settings", actions.openSettings)
            }
            .pulseFont(11).foregroundStyle(p.text3)
            .padding(.horizontal, 4)
        }
    }

    private func icon(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).frame(width: 18, height: 18) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

/// Legend entry: dot + label, then a big value.
struct LegendItem: View {
    let color: Color, label: String, value: String, unit: String, size: CGFloat
    var note: String? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).pulseFont(11).foregroundStyle(p.text2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                ValueUnit(value, unit, size: size, unitSize: 11)
                if let note { Text(note).pulseFont(11).foregroundStyle(p.text3) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var size: CGFloat = 13
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        HStack {
            Text(text).pulseFont(size, .semibold).foregroundStyle(size == 12 ? p.text2 : p.text)
            Spacer()
            if let trailing { Text(trailing).pulseFont(12).foregroundStyle(p.text2) }
        }
        .padding(.horizontal, 4)
    }
}

/// 8 pt dot: green when running, hollow when stopped, orange when unhealthy.
struct StateDot: View {
    let state: ContainerState
    var size: CGFloat = 8
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        switch state {
        case .running: Circle().fill(p.green).frame(width: size, height: size)
        case .stopped: Circle().stroke(p.text3, lineWidth: 1.2).frame(width: size - 1.2, height: size - 1.2).frame(width: size, height: size)
        case .unhealthy, .restarting: Circle().fill(p.orange).frame(width: size, height: size)
        }
    }
}

/// Blue capsule "Start" button.
struct StartPill: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        Button(action: action) {
            Text("Start").pulseFont(12, .semibold).foregroundStyle(.white)
                .padding(.vertical, 5).padding(.horizontal, 12)
                .background(p.blue, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start container")
    }
}

/// Full container list, grouped by stack, problems first.
struct AllContainers: View {
    let snap: Snapshot
    let now: Date
    let actions: PopoverActions
    let back: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: back) {
                    HStack(spacing: 3) { Image(systemName: "chevron.left"); Text("Back") }
                        .pulseFont(13).foregroundStyle(p.blue)
                }.buttonStyle(.plain)
                Spacer()
                Text("\(snap.running) of \(snap.total) running").pulseFont(12).foregroundStyle(p.text2)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Stacks.group(snap.containers), id: \.name) { stack in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(stack.name).pulseFont(12, .semibold).foregroundStyle(p.text2)
                            ForEach(stack.containers) { c in
                                HStack(spacing: 8) {
                                    StateDot(state: c.state)
                                    Text(c.name).pulseFont(13).foregroundStyle(p.text).lineLimit(1)
                                    Spacer()
                                    Text(Format.containerDetail(c, now: now)).pulseFont(12).foregroundStyle(p.text3)
                                    if c.state == .stopped, snap.canStart {
                                        Button("Start") { actions.start(c.name) }.buttonStyle(.plain)
                                            .pulseFont(12).foregroundStyle(p.blue)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 440)
        }
    }
}

public enum Stacks {
    public struct Stack: Equatable {
        public var name: String
        public var containers: [Container]
        public var running: Int { containers.filter(\.isRunning).count }
        public var hasProblem: Bool { containers.contains(where: \.needsAttention) }
    }

    /// Problem stacks first, then larger stacks, "other" last. One-container stacks fold into "other"
    /// (standalone `docker run` containers each get their own project name otherwise).
    public static func group(_ containers: [Container]) -> [Stack] {
        let sizes = Dictionary(grouping: containers, by: \.stack).mapValues(\.count)
        return Dictionary(grouping: containers, by: { sizes[$0.stack] == 1 ? "other" : $0.stack })
            .map { Stack(name: $0.key, containers: $0.value.sorted { $0.name < $1.name }) }
            .sorted { a, b in
                if a.hasProblem != b.hasProblem { return a.hasProblem }
                if (a.name == "other") != (b.name == "other") { return b.name == "other" }
                if a.containers.count != b.containers.count { return a.containers.count > b.containers.count }
                return a.name < b.name
            }
    }
}
