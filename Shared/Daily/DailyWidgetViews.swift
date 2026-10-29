import SwiftUI

// The widget's faces: Today's Move as a printed diagram, and the streak. Compiled into the app
// too, so the app's tests can draw them; the widget extension adds WidgetKit's frame around them.
// SwiftUI and Foundation only.

/// Everything one face of the widget shows, for one moment.
struct DailyWidgetEntry {
    let date: Date
    let puzzle: DailyPuzzle?
    let snapshot: DailySnapshot
    var calendar: Calendar = .current

    var day: String { DailyMoves.dayKey(date, calendar: calendar) }
    var streak: Int { snapshot.streakShown(on: day) }
    var doneToday: Bool { snapshot.isDone(on: day) }
    var playedMove: Bool { snapshot.playedMove(on: day) }

    /// "Thursday", for the dateline.
    var weekday: String { date.formatted(.dateTime.weekday(.wide)) }

    /// The streak said in a few words: "12-day streak", "Start a streak today".
    var streakLine: String {
        switch streak {
        case 0: return "Start a streak today"
        case 1: return "1-day streak"
        default: return "\(streak)-day streak"
        }
    }

    /// What's left today: nothing, or the one small thing that keeps the streak.
    var statusLine: String {
        if playedMove { return snapshot.moveFound ? "Solved today" : "Played today" }
        if doneToday { return "Done for today" }
        return streak > 0 ? "Keep it going today" : "One move a day"
    }
}

/// The faces, matching the widget sizes.
enum DailyWidgetStyle {
    case small, medium, circular, rectangular, inline
}

/// The colors of the home screen: charcoal, ivory ink and the gold of the Gilded look.
enum DailyPalette {
    static let canvas = Color(red: 0.075, green: 0.071, blue: 0.067)
    static let ink = Color(red: 0.965, green: 0.945, blue: 0.91)
    static let gold = Color(red: 0.87, green: 0.68, blue: 0.40)
    static let light = Color(red: 0.804, green: 0.737, blue: 0.612)
    static let dark = Color(red: 0.333, green: 0.204, blue: 0.125)
}

/// One face of the widget.
struct DailyWidgetView: View {
    let entry: DailyWidgetEntry
    let style: DailyWidgetStyle

    var body: some View {
        switch style {
        case .small: small
        case .medium: medium
        case .circular: circular
        case .rectangular: rectangular
        case .inline: inline
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                flame
                Text("\(entry.streak)")
                    .font(.system(.subheadline, design: .serif, weight: .semibold).monospacedDigit())
                    .foregroundStyle(DailyPalette.ink)
                Spacer(minLength: 4)
                check
            }
            diagram
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 14) {
            diagram
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.puzzle.map { "TODAY'S MOVE · NO. \($0.number)" } ?? "TODAY'S MOVE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(DailyPalette.gold)
                Text(entry.puzzle?.headline ?? "A new puzzle every day.")
                    .font(.system(.headline, design: .serif, weight: .medium))
                    .foregroundStyle(DailyPalette.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.puzzle.map { "\(entry.weekday) · \($0.difficulty)" } ?? entry.weekday)
                    .font(.caption)
                    .foregroundStyle(DailyPalette.ink.opacity(0.6))
                Spacer(minLength: 2)
                HStack(spacing: 5) {
                    flame
                    Text(entry.streakLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DailyPalette.ink)
                }
                Text(entry.statusLine)
                    .font(.caption2)
                    .foregroundStyle(entry.doneToday ? DailyPalette.gold : DailyPalette.ink.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var diagram: some View {
        if let puzzle = entry.puzzle {
            DailyDiagram(fen: puzzle.shownFEN, flipped: !puzzle.solverIsWhite)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(DailyPalette.ink.opacity(0.08))
                .aspectRatio(1, contentMode: .fit)
        }
    }

    private var flame: some View {
        Image(systemName: "flame.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(entry.streak > 0 ? DailyPalette.gold : DailyPalette.ink.opacity(0.35))
    }

    @ViewBuilder
    private var check: some View {
        if entry.doneToday {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(DailyPalette.gold)
        } else if let puzzle = entry.puzzle {
            Text("No. \(puzzle.number)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(DailyPalette.ink.opacity(0.6))
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        VStack(spacing: 0) {
            Image(systemName: entry.doneToday ? "flame.fill" : "flame")
                .font(.system(size: 15, weight: .bold))
            Text("\(entry.streak)")
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: entry.doneToday ? "flame.fill" : "flame")
                Text(entry.streakLine)
            }
            .font(.headline)
            Text(entry.puzzle?.headline ?? "Today's Move")
                .font(.caption)
                .lineLimit(1)
            Text(entry.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var inline: some View {
        Label(entry.streak > 0 ? "\(entry.streak) · \(entry.statusLine)" : "Today's Move is ready",
              systemImage: "flame.fill")
    }

    private var accessibilitySummary: String {
        let move = entry.puzzle.map { "Today's Move: \($0.headline)" } ?? "Today's Move"
        return "\(entry.streakLine). \(entry.statusLine). \(move)"
    }
}

/// A position printed like a newspaper diagram: flat squares, the classic pieces, a fine rule round
/// the edge. Reads the piece placement straight from the FEN, so it needs no chess library.
struct DailyDiagram: View {
    let fen: String
    /// Black at the bottom, for a puzzle Black solves.
    let flipped: Bool

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let square = side / 8
            let cells = Self.cells(fen)
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { column in
                            cell(row: row, column: column, cells: cells, square: square)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .overlay { Rectangle().strokeBorder(DailyPalette.ink.opacity(0.35), lineWidth: 0.5) }
        }
        .aspectRatio(1, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func cell(row: Int, column: Int, cells: [String?], square: CGFloat) -> some View {
        // Row 0 is the top of the picture: rank 8 for White at the bottom, rank 1 for Black.
        let rank = flipped ? row : 7 - row
        let file = flipped ? 7 - column : column
        let isLight = (rank + file) % 2 == 1
        let piece = cells[(7 - rank) * 8 + file]
        return ZStack {
            Rectangle().fill(isLight ? DailyPalette.light : DailyPalette.dark)
            if let piece {
                Image(piece)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(square * 0.04)
            }
        }
        .frame(width: square, height: square)
    }

    /// The 64 squares from a FEN's placement, rank 8 first, a1 last of its rank: each "wK", "bP"… or nil.
    static func cells(_ fen: String) -> [String?] {
        var cells: [String?] = []
        let placement = fen.split(separator: " ").first ?? ""
        for rank in placement.split(separator: "/") {
            for character in rank {
                if let empty = character.wholeNumberValue {
                    cells.append(contentsOf: Array(repeating: nil, count: empty))
                } else {
                    let color = character.isUppercase ? "w" : "b"
                    cells.append(color + character.uppercased())
                }
            }
        }
        if cells.count < 64 { cells.append(contentsOf: Array(repeating: nil, count: 64 - cells.count)) }
        return Array(cells.prefix(64))
    }
}
