import Foundation

/// Geometry of the container ring: the circumference is split into N equal slots,
/// each drawn as a dash followed by a fixed gap. Slot 0 starts at 12 o'clock, clockwise.
public struct HaloLayout: Sendable, Equatable {
    public static let proportionalAbove = 80

    public let count: Int
    public let radius: Double
    public let gap: Double

    public init(count: Int, radius: Double, gap: Double = 3) {
        self.count = count; self.radius = radius; self.gap = gap
    }

    public var circumference: Double { 2 * .pi * radius }
    public var isProportional: Bool { count > Self.proportionalAbove }
    public var slotLength: Double { count > 0 ? circumference / Double(count) : 0 }
    public var dashLength: Double { max(0, slotLength - gap) }

    /// Start and end of slot `i` as fractions of the circle (0 = 12 o'clock), for `trim(from:to:)`.
    public func slot(_ i: Int) -> (start: Double, end: Double) {
        let start = Double(i) * slotLength / circumference
        return (start, start + dashLength / circumference)
    }

    /// Centre of slot `i` as a fraction of the circle.
    public func center(_ i: Int) -> Double {
        let s = slot(i)
        return (s.start + s.end) / 2
    }

    /// Angle in radians from 12 o'clock, clockwise.
    public func angle(_ i: Int) -> Double { center(i) * 2 * .pi }
}
