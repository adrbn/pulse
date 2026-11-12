import SwiftUI

/// The 360 pt popover. Same header and footer for every style; the hero and the block under it change.
public struct PopoverView: View {
    let snap: Snapshot
    let status: Status
    let style: PulseStyle
    let variant: ContainerRing
    let now: Date
    let actions: PopoverActions
    @State private var showAll = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(snap: Snapshot, status: Status, style: PulseStyle, variant: ContainerRing, now: Date = .now,
                actions: PopoverActions = PopoverActions()) {
        self.snap = snap; self.status = status; self.style = style; self.variant = variant
        self.now = now; self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showAll {
                AllContainers(snap: snap, now: now, actions: actions) { showAll = false }
            } else {
                Group {
                    switch style {
                    case .halo: HaloStyle(snap: snap, status: status, variant: variant, now: now, actions: actions, showAll: $showAll)
                    case .rings: RingsStyle(snap: snap, status: status, now: now, showAll: $showAll)
                    case .memory: MemoryStyle(snap: snap, status: status, now: now, actions: actions)
                    case .live: LiveStyle(snap: snap, status: status, now: now)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .id(style)
            }
            Footer(updated: snap.updatedAt, now: now, link: style == .memory && !showAll ? "All containers ›" : nil,
                   linkAction: { showAll = true }, actions: actions)
        }
        .padding(16)
        .frame(width: 360, alignment: .topLeading)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: style)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: variant)
    }
}

// MARK: - 2a Halo

struct HaloStyle: View {
    let snap: Snapshot, status: Status, variant: ContainerRing, now: Date, actions: PopoverActions
    @Binding var showAll: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme)
        let s = snap.server
        Header(snap: snap, status: status, now: now) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(s.cpuModel); Text("\(s.cores) cores")
            }
            .pulseFont(11).foregroundStyle(p.text3)
        }
        HStack(alignment: .center, spacing: 16) {
            HaloDrawing(snap: snap, variant: variant, size: 180, level: status.level)
            VStack(alignment: .leading, spacing: 9) {
                let containers = LegendItem(color: variant == .ticks ? p.text3 : p.green, label: "Containers",
                                            value: "\(snap.running)", unit: "/ \(snap.total)", size: 19)
                if variant != .inner { containers }
                LegendItem(color: p.mint, label: "CPU", value: Format.pct(s.cpu), unit: "%", size: 19)
                LegendItem(color: p.blue, label: "Memory", value: Format.pct(s.ram), unit: "%", size: 19)
                LegendItem(color: p.indigo, label: "Disk", value: Format.pct(s.disk), unit: "%", size: 19)
                if variant == .inner { containers }
            }
            Spacer(minLength: 0)
        }
        VitalsTiles(snap: snap)
        if !snap.problems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Needs attention", size: 12)
                ForEach(snap.problems) { c in
                    HStack(spacing: 10) {
                        Circle().stroke(c.state == .stopped ? p.text3 : p.orange, lineWidth: 1.5).frame(width: 7.5, height: 7.5)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).pulseFont(13, .semibold).foregroundStyle(p.text)
                            Text(Format.containerDetail(c, now: now)).pulseFont(12).foregroundStyle(p.text2)
                        }
                        Spacer()
                        if c.state == .stopped, snap.canStart { StartPill { actions.start(c.name) } }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .contain)
                }
            }
        }
        HStack {
            Text("\(snap.healthyCount) healthy · \(snap.noCheckCount) no health check").foregroundStyle(p.text2)
            Spacer()
            Button("All \(snap.total) ›") { showAll = true }.buttonStyle(.plain).foregroundStyle(p.blue)
        }
        .pulseFont(12).padding(.horizontal, 4)
    }
}

// MARK: - 1a Rings

