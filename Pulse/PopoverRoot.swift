import PulseKit
import SwiftUI

/// Popover content: live data from the monitor, styled by the user's settings, on a glass surface.
struct PopoverRoot: View {
    let monitor: Monitor
    let openSettings: () -> Void
    @AppStorage(Pref.style, store: AppGroup.defaults) private var style = PulseStyle.halo
    @AppStorage(Pref.containerRing, store: AppGroup.defaults) private var variant = ContainerRing.ticks
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Group {
                if let snap = monitor.snapshot {
                    VStack(spacing: 0) {
                        PopoverView(snap: snap, status: monitor.status, style: style, variant: variant, now: ctx.date,
                                    actions: PopoverActions(start: monitor.startContainer, openProxmox: openProxmox, openSettings: openSettings))
                        if let err = monitor.lastError { errorBanner(err) }
                    }
                } else {
                    setup
                }
            }
        }
        .pulseSurface(cornerRadius: 24)
    }

    private func errorBanner(_ text: String) -> some View {
        let p = Palette(scheme)
        return Text(text).pulseFont(11).foregroundStyle(p.orange).lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.bottom, 14)
    }

    private var setup: some View {
        let p = Palette(scheme)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Pulse").pulseFont(15, .semibold).foregroundStyle(p.text)
            Text(monitor.lastError ?? "Connecting…").pulseFont(12).foregroundStyle(p.text2)
            Button("Open Settings…", action: openSettings).buttonStyle(.plain).pulseFont(12).foregroundStyle(p.blue)
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }

    private func openProxmox() {
        if let s = AppGroup.defaults.string(forKey: Pref.proxmoxURL), let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}

extension View {
    /// Liquid Glass, or a solid window background when Reduce Transparency is on.
    func pulseSurface(cornerRadius: CGFloat) -> some View { modifier(PulseSurface(cornerRadius: cornerRadius)) }
}

private struct PulseSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape).clipShape(shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
