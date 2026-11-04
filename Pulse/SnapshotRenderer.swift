import AppKit
import PulseKit
import SwiftUI

/// `Pulse --render-snapshots <dir>`: every popover style × variant × scheme × status, widgets and icons as PNGs.
/// Used to compare against the design reference without clicking through the UI.
@MainActor
enum SnapshotRenderer {
    static func renderAll(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let levels: [StatusLevel] = [.healthy, .warning, .offline]
        for scheme in [ColorScheme.light, .dark] {
            let s = scheme == .dark ? "dark" : "light"
            for level in levels {
                let snap = Fixtures.snapshot(level)
                let status = StatusEngine.evaluate(snap, treatStoppedAsWarning: false, now: Fixtures.now)
                for style in PulseStyle.allCases {
                    let variants: [ContainerRing] = style == .halo ? ContainerRing.allCases : [.ticks]
                    for v in variants {
                        let name = style == .halo ? "\(style.rawValue)-\(v.rawValue)" : style.rawValue
                        let pop = PopoverView(snap: snap, status: status, style: style, variant: v, now: Fixtures.now)
                            .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
                        write(pop, scheme: scheme, to: dir.appendingPathComponent("popover-\(name)-\(level.rawValue)-\(s).png"))
                        for size in [WidgetSize.small, .medium] {
                            let w = PulseWidgetView(snap: snap, status: status, style: style, variant: v, size: size, now: Fixtures.now)
                                .padding(16)
                                .frame(width: size == .small ? 170 : 364, height: 170)
                                .background(scheme == .dark ? Color(white: 0.12) : .white, in: RoundedRectangle(cornerRadius: 22))
                            write(w, scheme: scheme, to: dir.appendingPathComponent("widget-\(size)-\(name)-\(level.rawValue)-\(s).png"))
                        }
                    }
                }
            }
            write(AppearanceTab(monitor: Monitor()).frame(width: 640), scheme: scheme,
                  to: dir.appendingPathComponent("settings-appearance-\(s).png"), background: true)
        }
        for (kname, kind) in [("halo", MenuBarIcon.Kind.halo), ("rings", .rings), ("live", .live(cpu: 23, ram: 61, disk: 48))] {
            for level in levels {
                let img = MenuBarIcon.image(kind, level: level, size: 64, template: false)
                png(img, to: dir.appendingPathComponent("icon-\(kname)-\(level.rawValue).png"))
            }
        }
        png(MenuBarIcon.notificationTile(.halo, size: 152), to: dir.appendingPathComponent("notification-tile.png"))
        png(MenuBarIcon.notificationTile(.halo, size: 824, level: .healthy), to: dir.appendingPathComponent("app-icon-824.png"))
    }

    private static func write(_ view: some View, scheme: ColorScheme, to url: URL, background: Bool = false) {
        let r = ImageRenderer(content: view.environment(\.colorScheme, scheme)
            .background(background ? (scheme == .dark ? Color(white: 0.16) : Color(white: 0.96)) : .clear))
        r.scale = 2
        guard let img = r.nsImage else { NSLog("Pulse: render failed \(url.lastPathComponent)"); return }
        png(img, to: url)
    }

    private static func png(_ img: NSImage, to url: URL) {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        do { try data.write(to: url) } catch { NSLog("Pulse: write failed \(error)") }
    }
}