struct RingsStyle: View {
    let snap: Snapshot, status: Status, now: Date
    @Binding var showAll: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme)
        let s = snap.server
        Header(snap: snap, status: status, now: now) { EmptyView() }
        HStack(spacing: 22) {
            TripleRings(server: s, size: 132, radii: (58, 44, 30), stroke: 12)
            VStack(alignment: .leading, spacing: 10) {
                LegendItem(color: p.mint, label: "CPU", value: Format.pct(s.cpu), unit: "%", size: 22)
                LegendItem(color: p.blue, label: "Memory", value: Format.pct(s.ram), unit: "%", size: 22)
                LegendItem(color: p.indigo, label: "Disk", value: Format.pct(s.disk), unit: "%", size: 22)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        VitalsTiles(snap: snap)
        Rectangle().fill(p.separator).frame(height: 0.5)
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: "Containers", trailing: "\(snap.running) of \(snap.total) running")
            ForEach(rows) { c in
                HStack(spacing: 10) {
                    StateDot(state: c.state)
                    Text(c.name).pulseFont(13).foregroundStyle(p.text)
                    Spacer()
                    Text(detail(c)).pulseFont(12).foregroundStyle(p.text3)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
            }
            Button("Show all \(snap.total)") { showAll = true }.buttonStyle(.plain)
                .pulseFont(12).foregroundStyle(p.blue).padding(.horizontal, 4)
        }
    }

    /// Problems first, then the busiest containers, 6 rows.
    var rows: [Container] {
        let busy = snap.containers.filter(\.isRunning).sorted { $0.cpu > $1.cpu }
        return Array((snap.problems + busy).prefix(6))
    }

    func detail(_ c: Container) -> String {
        if c.state == .stopped { return "Stopped" + (c.stoppedAt.map { " · " + Format.ago($0, now: now) } ?? "") }
        return Format.containerDetail(c, now: now)
    }
}

// MARK: - 2b Rings with memory

