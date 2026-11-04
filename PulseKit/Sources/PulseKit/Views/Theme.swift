import SwiftUI

/// Design tokens from the spec, resolved for one colour scheme.
public struct Palette: Sendable {
    public let text, text2, text3, separator, fill, track: Color
    public let green, greenText, orange, red, blue, mint, indigo: Color
    public let mintT, blueT, indigoT, greenT, orangeT, redT: Color
    public let glass, glassBorder: Color

    public init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        func rgb(_ hex: UInt32, _ a: Double = 1) -> Color {
            Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: a)
        }
        text = dark ? rgb(0xF5F5F7) : rgb(0x1D1D1F)
        text2 = dark ? rgb(0xEBEBF5, 0.72) : rgb(0x3C3C43, 0.78)
        text3 = dark ? rgb(0xEBEBF5, 0.48) : rgb(0x3C3C43, 0.55)
        separator = dark ? rgb(0xFFFFFF, 0.10) : rgb(0x3C3C43, 0.16)
        fill = dark ? rgb(0xFFFFFF, 0.07) : rgb(0x787880, 0.10)
        track = dark ? rgb(0xFFFFFF, 0.12) : rgb(0x787880, 0.18)
        let g: UInt32 = dark ? 0x30D158 : 0x34C759
        let o: UInt32 = dark ? 0xFF9F0A : 0xFF9500
        let r: UInt32 = dark ? 0xFF453A : 0xFF3B30
        let b: UInt32 = dark ? 0x0A84FF : 0x007AFF
        let m: UInt32 = dark ? 0x63E6E2 : 0x00B8B0
        let i: UInt32 = dark ? 0x7D7AFF : 0x5856D6
        green = rgb(g); greenText = dark ? rgb(0x30D158) : rgb(0x248A3D)
        orange = rgb(o); red = rgb(r); blue = rgb(b); mint = rgb(m); indigo = rgb(i)
        mintT = rgb(m, 0.16); blueT = rgb(b, dark ? 0.20 : 0.14); indigoT = rgb(i, dark ? 0.20 : 0.14)
        greenT = rgb(g, 0.35); orangeT = rgb(o, 0.40); redT = rgb(r, 0.40)
        glass = dark ? rgb(0x26262C, 0.55) : rgb(0xFFFFFF, 0.60)
        glassBorder = dark ? rgb(0xFFFFFF, 0.14) : rgb(0xFFFFFF, 0.85)
    }

    public func ring(_ metric: Metric) -> (Color, Color) {
        switch metric {
        case .cpu: (mint, mintT)
        case .ram: (blue, blueT)
        case .disk: (indigo, indigoT)
        }
    }

    /// Ring colour after thresholds: orange over warning, red over critical.
    public func ringColor(_ metric: Metric, value: Double, cpuSustained: Bool = false) -> Color {
        switch StatusEngine.severity(metric, value: value, cpuSustained: cpuSustained) {
        case .normal: ring(metric).0
        case .warning: orange
        case .critical: red
        }
    }
}

public extension View {
    /// SF Pro at an exact point size with tabular digits.
    func pulseFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight)).monospacedDigit()
    }
}

/// `12` + `%`: the unit smaller and in text2, baseline-aligned.
public struct ValueUnit: View {
    let value: String, unit: String, size: CGFloat, unitSize: CGFloat
    var weight: Font.Weight = .semibold
    var tracking: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    public init(_ value: String, _ unit: String, size: CGFloat, unitSize: CGFloat, weight: Font.Weight = .semibold, tracking: CGFloat = 0) {
        self.value = value; self.unit = unit; self.size = size; self.unitSize = unitSize
        self.weight = weight; self.tracking = tracking
    }

    public var body: some View {
        let p = Palette(scheme)
        HStack(alignment: .firstTextBaseline, spacing: 1.5) {
            Text(value).pulseFont(size, weight).tracking(tracking).foregroundStyle(p.text)
            if !unit.isEmpty { Text(unit).pulseFont(unitSize, .regular).foregroundStyle(p.text2) }
        }
    }
}
