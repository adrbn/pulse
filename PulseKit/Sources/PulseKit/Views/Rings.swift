import SwiftUI

/// One progress ring: starts at 12 o'clock, clockwise, round caps, track underneath.
/// Animates from its previous value (0.6 s ease-out), never from zero after it appears.
public struct Ring: View {
    let value: Double          // 0...100
    let radius: CGFloat
    let stroke: CGFloat
    let color: Color
    let track: Color
    var peak: Double? = nil
    var peakColor: Color = .primary
    var peakStroke: CGFloat = 14
    var peakLength: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Double, radius: CGFloat, stroke: CGFloat, color: Color, track: Color,
                peak: Double? = nil, peakColor: Color = .primary, peakStroke: CGFloat = 14, peakLength: CGFloat = 2.5) {
        self.value = value; self.radius = radius; self.stroke = stroke; self.color = color; self.track = track
        self.peak = peak; self.peakColor = peakColor; self.peakStroke = peakStroke; self.peakLength = peakLength
    }

    public var body: some View {
        let frac = min(max(value / 100, 0), 1)
        ZStack {
            Circle().stroke(track, lineWidth: stroke)
            Circle().trim(from: 0, to: frac)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: frac)
            if let peak {
                let c = 2 * .pi * radius
                let p = min(max(peak / 100, 0), 1)
                let half = peakLength / c / 2
                Circle().trim(from: max(0, p - half), to: min(1, p + half))
                    .stroke(peakColor, style: StrokeStyle(lineWidth: peakStroke, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

/// CPU, memory and disk rings, concentric, in a square of `size`.
public struct TripleRings: View {
    let server: Server
    let size: CGFloat
    let radii: (CGFloat, CGFloat, CGFloat)
    let stroke: CGFloat
    var peaks: (Double, Double, Double)? = nil
    var peakStroke: CGFloat = 14
    var cpuSustained = false
    @Environment(\.colorScheme) private var scheme

    public init(server: Server, size: CGFloat, radii: (CGFloat, CGFloat, CGFloat), stroke: CGFloat,
                peaks: (Double, Double, Double)? = nil, peakStroke: CGFloat = 14, cpuSustained: Bool = false) {
        self.server = server; self.size = size; self.radii = radii; self.stroke = stroke
        self.peaks = peaks; self.peakStroke = peakStroke; self.cpuSustained = cpuSustained
    }

    public var body: some View {
        let p = Palette(scheme)
        ZStack {
            Ring(value: server.cpu, radius: radii.0, stroke: stroke,
                 color: p.ringColor(.cpu, value: server.cpu, cpuSustained: cpuSustained), track: p.mintT,
                 peak: peaks?.0, peakColor: p.text, peakStroke: peakStroke)
                .accessibilityElement().accessibilityLabel("CPU").accessibilityValue("\(Format.pct(server.cpu)) percent")
            Ring(value: server.ram, radius: radii.1, stroke: stroke,
                 color: p.ringColor(.ram, value: server.ram), track: p.blueT,
                 peak: peaks?.1, peakColor: p.text, peakStroke: peakStroke)
                .accessibilityElement().accessibilityLabel("Memory").accessibilityValue("\(Format.pct(server.ram)) percent")
            Ring(value: server.disk, radius: radii.2, stroke: stroke,
                 color: p.ringColor(.disk, value: server.disk), track: p.indigoT)
                .accessibilityElement().accessibilityLabel("Disk").accessibilityValue("\(Format.pct(server.disk)) percent")
        }
        .frame(width: size, height: size)
        .opacity(server.online ? 1 : 0.4)
    }
}

/// Radial tick at an angle (radians from 12 o'clock, clockwise), centred on `radius`.
struct Tick: Shape {
    let angle: Double, radius: CGFloat, length: CGFloat
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let dx = CGFloat(sin(angle)), dy = CGFloat(-cos(angle))
        var p = Path()
        p.move(to: CGPoint(x: c.x + dx * (radius - length / 2), y: c.y + dy * (radius - length / 2)))
        p.addLine(to: CGPoint(x: c.x + dx * (radius + length / 2), y: c.y + dy * (radius + length / 2)))
        return p
    }
}

/// The outer container ring of the Halo style, in one of its variants. All lengths in points.
public struct ContainerRingView: View {
    let containers: [Container]
    let variant: ContainerRing
    let radius: CGFloat
    let stroke: CGFloat
    let scale: CGFloat           // design units -> points, for gaps and tick widths
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(containers: [Container], variant: ContainerRing, radius: CGFloat, stroke: CGFloat, scale: CGFloat) {
        self.containers = containers; self.variant = variant; self.radius = radius; self.stroke = stroke; self.scale = scale
    }

    public var body: some View {
        let p = Palette(scheme)
        let layout = HaloLayout(count: containers.count, radius: Double(radius), gap: 3 * Double(scale))
        ZStack {
            if layout.isProportional || containers.isEmpty {
                proportional(p)
            } else {
                switch variant {
                case .segments, .inner: segments(p, layout)
                case .ticks: ticks(p, layout)
                case .beads: beads(p, layout)
                }
            }
        }
        .frame(width: radius * 2 + stroke * 2, height: radius * 2 + stroke * 2)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: containers.map(\.state))
    }

    private func proportional(_ p: Palette) -> some View {
        let share = containers.isEmpty ? 0 : Double(containers.filter(\.isRunning).count) / Double(containers.count)
        return ZStack {
            Circle().stroke(p.track, lineWidth: stroke)
            Circle().trim(from: 0, to: share).stroke(p.green, style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    private func segments(_ p: Palette, _ l: HaloLayout) -> some View {
        ForEach(Array(containers.enumerated()), id: \.element.name) { i, c in
            let s = l.slot(i)
            Circle().trim(from: s.start, to: s.end)
                .stroke(c.state == .running ? p.green : c.state == .stopped ? p.track : p.orange,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .frame(width: radius * 2, height: radius * 2)
        }
    }

    private func ticks(_ p: Palette, _ l: HaloLayout) -> some View {
        ForEach(Array(containers.enumerated()), id: \.element.name) { i, c in
            let bad = !c.isRunning
            Tick(angle: l.angle(i), radius: radius, length: bad ? 8 * scale : stroke)
                .stroke(bad ? p.orange : p.text3, style: StrokeStyle(lineWidth: (bad ? 2.4 : 1.6) * scale, lineCap: .butt))
        }
    }

    private func beads(_ p: Palette, _ l: HaloLayout) -> some View {
        ForEach(Array(containers.enumerated()), id: \.element.name) { i, c in
            let a = l.angle(i)
            let off = CGSize(width: CGFloat(sin(a)) * radius, height: CGFloat(-cos(a)) * radius)
            Group {
                switch c.state {
                case .running: Circle().fill(p.green).frame(width: 3.5 * scale, height: 3.5 * scale)
                case .stopped: Circle().stroke(p.text3, lineWidth: 1.2 * scale).frame(width: 4.4 * scale, height: 4.4 * scale)
                case .unhealthy, .restarting: Circle().fill(p.orange).frame(width: 3.5 * scale, height: 3.5 * scale)
                }
            }
            .offset(off)
        }
    }
}

/// Geometry of the Halo hero, in design units of a 180-unit square.
public struct HaloGeometry: Sendable {
    public var haloRadius: CGFloat, haloStroke: CGFloat
    public var rings: (CGFloat, CGFloat, CGFloat), ringStroke: CGFloat
    public var innerArc: CGFloat?           // Inner variant only

    public init(haloRadius: CGFloat, haloStroke: CGFloat, rings: (CGFloat, CGFloat, CGFloat), ringStroke: CGFloat, innerArc: CGFloat? = nil) {
        self.haloRadius = haloRadius; self.haloStroke = haloStroke; self.rings = rings; self.ringStroke = ringStroke; self.innerArc = innerArc
    }

    public static func popover(_ v: ContainerRing) -> HaloGeometry {
        switch v {
        case .segments: HaloGeometry(haloRadius: 84, haloStroke: 9, rings: (66, 53, 40), ringStroke: 10)
        case .ticks: HaloGeometry(haloRadius: 86, haloStroke: 6, rings: (66, 53, 40), ringStroke: 10)
        case .beads: HaloGeometry(haloRadius: 85, haloStroke: 3.5, rings: (66, 53, 40), ringStroke: 10)
        case .inner: HaloGeometry(haloRadius: 0, haloStroke: 0, rings: (82, 67, 52), ringStroke: 12, innerArc: 36)
        }
    }

    /// Widgets use thicker strokes so the shape holds at small sizes.
    public static func widget(_ v: ContainerRing) -> HaloGeometry {
        var g = popover(v)
        if v == .inner { g.ringStroke = 14; return g }
        g.rings = (64, 49, 34); g.ringStroke = 12
        if v == .segments { g.haloStroke = 10 }
        return g
    }
}

/// Halo hero drawing: container ring + three capacity rings + the running count.
public struct HaloDrawing: View {
    let snap: Snapshot
    let variant: ContainerRing
    let size: CGFloat
    var geometry: HaloGeometry? = nil
    var showCount = true
    var cpuSustained = false
    var level: StatusLevel? = nil
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Pref.haloStatusCenter, store: AppGroup.defaults) private var statusCenter = false

    public init(snap: Snapshot, variant: ContainerRing, size: CGFloat, geometry: HaloGeometry? = nil,
                showCount: Bool = true, cpuSustained: Bool = false, level: StatusLevel? = nil) {
        self.snap = snap; self.variant = variant; self.size = size; self.geometry = geometry
        self.showCount = showCount; self.cpuSustained = cpuSustained; self.level = level
    }

    public var body: some View {
        let p = Palette(scheme)
        let k = size / 180
        let g = geometry ?? .popover(variant)
        ZStack {
            if variant != .inner {
                ContainerRingView(containers: snap.containers, variant: variant,
                                  radius: g.haloRadius * k, stroke: g.haloStroke * k, scale: k)
                    .opacity(snap.server.online ? 1 : 0.4)
            }
            TripleRings(server: snap.server, size: size, radii: (g.rings.0 * k, g.rings.1 * k, g.rings.2 * k),
                        stroke: g.ringStroke * k, cpuSustained: cpuSustained)
            if let arc = g.innerArc {
                let share = snap.total == 0 ? 0 : Double(snap.running) / Double(snap.total) * 100
                Ring(value: share, radius: arc * k, stroke: 3 * k, color: p.green, track: p.track)
            }
            if showCount, statusCenter, let level {
                StatusGlyph(level: level, size: 40 * k)
            } else if showCount {
                VStack(spacing: 0) {
                    Text("\(snap.running)").pulseFont(24 * k, .bold).tracking(-0.48 * k).foregroundStyle(p.text)
                    Text("of \(snap.total)").pulseFont(11 * k).foregroundStyle(p.text2)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(snap.running) of \(snap.total) containers running")
    }
}

/// Optional Halo centre (Settings → Appearance): the server's state as a shape and a colour, readable without colour too.
struct StatusGlyph: View {
    let level: StatusLevel
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        let (name, color, label) = switch level {
        case .healthy: ("checkmark.circle.fill", p.green, "All good")
        case .warning: ("exclamationmark.triangle.fill", p.orange, "Warning")
        case .offline: ("xmark.octagon.fill", p.red, "Offline")
        }
        Image(systemName: name)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
            .font(.system(size: size, weight: .semibold))
            .accessibilityLabel(label)
    }
}