struct MemoryStyle: View {
    let snap: Snapshot, status: Status, now: Date, actions: PopoverActions
    @State private var mode = 0     // 0 = Now, 1 = 24 h (rings show the 24 h average)
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme)
        let h = Peaks(snap.history, now: now)
        let s = snap.server
        var shown = s
        if mode == 1 { shown.cpu = h.avg.cpu; shown.ram = h.avg.ram; shown.disk = h.avg.disk }
        let note = mode == 1 ? "avg" : nil

        return Group {
            Header(snap: snap, status: status, now: now) {
                // Drawn in SwiftUI (not a segmented Picker) so ImageRenderer snapshots show it too.
                HStack(spacing: 2) {
                    ForEach([(0, "Now"), (1, "24 h")], id: \.0) { tag, label in
                        Text(label).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(mode == tag ? Color.primary.opacity(0.14) : .clear, in: Capsule())
                            .contentShape(Capsule())
                            .onTapGesture { mode = tag }
                    }
                }
                .padding(2).background(Color.primary.opacity(0.06), in: Capsule())
            }
            HStack(spacing: 22) {
                TripleRings(server: shown, size: 132, radii: (58, 44, 30), stroke: 12,
                            peaks: (h.peak.cpu, h.peak.ram, h.peak.disk))
                VStack(alignment: .leading, spacing: 10) {
                    LegendItem(color: p.mint, label: "CPU", value: Format.pct(shown.cpu), unit: "%", size: 22,
                               note: note ?? "peak \(Format.pct(h.peak.cpu))%")
                    LegendItem(color: p.blue, label: "Memory", value: Format.pct(shown.ram), unit: "%", size: 22,
                               note: note ?? "peak \(Format.pct(h.peak.ram))%")
                    LegendItem(color: p.indigo, label: "Disk", value: Format.pct(shown.disk), unit: "%", size: 22,
                               note: h.diskPerDay.map { String(format: "%+.1f%% / day", $0) })
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
            CPUChart(snap: snap, now: now)
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Today", trailing: "\(snap.running) of \(snap.total) running")
                let today = snap.events.filter { now.timeIntervalSince($0.time) < 86400 }.prefix(4)
                if today.isEmpty {
                    Text("Nothing happened in the last 24 h").pulseFont(13).foregroundStyle(p.text3).padding(.horizontal, 4)
                }
                ForEach(Array(today)) { e in
                    HStack(spacing: 0) {
                        Text(Format.clock(e.time)).pulseFont(13).foregroundStyle(p.text3).frame(width: 40, alignment: .leading)
                        Text(e.text).pulseFont(13).foregroundStyle(p.text).lineLimit(1)
                        Spacer(minLength: 6)
                        if e.kind == .exited, let name = e.container, snap.canStart,
                           snap.containers.first(where: { $0.name == name })?.state == .stopped {
                            Button("Start") { actions.start(name) }.buttonStyle(.plain).pulseFont(13).foregroundStyle(p.blue)
                        }
                    }
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// 24 h peaks, averages and disk growth, from local history.
public struct Peaks {
    public var peak: (cpu: Double, ram: Double, disk: Double, temp: Double?)
    public var peakCPUTime: Date?
    public var avg: (cpu: Double, ram: Double, disk: Double)
    public var diskPerDay: Double?

    public init(_ samples: [Sample], now: Date) {
        let day = samples.filter { now.timeIntervalSince($0.time) <= 86400 }
        let top = day.max { $0.cpu < $1.cpu }
        peak = (top?.cpu ?? 0, day.map(\.ram).max() ?? 0, day.map(\.disk).max() ?? 0, day.compactMap(\.temp).max())
        peakCPUTime = top?.time
        let n = Double(max(1, day.count))
        avg = (day.map(\.cpu).reduce(0, +) / n, day.map(\.ram).reduce(0, +) / n, day.map(\.disk).reduce(0, +) / n)
        if let first = day.first, let last = day.last, last.time.timeIntervalSince(first.time) > 3 * 3600 {
            diskPerDay = (last.disk - first.disk) / (last.time.timeIntervalSince(first.time) / 86400)
        }
    }
}

struct CPUChart: View {
    let snap: Snapshot, now: Date
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        let h = Peaks(snap.history, now: now)
        let day = snap.history.filter { now.timeIntervalSince($0.time) <= 86400 }
        let spike = snap.events.first { $0.kind == .cpuSpike && now.timeIntervalSince($0.time) <= 86400 }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CPU · last 24 h")
                Spacer()
                if let t = snap.server.cpuTempC {
                    Text("\(Format.pct(t))°C now" + (h.peak.temp.map { " · \(Format.pct($0))°C peak" } ?? ""))
                }
            }
            .pulseFont(11).foregroundStyle(p.text2)
            Sparkline(values: Self.downsample(day.map(\.cpu), to: 144), line: p.mint, area: p.mintT)
                .frame(height: 48)
            HStack {
                Text(day.first.map { Format.clock($0.time) } ?? "")
                Spacer()
                if let spike { Text("\(Format.clock(spike.time)) \(spike.container ?? "peak")") }
                else if let t = h.peakCPUTime { Text("peak \(Format.clock(t))") }
                Spacer()
                Text("now")
            }
            .pulseFont(10).foregroundStyle(p.text3)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU over the last 24 hours, peak \(Format.pct(h.peak.cpu)) percent")
    }

    /// Bucket maxima keep short spikes visible.
    static func downsample(_ v: [Double], to n: Int) -> [Double] {
        guard v.count > n else { return v }
        let size = Double(v.count) / Double(n)
        return (0..<n).map { i in v[Int(Double(i) * size)..<min(v.count, Int(Double(i + 1) * size))].max() ?? 0 }
    }
}

// MARK: - 2c Live rings

struct LiveStyle: View {
    let snap: Snapshot, status: Status, now: Date
    @State private var expanded: Set<String> = []
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Palette(scheme)
        let s = snap.server
        let problems = snap.problems
        Header(snap: snap, status: status, now: now) {
            if !problems.isEmpty {
                let word = problems.contains { $0.state == .unhealthy } ? "unhealthy" : "stopped"
                Text("\(problems.count) \(word)").pulseFont(12, .semibold).foregroundStyle(p.text2)
                    .padding(.vertical, 3).padding(.horizontal, 10)
                    .background(p.fill, in: Capsule())
            }
        }
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                LiveRing(value: s.cpu, metric: .cpu, label: "CPU" + (s.cpuTempC.map { " · \(Format.pct($0))°C" } ?? ""), size: 88)
                    .frame(maxWidth: .infinity)
                LiveRing(value: s.ram, metric: .ram, label: "Memory", size: 88).frame(maxWidth: .infinity)
                LiveRing(value: s.disk, metric: .disk, label: "Disk", size: 88).frame(maxWidth: .infinity)
            }
            Text("Load \(Format.load(s.load1)) · ↓ \(Format.rateString(s.netInBps)) · ↑ \(Format.rateString(s.netOutBps))")
                .pulseFont(12).foregroundStyle(p.text2)
        }
        Rectangle().fill(p.separator).frame(height: 0.5)
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Stacks", trailing: "\(snap.running) of \(snap.total) running").padding(.bottom, 4)
            ForEach(Stacks.group(snap.containers), id: \.name) { stack in
                StackRow(stack: stack, expanded: expanded.contains(stack.name), now: now) {
                    if expanded.contains(stack.name) { expanded.remove(stack.name) } else { expanded.insert(stack.name) }
                }
            }
        }
    }
}

