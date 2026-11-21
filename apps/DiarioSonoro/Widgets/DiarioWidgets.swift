import WidgetKit
import SwiftUI
import AppIntents
import SonoroCore

@main
struct DiarioWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        RecordControl()
    }
}

// MARK: - Today widget (Home + Lock Screen)

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let hasData: Bool
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .placeholder, hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let e = entry()
        completion(context.isPreview && !e.hasData ? placeholder(in: context) : e)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let midnight = DayDate.today().adding(days: 1).date(minuteOfDay: 0)
        // Refresh at midnight (counters reset) or in an hour, whichever comes first.
        let next = min(midnight.addingTimeInterval(5), now.addingTimeInterval(3600))
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> TodayEntry {
        let today = DayDate.today()
        guard let s = SharedStore.loadSnapshot() else {
            return TodayEntry(date: Date(), snapshot: WidgetSnapshot(day: today), hasData: false)
        }
        return TodayEntry(date: Date(), snapshot: s.effective(on: today), hasData: true)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Diario Sonoro")
        .description("Le clip di oggi e un tocco per registrare il suono intorno a te.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        TodayWidgetContent(snapshot: entry.snapshot, family: family, hasData: entry.hasData)
            .widgetURL(DeepLink.record(.widget).url)
            .containerBackground(for: .widget) {
                WidgetBackground()
            }
    }
}

// MARK: - Control Center / Action button (iOS 18+)

struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.garoth93.diariosonoro.record") {
            ControlWidgetButton(action: ControlRecordIntent()) {
                Label("Registra suono", systemImage: "mic.fill")
            }
        }
        .displayName("Registra suono")
        .description("Apre Diario Sonoro pronto a registrare: dal Centro di Controllo, dalla schermata di blocco o dal tasto Azione.")
    }
}
