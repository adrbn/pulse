import SwiftUI

public enum WidgetSize: Sendable { case small, medium }

/// Widget content for every style. The widget extension wraps it in `containerBackground`.
public struct PulseWidgetView: View {
    let snap: Snapshot
    let status: Status
    let style: PulseStyle
    let variant: ContainerRing
    let size: WidgetSize
    let now: Date

    public init(snap: Snapshot, status: Status, style: PulseStyle, variant: ContainerRing, size: WidgetSize, now: Date) {
        self.snap = snap; self.status = status; self.style = style; self.variant = variant; self.size = size; self.now = now
    }

    public var body: some View {
        switch (style, size) {
        case (.halo, .small): HaloSmall(snap: snap, status: status, variant: variant, now: now)
        case (.halo, .medium): HaloMedium(snap: snap, status: status, variant: variant, now: now)
        case (.rings, .small): RingsSmall(snap: snap, status: status, now: now)
        case (.rings, .medium): RingsMedium(snap: snap, status: status, now: now)
        case (.memory, .small): MemorySmall(snap: snap, status: status, now: now)
        case (.memory, .medium): MemoryMedium(snap: snap, status: status, now: now)
        case (.live, .small): LiveSmall(snap: snap, status: status, now: now)
        case (.live, .medium): LiveMedium(snap: snap, status: status, now: now)
        }
    }
}

/// One-line widget status that never relies on colour alone.
enum WidgetText {
    static func summary(_ snap: Snapshot, _ status: Status, now: Date, healthyText: String) -> String {
        switch status.level {
        case .offline: return "Offline · \(Format.ago(snap.server.lastSeen, now: now))"
        case .warning: return status.reasons.first.map { "Warning · \($0)" } ?? "Warning"
        // WidgetKit can delay reloads: say how old the data is rather than look live.
        case .healthy: return now.timeIntervalSince(snap.updatedAt) > 1200 ? "Updated \(Format.ago(snap.updatedAt, now: now))" : healthyText
        }
    }

    /// Several problems take turns, one every 3 s of `now`, so every name shows up.
    static func problemsLine(_ snap: Snapshot, now: Date) -> String? {
        let p = snap.problems
        guard !p.isEmpty else { return nil }
        let i = Int(now.timeIntervalSince1970 / 3) % p.count
        let word = p[i].state == .unhealthy ? "unhealthy" : "stopped"
        return p.count == 1 ? "\(p[i].name) \(word)" : "\(p[i].name) \(word) · \(i + 1)/\(p.count)"
    }

    static func stoppedSuffix(_ snap: Snapshot) -> String {
        snap.stopped.isEmpty ? "" : " · \(snap.stopped.count) stopped"
    }
}

struct NameBlock: View {
    let name: String, line: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        VStack(alignment: .leading, spacing: 1) {
            Text(name).pulseFont(15, .semibold).foregroundStyle(p.text)
            Text(line).pulseFont(12).foregroundStyle(p.text2).lineLimit(1)
        }
    }
}

struct LegendRow: View {
    let color: Color, label: String, value: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).pulseFont(12).foregroundStyle(p.text2)
            Spacer()
            Text(value).pulseFont(12, .semibold).foregroundStyle(p.text)
        }
    }
}

// MARK: Halo

