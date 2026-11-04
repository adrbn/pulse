import AppKit
import PulseKit
import SwiftUI

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        // The real settings window is an NSTabViewController (toolbar tabs), opened from the status item.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: Monitor?
    private var statusItem: StatusItemController?
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--render-snapshots"), i + 1 < args.count {
            SnapshotRenderer.renderAll(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
            return
        }
        applyAppearance()
        let monitor = Monitor()
        self.monitor = monitor
        statusItem = StatusItemController(monitor: monitor) { [weak self] in self?.showSettings() }
        monitor.start()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyAppearance()
                self?.statusItem?.updateIcon()
            }
        }
        if args.contains("--open-settings") { showSettings() }
        if args.contains("--open-popover") { statusItem?.toggle() }
    }

    func showSettings() {
        guard let monitor else { return }
        let s = settings ?? SettingsWindowController(monitor: monitor)
        settings = s
        s.show()
    }

    private func applyAppearance() {
        let mode = AppGroup.defaults.value(Pref.appearance, default: AppearanceMode.system)
        let target: NSAppearance? = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if NSApp.appearance != target { NSApp.appearance = target }
    }
}
