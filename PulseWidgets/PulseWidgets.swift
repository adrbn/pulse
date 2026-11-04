import AppIntents
import PulseKit
import SwiftUI
import WidgetKit

@main
struct PulseWidgetBundle: WidgetBundle {
    var body: some Widget { PulseWidget() }
}

/// Used only when "Widgets follow this style" is off in Settings → Appearance.
struct StyleIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Pulse"
    static let description = IntentDescription("Server health at a glance.")
    @Parameter(title: "Style", default: .halo) var style: StyleOption
}

enum StyleOption: String, AppEnum {
    case rings, halo, memory, live
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [StyleOption: DisplayRepresentation] = [
        .rings: "Rings", .halo: "Halo", .memory: "Memory", .live: "Live",
    ]
}

struct PulseEntry: TimelineEntry {
    let date: Date
    let snap: Snapshot
    let style: PulseStyle
    let variant: ContainerRing
    let stoppedIsWarning: Bool
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: Fixtures.now, snap: Fixtures.snapshot(), style: .halo, variant: .ticks, stoppedIsWarning: false)
    }

    func snapshot(for configuration: StyleIntent, in context: Context) async -> PulseEntry {
        context.isPreview ? placeholder(in: context) : entry(configuration, date: .now)
    }

    /// The app reloads timelines on every visible change; the entries only age "updated N min ago" and offline status.
    func timeline(for configuration: StyleIntent, in context: Context) async -> Timeline<PulseEntry> {
        let now = Date.now
        let entries = (0..<6).map { entry(configuration, date: now.addingTimeInterval(Double($0) * 300)) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(_ config: StyleIntent, date: Date) -> PulseEntry {
        let d = AppGroup.defaults
        let follow = d.object(forKey: Pref.widgetsFollowStyle) as? Bool ?? true
        let style = follow ? d.value(Pref.style, default: PulseStyle.halo) : PulseStyle(rawValue: config.style.rawValue) ?? .halo
        let snap = Store.loadSnapshot() ?? Fixtures.snapshot(.offline)
        return PulseEntry(date: date, snap: snap, style: style, variant: d.value(Pref.containerRing, default: .ticks),
                          stoppedIsWarning: d.bool(forKey: Pref.stoppedIsWarning))
    }
}

struct PulseWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PulseWidget", intent: StyleIntent.self, provider: Provider()) { e in
            EntryView(entry: e)
        }
        .configurationDisplayName("Pulse")
        .description("Server health at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct EntryView: View {
    let entry: PulseEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        // The app reloads at most every 30 min and WidgetKit may throttle that: only call the server offline past 1 h of silence.
        let stale = entry.date.timeIntervalSince(entry.snap.updatedAt) > 3600
        let status = StatusEngine.evaluate(entry.snap, treatStoppedAsWarning: entry.stoppedIsWarning,
                                           now: stale ? entry.date : entry.snap.updatedAt)
        PulseWidgetView(snap: entry.snap, status: status, style: entry.style, variant: entry.variant,
                        size: family == .systemMedium ? .medium : .small, now: entry.date)
            .containerBackground(.fill.tertiary, for: .widget)
    }
}
