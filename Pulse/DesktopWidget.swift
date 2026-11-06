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
        let frame = NSSize(width: medium ? 344 : 163, height: 163)   // measured on the native desktop widget
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: frame),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        // Above the desktop icons, below every app window, on all Spaces: where native widgets sit.
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.isMovableByWindowBackground = true
        p.contentView = DraggableHostingView(rootView: DesktopWidgetView(monitor: monitor, size: medium ? .medium : .small, frame: frame))
        if !p.setFrameUsingName("PulseDesktopWidget") { p.center() }
        p.setFrameAutosaveName("PulseDesktopWidget")
        p.setContentSize(frame)
        p.orderFront(nil)
        p.invalidateShadow()
        panel = p
    }
}

/// SwiftUI swallows mouse-downs, so isMovableByWindowBackground alone never drags the panel.
private final class DraggableHostingView<V: View>: NSHostingView<V> {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

private struct DesktopWidgetView: View {
    let monitor: Monitor
    let size: WidgetSize
    let frame: NSSize
    @AppStorage(Pref.style, store: AppGroup.defaults) private var style = PulseStyle.halo
    @AppStorage(Pref.containerRing, store: AppGroup.defaults) private var ring = ContainerRing.ticks
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Ticks so "Updated N min ago" appears if the Monitor ever stops publishing.
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            PulseWidgetView(snap: monitor.snapshot ?? Fixtures.snapshot(.offline), status: monitor.status,
                            style: style, variant: ring, size: size, now: ctx.date)
                .padding(16)
                .frame(width: frame.width, height: frame.height)
                // Same card as the native widget: a soft top-to-bottom gradient, sampled from a screenshot of it.
                .background(LinearGradient(colors: scheme == .dark ? [Color(white: 0.22), Color(white: 0.12)] : [.white, Color(white: 0.94)],
                                           startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.1)))
        }
    }
}
