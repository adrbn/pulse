import AppKit
import Observation
import PulseKit
import SwiftUI

/// Menu bar item: left click toggles the glass popover, right click shows Refresh / Settings / Quit.
/// AppKit instead of `MenuBarExtra` because `MenuBarExtra` has no right-click menu.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let monitor: Monitor
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var panel: PopoverPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var anchorTop: CGFloat = 0
    private var closedAt = Date.distantPast
    let openSettings: () -> Void

    init(monitor: Monitor, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.openSettings = openSettings
        super.init()
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
        observe()
    }

    /// Re-render the icon whenever the snapshot, status or settings change.
    private func observe() {
        withObservationTracking {
            _ = monitor.snapshot; _ = monitor.status
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon(); self?.observe() }
        }
    }

    func updateIcon() {
        let d = AppGroup.defaults
        let kind = MenuBarIcon.kind(style: d.value(Pref.style, default: .halo), mode: d.value(Pref.iconMode, default: .status),
                                    server: monitor.snapshot?.server)
        item.button?.image = MenuBarIcon.image(kind, level: monitor.status.level)
        let s = monitor.snapshot
        item.button?.setAccessibilityLabel(MenuBarIcon.accessibilityLabel(server: s?.server.name ?? "server", status: monitor.status,
                                                                          running: s?.running ?? 0, total: s?.total ?? 0))
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    private func showMenu() {
        close()
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc func refreshNow() { Task { await monitor.refresh() } }
    @objc private func settings() { close(); openSettings() }

    /// The status item lives outside Pulse's process, so clicking it to close first fires the "click elsewhere"
    /// monitor on mouse-down, then this toggle on mouse-up: don't reopen what that click just closed.
    func toggle() {
        if panel?.isVisible == true { close() } else if Date.now.timeIntervalSince(closedAt) > 0.5 { open() }
    }

    private func open() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let button = item.button, let window = button.window else { return }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = panel.contentView?.fittingSize ?? NSSize(width: 360, height: 500)
        anchorTop = rect.minY - 6
        let x = min(max(rect.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchorTop - size.height, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSApp.activate()
        monitor.popoverOpen = true
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let code = e.keyCode, cmd = e.modifierFlags.contains(.command), chars = e.charactersIgnoringModifiers
            let handled = MainActor.assumeIsolated { self?.handleKey(code: code, command: cmd, chars: chars) ?? false }
            return handled ? nil : e
        }
    }

    private func handleKey(code: UInt16, command: Bool, chars: String?) -> Bool {
        if code == 53 { close(); return true }                          // Esc
        guard command else { return false }
        switch chars {
        case "r": refreshNow(); return true
        case ",": settings(); return true
        case "q": NSApp.terminate(nil); return true
        default: return false
        }
    }

    func close() {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        closedAt = .now
        monitor.popoverOpen = false
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func makePanel() -> PopoverPanel {
        let host = NSHostingView(rootView: PopoverRoot(monitor: monitor, openSettings: { [weak self] in self?.settings() }))
        host.sizingOptions = [.preferredContentSize]
        // Clip the window itself to the popover shape: otherwise the transparent panel keeps square corners
        // and a rectangular shadow wherever it is taller than the SwiftUI content.
        host.wantsLayer = true
        host.layer?.cornerRadius = 24
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        let panel = PopoverPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 500),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.delegate = self
        return panel
    }

    /// Content height changes (expanding a stack, "All 43"): keep the top edge under the menu bar.
    func windowDidResize(_ notification: Notification) {
        guard let panel, panel.isVisible else { return }
        var f = panel.frame
        if abs(f.maxY - anchorTop) > 0.5 { f.origin.y = anchorTop - f.height; panel.setFrame(f, display: true) }
        panel.invalidateShadow()
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}

final class PopoverPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backing, defer: flag)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
    }
    override var canBecomeKey: Bool { true }
}
