import AppKit
import PulseKit

/// 16×16 pt template glyphs. State is carried by shape, never colour.
enum MenuBarIcon {
    enum Kind { case halo, rings, live(cpu: Double, ram: Double, disk: Double) }

    static func kind(style: PulseStyle, mode: IconMode, server: Server?) -> Kind {
        if mode == .live, let s = server { return .live(cpu: s.cpu, ram: s.ram, disk: s.disk) }
        if mode == .live { return .live(cpu: 0, ram: 0, disk: 0) }
        return style == .halo ? .halo : .rings
    }

    static func image(_ kind: Kind, level: StatusLevel, size: CGFloat = 16, template: Bool = true) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: rect.width / 16, y: rect.height / 16)
            draw(kind, level: level, in: ctx, color: .black)
            return true
        }
        img.isTemplate = template
        return img
    }

    static func draw(_ kind: Kind, level: StatusLevel, in ctx: CGContext, color: NSColor) {
        let c = CGPoint(x: 8, y: 8)
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(1.5)
        let offline = level == .offline
        let warning = level == .warning

        /// Clockwise angle from 12 o'clock (degrees) -> CG angle in the flipped space.
        func a(_ deg: Double) -> CGFloat { CGFloat((deg - 90) * .pi / 180) }

        switch kind {
        case .halo, .rings:
            let outerR: CGFloat = { if case .halo = kind { return 6.6 } else { return 6.25 } }()
            ctx.saveGState()
            if offline { ctx.setAlpha(0.4) }
            if case .halo = kind { ctx.setLineDash(phase: 0, lengths: [1.9, 1.2]) }
            if warning {
                ctx.addArc(center: c, radius: outerR, startAngle: a(80), endAngle: a(370), clockwise: false)
            } else {
                ctx.addEllipse(in: CGRect(x: c.x - outerR, y: c.y - outerR, width: outerR * 2, height: outerR * 2))
            }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.strokeEllipse(in: CGRect(x: 5, y: 5, width: 6, height: 6))
            ctx.restoreGState()
            if warning { ctx.fillEllipse(in: CGRect(x: 12.8 - 1.9, y: 3.2 - 1.9, width: 3.8, height: 3.8)) }

        case .live(let cpu, let ram, let disk):
            ctx.setLineCap(.round)
            for (r, v) in [(6.5, cpu), (4.4, ram), (2.3, disk)] as [(CGFloat, Double)] {
                ctx.saveGState()
                ctx.setAlpha(0.3)
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.restoreGState()
                if !offline, v > 0 {
                    ctx.addArc(center: c, radius: r, startAngle: a(0), endAngle: a(360 * min(v, 100) / 100), clockwise: false)
                    ctx.strokePath()
                }
            }
            if warning {
                // Knock out the arcs under the dot so it reads at 16 px.
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: CGRect(x: 13 - 3.4, y: 3 - 3.4, width: 6.8, height: 6.8))
                ctx.restoreGState()
                ctx.fillEllipse(in: CGRect(x: 13 - 2.4, y: 3 - 2.4, width: 4.8, height: 4.8))
            }
        }

        if offline {
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 2.6, y: 13.4))
            ctx.addLine(to: CGPoint(x: 13.4, y: 2.6))
            ctx.strokePath()
        }
    }

    /// The offline glyph in red on the dark app-icon tile, for notification attachments.
    static func notificationTile(_ kind: Kind, size: CGFloat = 76, level: StatusLevel = .offline) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 9 / 38, cornerHeight: rect.width * 9 / 38, transform: nil)
            ctx.addPath(path); ctx.clip()
            let colors = [NSColor(srgbRed: 0x3A / 255, green: 0x3A / 255, blue: 0x3C / 255, alpha: 1).cgColor,
                          NSColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
                // 160°: from top, slightly left, to bottom, slightly right.
                ctx.drawLinearGradient(g, start: CGPoint(x: rect.width * 0.41, y: 0), end: CGPoint(x: rect.width * 0.59, y: rect.height),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            let glyph = rect.width * 0.55
            ctx.translateBy(x: (rect.width - glyph) / 2, y: (rect.height - glyph) / 2)
            ctx.scaleBy(x: glyph / 16, y: glyph / 16)
            draw(kind, level: level, in: ctx, color: level == .offline ? NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1) : .white)
            return true
        }
    }

    static func accessibilityLabel(server: String, status: Status, running: Int, total: Int) -> String {
        switch status.level {
        case .healthy: "Pulse, \(server) healthy, \(running) of \(total) containers running"
        case .warning: "Pulse, \(server) warning, \(status.reasons.joined(separator: ", ")), \(running) of \(total) containers running"
        case .offline: "Pulse, \(server) offline"
        }
    }
}
