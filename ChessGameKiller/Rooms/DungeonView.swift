import SwiftUI

/// The Dungeon's cells: the endgames where the side to move must save a worse position, one a
/// day, the same for everyone that day. Holding the draw escapes the cell. Escapes are kept by
/// day ("2026-11-14": the cell's study), so each day's cell counts once.
enum DungeonCells {
    static let escapesKey = "dungeon.escapes"

    /// Every cell, easiest first: the draws to hold from the endgame library.
    static func all(_ content: GrandmasterContent = .shared) -> [EndgameStudy] {
        content.endgames.filter { $0.goal == .draw }.sorted { $0.level < $1.level }
    }

    /// Days since 2026-01-01 in the player's calendar: the cell turns at midnight.
    static func dayNumber(_ date: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .distantPast
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                       to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func today(_ date: Date = .now, cells: [EndgameStudy] = all(), calendar: Calendar = .current) -> EndgameStudy? {
        guard !cells.isEmpty else { return nil }
        let day = dayNumber(date, calendar: calendar)
        return cells[((day % cells.count) + cells.count) % cells.count]
    }

    static func dayKey(_ date: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func escapes(_ defaults: UserDefaults = .standard) -> [String: String] {
        defaults.dictionary(forKey: escapesKey) as? [String: String] ?? [:]
    }

    static func escapedCount(_ defaults: UserDefaults = .standard) -> Int { escapes(defaults).count }

    static func escapedToday(_ date: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        escapes(defaults)[dayKey(date)] != nil
    }

    /// The studies ever escaped from, as a cell.
    static func escapedStudies(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(escapes(defaults).values)
    }

    static func markEscaped(_ study: EndgameStudy, on date: Date = .now, defaults: UserDefaults = .standard) {
        var all = escapes(defaults)
        all[dayKey(date)] = study.id
        defaults.set(all, forKey: escapesKey)
    }

    /// Escapes on days in a row, up to today (or yesterday, while today's cell is still locked).
    static func run(_ date: Date = .now, defaults: UserDefaults = .standard, calendar: Calendar = .current) -> Int {
        let all = escapes(defaults)
        var day = date
        if all[dayKey(day, calendar: calendar)] == nil {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while all[dayKey(day, calendar: calendar)] != nil {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }
}

/// The Dungeon (Alex's pick, 2026-11-14): you start in a losing spot and must save the game to
/// escape. A new cell each day. The cell plays as an endgame against perfect defence.
struct DungeonView: View {
    let theme: BoardTheme
    @State private var playing: EndgameStudy?
    /// Bumped when a cell is left, so the escape shows at once.
    @State private var refresh = 0
    /// How many times the cell had been held before this visit.
    @State private var heldBefore = 0

    var body: some View {
        let cells = DungeonCells.all()
        ScrollView {
            VStack(spacing: 14) {
                Text("You start in a losing spot. Save the game to escape. A new cell opens each day.")
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(CastleStyle.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                if let cell = DungeonCells.today(cells: cells) {
                    todayCard(cell, number: (cells.firstIndex(of: cell) ?? 0) + 1)
                }
                CastleSectionTitle(text: "The cells")
                cellRow(cells)
            }
            .id(refresh)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(item: $playing, onDismiss: noteEscape) { study in
            EndgameView(study: study, theme: theme)
                .environment(EndgameProgress.shared)
        }
    }

    private func todayCard(_ cell: EndgameStudy, number: Int) -> some View {
        let escaped = DungeonCells.escapedToday()
        let run = DungeonCells.run()
        return CastleCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: escaped ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(escaped ? CastleStyle.gold : CastleStyle.ink)
                    Text("TODAY'S CELL · \(number)")
                        .font(.custom(CastleStyle.titleFont, size: 15, relativeTo: .headline))
                        .tracking(1.5)
                        .foregroundStyle(CastleStyle.ink)
                    Spacer(minLength: 0)
                    Text(cell.levelName)
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(CastleStyle.gold)
                }
                Text(escaped ? "You escaped today. A new cell opens tomorrow."
                     : "Play \(cell.player.displayName). Hold on for \(cell.movesToHold) good moves and the door opens.")
                    .font(.app(.body, weight: .medium))
                    .foregroundStyle(CastleStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if run > 1 {
                    Label("\(run) days in a row", systemImage: "flame.fill")
                        .font(.app(.footnote, weight: .semibold))
                        .foregroundStyle(CastleStyle.gold)
                }
                Button {
                    heldBefore = EndgameProgress.shared.records[cell.id]?.completions ?? 0
                    playing = cell
                } label: {
                    Text(escaped ? "Play it again" : "Enter the cell")
                        .font(.app(.headline))
                        .foregroundStyle(escaped ? CastleStyle.ink : CastleStyle.stone)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(escaped ? AnyShapeStyle(CastleStyle.panel) : AnyShapeStyle(CastleStyle.gold),
                                    in: Capsule())
                        .overlay { Capsule().strokeBorder(CastleStyle.edge, lineWidth: escaped ? 0.75 : 0) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One lock for every cell, open once escaped.
    private func cellRow(_ cells: [EndgameStudy]) -> some View {
        let escaped = DungeonCells.escapedStudies()
        return CastleCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(cells) { cell in
                        Image(systemName: escaped.contains(cell.id) ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(escaped.contains(cell.id) ? CastleStyle.gold : CastleStyle.ink2.opacity(0.6))
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("\(escaped.count) of \(cells.count) cells escaped")
                Text("\(cells.filter { escaped.contains($0.id) }.count) of \(cells.count) cells escaped")
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(CastleStyle.ink2)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Back from the cell: held today, it's an escape.
    private func noteEscape() {
        guard let cell = DungeonCells.today(),
              let record = EndgameProgress.shared.records[cell.id],
              record.completions > heldBefore else { return }
        DungeonCells.markEscaped(cell)
        refresh += 1
    }
}
