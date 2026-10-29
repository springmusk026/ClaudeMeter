// ClaudeMeter's widget: the 5-hour limit ring (small) plus weekly limits and
// today's usage (medium). Reads the summary the app writes; see WidgetData.

import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let data: WidgetData?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), data: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), data: context.isPreview ? (WidgetData.load() ?? .sample) : WidgetData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app reloads the widget when its numbers change; this is a fallback
        let now = Date()
        completion(Timeline(entries: [Entry(date: now, data: WidgetData.load())],
                            policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

struct ClaudeMeterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        let level = entry.data.flatMap { d in d.fiveHour.map { d.level($0.percent) } } ?? .normal
        Group {
            switch family {
            case .systemMedium: WidgetMediumView(data: entry.data, now: entry.date)
            default:            WidgetSmallView(data: entry.data, now: entry.date)
            }
        }
        .containerBackground(for: .widget) { WidgetBackground(level: level) }
    }
}

@main
struct ClaudeMeterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeMeter", provider: Provider()) { entry in
            ClaudeMeterWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Your 5-hour limit, weekly limits and today's usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

extension WidgetData {
    /// Shown in the widget gallery before the app has written real data.
    static var sample: WidgetData {
        let now = Date()
        return WidgetData(plan: "Max 20×",
                          fiveHour: Gauge(percent: 48, resets: now.addingTimeInterval(3 * 3600)),
                          weekly: Gauge(percent: 31, resets: now.addingTimeInterval(3 * 86400)),
                          models: [NamedGauge(name: "Sonnet only", gauge: Gauge(percent: 18, resets: now.addingTimeInterval(3 * 86400)))],
                          todayCost: 8.42, todayTokens: 10_100_000, working: true, updated: now)
    }
}
