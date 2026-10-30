import SwiftUI
import WidgetKit

// The Home Screen and Lock Screen widget: Today's Move and the streak. The faces are drawn by
// DailyWidgetView (Shared/Daily), which the app's tests draw too. The app writes the streak to
// the app group (DailySnapshot) and asks for a fresh timeline whenever it changes; the widget
// turns the page itself at midnight, when a new puzzle starts.
// The bundle also draws the game under way on the Lock Screen and in the Dynamic Island
// (LiveGameWidget.swift).

@main
struct ChessGameKillerWidgets: WidgetBundle {
    var body: some Widget {
        DailyMoveWidget()
        LiveGameWidget()
    }
}

struct DailyMoveWidget: Widget {
    static let kind = "DailyMove"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: DailyTimeline()) { entry in
            DailyWidgetFace(entry: entry)
        }
        .configurationDisplayName("Today's Move")
        .description("The puzzle of the day and your streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// One entry now, then one at each of the next two midnights (if the app isn't opened, the
/// streak and the puzzle still turn over on time).
struct DailyTimeline: TimelineProvider {
    func placeholder(in context: Context) -> DailyWidgetEntry {
        entry(at: .now, snapshot: DailySnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyWidgetEntry) -> Void) {
        completion(entry(at: .now, snapshot: DailySnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyWidgetEntry>) -> Void) {
        let snapshot = DailySnapshot.read()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries = [entry(at: .now, snapshot: snapshot)]
        for offset in 1...2 {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: today) {
                entries.append(entry(at: midnight, snapshot: snapshot))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, snapshot: DailySnapshot) -> DailyWidgetEntry {
        DailyWidgetEntry(date: date, puzzle: DailyMoves.puzzle(for: date), snapshot: snapshot)
    }
}

extension DailyWidgetEntry: TimelineEntry {}

/// The face for the widget's size, in WidgetKit's frame. Tapping it opens Today's Move.
struct DailyWidgetFace: View {
    let entry: DailyWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(URL(string: "chessgamekiller://daily"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            DailyWidgetView(entry: entry, style: .medium)
                .containerBackground(DailyPalette.canvas, for: .widget)
        case .accessoryCircular:
            DailyWidgetView(entry: entry, style: .circular)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            DailyWidgetView(entry: entry, style: .rectangular)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            DailyWidgetView(entry: entry, style: .inline)
                .containerBackground(for: .widget) { Color.clear }
        default:
            DailyWidgetView(entry: entry, style: .small)
                .containerBackground(DailyPalette.canvas, for: .widget)
        }
    }
}
