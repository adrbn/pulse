import SwiftUI

/// Temp, Load, In, Out tiles (styles Rings and Halo).
public struct VitalsTiles: View {
    let snap: Snapshot
    @Environment(\.colorScheme) private var scheme
    public init(snap: Snapshot) { self.snap = snap }

    public var body: some View {
        let p = Palette(scheme)
        let s = snap.server
        let inR = Format.rate(s.netInBps), outR = Format.rate(s.netOutBps)
        HStack(spacing: 6) {
            tile("Temp", s.cpuTempC.map { Format.pct($0) } ?? "–", "°C") { TempBar(temp: s.cpuTempC) }
                .accessibilityValue(s.cpuTempC.map { "\(Format.pct($0)) degrees" } ?? "unknown")
            tile("Load", Format.load(s.load1), "/\(s.cores)") { LoadBar(load: s.load1, cores: s.cores) }
                .accessibilityValue("\(Format.load(s.load1)) on \(s.cores) cores")
            tile("↓ In", inR.value, inR.unit) { Sparkline(values: snap.netIn, line: p.blue, area: p.blueT) }
                .accessibilityValue(Format.rateString(s.netInBps))
            tile("↑ Out", outR.value, outR.unit) { Sparkline(values: snap.netOut, line: p.indigo, area: p.indigoT) }
                .accessibilityValue(Format.rateString(s.netOutBps))
        }
    }

    private func tile<V: View>(_ label: String, _ value: String, _ unit: String, @ViewBuilder visual: () -> V) -> some View {
        let p = Palette(scheme)
        return VStack(alignment: .leading, spacing: 0) {
            Text(label).pulseFont(11).foregroundStyle(p.text3)
            ValueUnit(value, unit, size: 16, unitSize: 10).padding(.top, 2)
            visual().frame(height: 14, alignment: .center).padding(.top, 4)
        }
        .padding(.top, 9).padding(.horizontal, 10).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.replacingOccurrences(of: "↓ ", with: "Network ").replacingOccurrences(of: "↑ ", with: "Network "))
    }
}

/// 0–70 green, 70–85 orange, 85–100 red zones with a knob at the reading.
struct TempBar: View {
    let temp: Double?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        GeometryReader { geo in
            let w = geo.size.width - 4          // two 2 pt gaps
            let t = min(max(temp ?? 0, 0), 100)
            let zone = t >= 85 ? p.red : t >= 70 ? p.orange : p.green
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    Capsule().fill(p.greenT).frame(width: w * 0.70)
                    Capsule().fill(p.orangeT).frame(width: w * 0.15)
                    Capsule().fill(p.redT).frame(width: w * 0.15)
                }
                .frame(height: 5)
                if temp != nil {
                    Circle().fill(.white).overlay(Circle().stroke(zone, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .offset(x: min(max(0, geo.size.width * t / 100 - 5), geo.size.width - 10))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// One segment per core, filled left to right by load / cores.
struct LoadBar: View {
    let load: Double, cores: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(scheme)
        let n = max(1, cores)
        let filled = min(max(load / Double(n), 0), 1) * Double(n)
        GeometryReader { geo in
            let segW = (geo.size.width - CGFloat(n - 1) * 2) / CGFloat(n)
            HStack(spacing: 2) {
                ForEach(0..<n, id: \.self) { i in
                    let part = min(max(filled - Double(i), 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.track)
                        Capsule().fill(p.text).frame(width: segW * part)
                    }
                    .frame(width: segW, height: 5)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// Line with an area fill under it, scaled to its own min/max.
public struct Sparkline: View {
    let values: [Double]
    let line: Color, area: Color
    var lineWidth: CGFloat = 1.5
    public init(values: [Double], line: Color, area: Color, lineWidth: CGFloat = 1.5) {
        self.values = values; self.line = line; self.area = area; self.lineWidth = lineWidth
    }

    public var body: some View {
        GeometryReader { geo in
            let pts = Self.points(values, in: geo.size, inset: lineWidth / 2)
            if pts.count > 1 {
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height)); pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height)); p.closeSubpath()
                    }.fill(area)
                    Path { p in p.addLines(pts) }
                        .stroke(line, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    static func points(_ v: [Double], in size: CGSize, inset: CGFloat) -> [CGPoint] {
        guard v.count > 1, let lo = v.min(), let hi = v.max() else { return [] }
        let span = max(hi - lo, max(hi, 1) * 0.15)
        let base = lo - (span - (hi - lo)) / 2
        return v.enumerated().map { i, x in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(v.count - 1),
                    y: inset + (size.height - 2 * inset) * CGFloat(1 - (x - base) / span))
        }
    }
}