struct LiveRing: View {
    let value: Double, metric: Metric, label: String, size: CGFloat
    var labelSize: CGFloat = 12
    var valueSize: CGFloat = 19
    var showUnit = true
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        let k = size / 64
        VStack(spacing: 6 * min(1, k)) {
            ZStack {
                Ring(value: value, radius: 27 * k, stroke: 7 * k, color: p.ringColor(metric, value: value), track: p.ring(metric).1)
                ValueUnit(Format.pct(value), showUnit ? "%" : "", size: valueSize, unitSize: 11)
            }
            .frame(width: size, height: size)
            if !label.isEmpty { Text(label).pulseFont(labelSize).foregroundStyle(labelSize <= 10 ? p.text3 : p.text2) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label).accessibilityValue("\(Format.pct(value)) percent")
    }
}

struct StackRow: View {
    let stack: Stacks.Stack, expanded: Bool, now: Date, toggle: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        VStack(alignment: .leading, spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Text(stack.name).pulseFont(13, stack.hasProblem ? .semibold : .regular).foregroundStyle(p.text)
                    Spacer()
                    HStack(spacing: 3) {
                        // Problems first so a capped row still shows them.
                        ForEach(Array(stack.containers.sorted { $0.needsAttention && !$1.needsAttention }.prefix(10))) {
                            StateDot(state: $0.state, size: 7)
                        }
                    }
                    Text("\(stack.running)/\(stack.containers.count)").pulseFont(12).foregroundStyle(p.text3)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.vertical, 6).padding(.horizontal, 8)
                .background(stack.hasProblem ? p.fill : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(stack.name), \(stack.running) of \(stack.containers.count) running")
            if expanded && stack.containers.count > 8 {
                ScrollView { members(p) }.frame(height: 8 * 20).scrollIndicators(.never)
            } else if expanded {
                members(p)
            }
        }
    }

    private func members(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
                ForEach(stack.containers) { c in
                    HStack(spacing: 8) {
                        StateDot(state: c.state, size: 7)
                        Text(c.name).pulseFont(12).foregroundStyle(p.text2)
                        Spacer()
                        Text(Format.containerDetail(c, now: now)).pulseFont(11).foregroundStyle(p.text3)
                    }
                    .padding(.leading, 18).padding(.trailing, 8)
                }
        }
    }
}