struct HaloSmall: View {
    let snap: Snapshot, status: Status, variant: ContainerRing, now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HaloDrawing(snap: snap, variant: variant, size: 100, geometry: .widget(variant), showCount: false)
                .frame(width: 100, height: 100)
            Spacer(minLength: 4)
            NameBlock(name: snap.server.name,
                      line: WidgetText.summary(snap, status, now: now,
                                               healthyText: "\(snap.running) of \(snap.total)" + WidgetText.stoppedSuffix(snap)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct HaloMedium: View {
    let snap: Snapshot, status: Status, variant: ContainerRing, now: Date
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        let s = snap.server
        HStack(spacing: 18) {
            ZStack {
                HaloDrawing(snap: snap, variant: variant, size: 142, geometry: .widget(variant), showCount: false)
                Text("\(snap.running)").pulseFont(26, .bold).tracking(-0.5).foregroundStyle(p.text)
            }
            VStack(alignment: .leading, spacing: 0) {
                NameBlock(name: s.name, line: WidgetText.summary(snap, status, now: now,
                          healthyText: "Up \(Format.uptime(s.uptime))" + (s.cpuTempC.map { " · \(Format.pct($0))°C" } ?? "")))
                Spacer(minLength: 6)
                VStack(spacing: 3) {
                    LegendRow(color: variant == .ticks ? p.text3 : p.green, label: "Containers", value: "\(snap.running)/\(snap.total)")
                    LegendRow(color: p.mint, label: "CPU", value: "\(Format.pct(s.cpu))%")
                    LegendRow(color: p.blue, label: "Memory", value: "\(Format.pct(s.ram))%")
                    LegendRow(color: p.indigo, label: "Disk", value: "\(Format.pct(s.disk))%")
                }
                Spacer(minLength: 6)
                Text(WidgetText.problemsLine(snap, now: now) ?? "All containers running").pulseFont(12).foregroundStyle(p.text2).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: Rings

struct RingsSmall: View {
    let snap: Snapshot, status: Status, now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TripleRings(server: snap.server, size: 84, radii: (37, 27.5, 18), stroke: 7.5)
            Spacer(minLength: 4)
            NameBlock(name: snap.server.name,
                      line: WidgetText.summary(snap, status, now: now, healthyText: "All good" + WidgetText.stoppedSuffix(snap)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RingsMedium: View {
    let snap: Snapshot, status: Status, now: Date
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        let s = snap.server
        HStack(spacing: 20) {
            TripleRings(server: s, size: 132, radii: (58, 44, 30), stroke: 12)
            VStack(alignment: .leading, spacing: 0) {
                NameBlock(name: s.name, line: WidgetText.summary(snap, status, now: now,
                          healthyText: "Up \(Format.uptime(s.uptime))" + (s.cpuTempC.map { " · \(Format.pct($0))°C" } ?? "")))
                Spacer(minLength: 6)
                VStack(spacing: 3) {
                    LegendRow(color: p.mint, label: "CPU", value: "\(Format.pct(s.cpu))%")
                    LegendRow(color: p.blue, label: "Memory", value: "\(Format.pct(s.ram))%")
                    LegendRow(color: p.indigo, label: "Disk", value: "\(Format.pct(s.disk))%")
                }
                Spacer(minLength: 6)
                Text("\(snap.running) of \(snap.total) containers running").pulseFont(12).foregroundStyle(p.text2).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: Memory

struct MemorySmall: View {
    let snap: Snapshot, status: Status, now: Date
    var body: some View {
        let h = Peaks(snap.history, now: now)
        let peakLine = "CPU peak \(Format.pct(h.peak.cpu))%" + (h.peakCPUTime.map { " at \(Format.clock($0))" } ?? "")
        VStack(alignment: .leading, spacing: 0) {
            TripleRings(server: snap.server, size: 84, radii: (37, 27.5, 18), stroke: 7.5,
                        peaks: (h.peak.cpu, h.peak.ram, h.peak.disk), peakStroke: 9)
            Spacer(minLength: 4)
            NameBlock(name: snap.server.name, line: WidgetText.summary(snap, status, now: now, healthyText: peakLine))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MemoryMedium: View {
    let snap: Snapshot, status: Status, now: Date
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        let s = snap.server
        let h = Peaks(snap.history, now: now)
        let day = snap.history.filter { now.timeIntervalSince($0.time) <= 86400 }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.name).pulseFont(15, .semibold).foregroundStyle(p.text)
                Spacer()
                Text(status.level == .offline ? WidgetText.summary(snap, status, now: now, healthyText: "")
                     : "CPU \(Format.pct(s.cpu))% · RAM \(Format.pct(s.ram))% · Disk \(Format.pct(s.disk))%")
                    .pulseFont(12).foregroundStyle(p.text2)
            }
            Sparkline(values: CPUChart.downsample(day.map(\.cpu), to: 120), line: p.mint, area: p.mintT)
                .frame(maxHeight: .infinity)
            HStack {
                Text("24 h")
                Spacer()
                Text("Peak \(Format.pct(h.peak.cpu))%" + (h.peakCPUTime.map { " at \(Format.clock($0))" } ?? ""))
                Spacer()
                Text("now")
            }
            .pulseFont(11).foregroundStyle(p.text3)
        }
    }
}

// MARK: Live

struct LiveSmall: View {
    let snap: Snapshot, status: Status, now: Date
    var body: some View {
        let s = snap.server
        VStack(alignment: .leading, spacing: 0) {
            NameBlock(name: s.name, line: WidgetText.summary(snap, status, now: now,
                      healthyText: snap.problems.isEmpty ? "All running" : "\(snap.problems.count) stopped"))
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                LiveRing(value: s.cpu, metric: .cpu, label: "CPU", size: 42, labelSize: 10, valueSize: 12, showUnit: false)
                LiveRing(value: s.ram, metric: .ram, label: "RAM", size: 42, labelSize: 10, valueSize: 12, showUnit: false)
                LiveRing(value: s.disk, metric: .disk, label: "Disk", size: 42, labelSize: 10, valueSize: 12, showUnit: false)
            }
            .opacity(s.online ? 1 : 0.4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LiveMedium: View {
    let snap: Snapshot, status: Status, now: Date
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        let s = snap.server
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                NameBlock(name: s.name, line: WidgetText.summary(snap, status, now: now, healthyText: "Up \(Format.uptime(s.uptime))"))
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    LiveRing(value: s.cpu, metric: .cpu, label: "", size: 52, valueSize: 13, showUnit: false)
                    LiveRing(value: s.ram, metric: .ram, label: "", size: 52, valueSize: 13, showUnit: false)
                    LiveRing(value: s.disk, metric: .disk, label: "", size: 52, valueSize: 13, showUnit: false)
                }
                .opacity(s.online ? 1 : 0.4)
            }
            VStack(spacing: 3) {
                ForEach(Array(Stacks.group(snap.containers).prefix(5)), id: \.name) { st in
                    HStack {
                        Text(st.name).pulseFont(12, st.hasProblem ? .semibold : .regular).foregroundStyle(p.text)
                        Spacer()
                        Text("\(st.running)/\(st.containers.count)").pulseFont(12).foregroundStyle(p.text3)
                    }
                }
            }
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
