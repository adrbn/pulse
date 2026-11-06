import AppKit
import PulseKit
import SwiftUI

/// A widget-looking panel on the desktop, fed live by the Monitor: no WidgetKit reload budget.
@MainActor
final class DesktopWidget {
    private let monitor: Monitor
    private var panel: NSPanel?
    private var size: String = "off"

    init(monitor: Monitor) { self.monitor = monitor }

    /// Shows, resizes or hides the panel to match Settings → Appearance → Desktop widget.
    func update() {
        let wanted = AppGroup.defaults.string(forKey: Pref.desktopWidget) ?? "off"
        guard wanted != size else { return }
        size = wanted
        panel?.close()
        panel = nil
        guard wanted != "off" else { return }
        let medium = wanted == "medium"
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: medium ? 364 : 170, height: 170),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        // Above the desktop icons, below every app window, on all Spaces: where native widgets sit.
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isMovableByWindowBackground = true
        p.contentView = NSHostingView(rootView: DesktopWidgetView(monitor: monitor, size: medium ? .medium : .small))
        if !p.setFrameUsingName("PulseDesktopWidget") { p.center() }
        p.setFrameAutosaveName("PulseDesktopWidget")
        p.setContentSize(NSSize(width: medium ? 364 : 170, height: 170))
        p.orderFront(nil)
        panel = p
    }
}

private struct DesktopWidgetView: View {
    let monitor: Monitor
    let size: WidgetSize
    @AppStorage(Pref.style, store: AppGroup.defaults) private var style = PulseStyle.halo
    @AppStorage(Pref.containerRing, store: AppGroup.defaults) private var ring = ContainerRing.ticks

    var body: some View {
        // Ticks so "Updated N min ago" appears if the Monitor ever stops publishing.
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            PulseWidgetView(snap: monitor.snapshot ?? Fixtures.snapshot(.offline), status: monitor.status,
                            style: style, variant: ring, size: size, now: ctx.date)
                .padding(16)
                .frame(width: size == .small ? 170 : 364, height: 170)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
    }
}
