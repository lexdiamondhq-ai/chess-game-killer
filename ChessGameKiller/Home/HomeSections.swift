import ChessKit
import SwiftUI

// The cards below the clock: today's puzzle and session, the ladder of rivals, the
// scoresheet of your games, and the rest of the app.

// MARK: - Today

/// A real puzzle drawn as a diagram, the way a chess column prints one, and today's
/// session with Coach Leo. Solve opens Puzzles on this very puzzle; Start starts the session.
struct HomeTodayCard: View {
    let puzzle: HomePuzzle?
    let rating: Int
    let solvedInARow: Int
    let plan: SessionPlan?
    let trainedToday: Bool
    let tone: HomeTone
    let pieceTheme: BoardTheme
    let solve: () -> Void
    let startSession: (SessionPlan) -> Void
    let train: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            puzzleBlock
            HomeHairline(tone: tone)
                .padding(.vertical, 16)
            coachBlock
        }
        .padding(16)
        .homePane(RoundedRectangle(cornerRadius: 28, style: .continuous), tone: tone)
    }

    // MARK: The puzzle

    @ViewBuilder
    private var puzzleBlock: some View {
        if let puzzle, let draft = PositionDraft(fen: puzzle.fen) {
            Button(action: solve) {
                PositionBoard(draft: draft, theme: pieceTheme, flipped: puzzle.solver == .black)
                    .allowsHitTesting(false)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .padding(.bottom, 16)
            Text("Puzzle · \(puzzle.puzzle.rating.formatted())")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tone.metal)
            HStack(alignment: .center, spacing: 12) {
                Text(puzzle.title)
                    .font(HomeType.title)
                    .foregroundStyle(tone.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Solve", action: solve)
                    .buttonStyle(HomeIvoryButtonStyle(tone: tone, compact: true))
                    .accessibilityLabel("Solve: \(puzzle.title)")
            }
            .padding(.top, 4)
            Text(ratingLine)
                .font(.footnote)
                .foregroundStyle(tone.ink2)
                .padding(.top, 6)
        } else {
            // The pack is still loading (or missing): the rating and the way in.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Puzzles")
                        .font(HomeType.title)
                        .foregroundStyle(tone.ink)
                    Text(ratingLine)
                        .font(.footnote)
                        .foregroundStyle(tone.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Solve", action: solve)
                    .buttonStyle(HomeIvoryButtonStyle(tone: tone, compact: true))
                    .accessibilityLabel("Solve puzzles")
            }
        }
    }

    private var ratingLine: String {
        let base = "Your rating \(rating.formatted())"
        return solvedInARow > 1 ? "\(base) · \(solvedInARow) in a row" : base
    }

    // MARK: Coach Leo

    @ViewBuilder
    private var coachBlock: some View {
        Text("Today with Coach Leo")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tone.metal)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(coachTitle)
                    .font(HomeType.title)
                    .foregroundStyle(tone.ink)
                Text(coachDetail)
                    .font(.subheadline)
                    .foregroundStyle(tone.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !trainedToday, let plan {
                Button("Start") { startSession(plan) }
                    .buttonStyle(HomeIvoryButtonStyle(tone: tone, compact: true))
                    .accessibilityLabel("Start today's session: \(coachTitle)")
            } else {
                Button("Train", action: train)
                    .buttonStyle(HomeIvoryButtonStyle(tone: tone, compact: true))
                    .accessibilityLabel("Open training")
            }
        }
        .padding(.top, 4)
    }

    private var coachTitle: String {
        if trainedToday { return "Done for today" }
        guard let plan else { return "Lessons and drills" }
        return "\(plan.focus?.title ?? "Today's session") · \(plan.minutes) min"
    }

    private var coachDetail: String {
        if trainedToday { return "A new session waits tomorrow. Train more any time." }
        guard let plan else { return "Short lessons, then positions picked for you." }
        let count = plan.items.count
        let positions = count == 1 ? "1 position" : "\(count) positions"
        let shape = plan.lesson == nil ? "\(positions), picked for you." : "A short lesson, then \(positions)."
        if let blurb = plan.focus?.blurb { return "\(blurb) \(shape)" }
        return shape
    }
}

// MARK: - The ladder

/// The five rivals as rungs, strongest at the top, with your score against each and the
/// one to beat next lit in gold. Your own level stands between the rungs once there are a
/// few games to go on. Tap a rung to set up a game against that rival.
struct HomeLadderCard: View {
    let ladder: HomeLadder
    let tone: HomeTone
    let pieceTheme: BoardTheme
    let youColor: Piece.Color
    let play: (MatchController.Level) -> Void

    @ScaledMetric(relativeTo: .body) private var portrait: CGFloat = 36

    private enum Entry: Identifiable {
        case rung(HomeLadder.Rung)
        case you(Int)

        var id: Int {
            switch self {
            case .rung(let rung): return rung.id
            case .you: return -1
            }
        }
    }

    /// Strongest first, with you between the rungs at your level.
    private var entries: [Entry] {
        var list: [Entry] = []
        var placed = ladder.yourRating == nil
        for rung in ladder.rungs.reversed() {
            if !placed, let rating = ladder.yourRating, rating > rung.level.rating {
                list.append(.you(rating))
                placed = true
            }
            list.append(.rung(rung))
        }
        if !placed, let rating = ladder.yourRating { list.append(.you(rating)) }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    HomeHairline(tone: tone, inset: 26 + portrait)
                }
                switch entry {
                case .rung(let rung): rungRow(rung)
                case .you(let rating): youRow(rating)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .homePane(RoundedRectangle(cornerRadius: 28, style: .continuous), tone: tone)
    }

    private func rungRow(_ rung: HomeLadder.Rung) -> some View {
        let rival = rung.level.rival
        let isNext = ladder.nextToBeat == rung.level
        return Button {
            play(rung.level)
        } label: {
            HStack(spacing: 12) {
                Text("\(rung.level.rawValue + 1)")
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .foregroundStyle(tone.ink3)
                    .frame(width: 14)
                Image(rival.portraitName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: portrait, height: portrait)
                    .clipShape(Circle())
                    .overlay { Circle().strokeBorder(tone.ink.opacity(0.16), lineWidth: 0.5) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(rival.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(tone.ink)
                        Text(rival.elo)
                            .font(.subheadline)
                            .foregroundStyle(tone.ink2)
                    }
                    Text(isNext ? "Next to beat · \(rung.level.tagline)" : rung.level.tagline)
                        .font(.footnote)
                        .foregroundStyle(isNext ? tone.metal : tone.ink2)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(rung.score ?? "–")
                        .font(HomeType.score)
                        .monospacedDigit()
                        .foregroundStyle(rung.played == 0 ? tone.ink3 : tone.ink)
                    Text(rung.standingText)
                        .font(.caption)
                        .foregroundStyle(tone.ink3)
                }
                .lineLimit(1)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeRowPressStyle(tone: tone))
        .background {
            if isNext {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tone.metal.opacity(0.09))
                    .padding(.horizontal, -8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(rung, isNext: isNext))
        .accessibilityHint("Sets up a game against \(rival.name)")
        .accessibilityAddTraits(.isButton)
    }

    private func spoken(_ rung: HomeLadder.Rung, isNext: Bool) -> String {
        let rival = rung.level.rival
        var parts = ["\(rival.name), rung \(rung.level.rawValue + 1), rated \(rung.level.spokenRating)"]
        if isNext { parts.append("next to beat") }
        if rung.played == 0 {
            parts.append("not played yet")
        } else {
            parts.append("\(rung.standingText), \(Self.spokenPoints(rung.yourPoints)) to \(Self.spokenPoints(rung.theirPoints))")
        }
        return parts.joined(separator: ". ")
    }

    static func spokenPoints(_ value: Double) -> String {
        let whole = Int(value.rounded(.down))
        guard value - Double(whole) >= 0.5 else { return "\(whole)" }
        return whole == 0 ? "a half" : "\(whole) and a half"
    }

    private func youRow(_ rating: Int) -> some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 14, height: 1)
            PieceImage(piece: Piece(.king, color: youColor, square: youColor == .white ? .e1 : .e8),
                       theme: pieceTheme, size: portrait)
                .frame(width: portrait, height: portrait)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("You")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tone.metal)
                    Text("~\(rating.formatted())")
                        .font(.subheadline)
                        .foregroundStyle(tone.ink2)
                }
                Text("Your level, from \(ladder.gamesCounted) games")
                    .font(.footnote)
                    .foregroundStyle(tone.ink2)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You, playing at about \(rating), from \(ladder.gamesCounted) games")
    }
}

// MARK: - Your games

/// Your last games as a tournament scoresheet: the day, the rival, the result, your accuracy
/// and the moves left to fix. A row opens that game in Rewind.
struct HomeScoresheet: View {
    let rows: [HomeGameRow]
    let total: Int
    let tone: HomeTone
    let open: (SavedGame) -> Void
    let openAll: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var dayWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .subheadline) private var resultWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .subheadline) private var accuracyWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .subheadline) private var reviewWidth: CGFloat = 54

    /// Room for the columns: false on a narrow phone, where each game takes two lines.
    @State private var roomy = true

    /// Columns while they fit; at large text sizes or on a narrow phone each game takes two lines instead.
    private var columns: Bool { typeSize <= .xLarge && roomy }

    var body: some View {
        VStack(spacing: 0) {
            if columns {
                header
            }
            ForEach(rows) { row in
                if columns || row.id != rows.first?.id {
                    HomeHairline(tone: tone)
                }
                Button {
                    open(row.game)
                } label: {
                    label(row)
                }
                .buttonStyle(HomeRowPressStyle(tone: tone))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(row))
                .accessibilityHint("Opens it in Rewind")
                .accessibilityAddTraits(.isButton)
            }
            HomeHairline(tone: tone)
            Button(action: openAll) {
                HStack {
                    Text(total == 1 ? "Your game" : "All \(total) games")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tone.ink3)
                }
                .foregroundStyle(tone.ink)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeRowPressStyle(tone: tone))
        }
        .onGeometryChange(for: Bool.self) { proxy in
            // Date, result, accuracy and review take about 260 points; the rival needs the rest.
            proxy.size.width >= 330
        } action: { fits in
            roomy = fits
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .homePane(RoundedRectangle(cornerRadius: 28, style: .continuous), tone: tone)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Date").frame(width: dayWidth, alignment: .leading)
            Text("Rival").frame(maxWidth: .infinity, alignment: .leading)
            Text("Result").frame(width: resultWidth, alignment: .leading)
            Text("Accuracy").frame(width: accuracyWidth, alignment: .trailing)
            Text("Review").frame(width: reviewWidth, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .tracking(0.6)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(tone.ink3)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func label(_ row: HomeGameRow) -> some View {
        if columns {
            HStack(spacing: 8) {
                Text(row.day)
                    .foregroundStyle(tone.ink2)
                    .frame(width: dayWidth, alignment: .leading)
                rival(row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                result(row.game.result)
                    .frame(width: resultWidth, alignment: .leading)
                Text(row.game.accuracy.map { "\($0)%" } ?? "–")
                    .monospacedDigit()
                    .foregroundStyle(tone.ink)
                    .frame(width: accuracyWidth, alignment: .trailing)
                fix(row)
                    .frame(width: reviewWidth, alignment: .trailing)
            }
            .font(.subheadline)
            .lineLimit(1)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    rival(row)
                    Spacer(minLength: 8)
                    result(row.game.result)
                }
                HStack(spacing: 8) {
                    Text(row.day)
                    Text(row.game.accuracy.map { "\($0)% accuracy" } ?? "No accuracy")
                    Spacer(minLength: 8)
                    fix(row)
                }
                .foregroundStyle(tone.ink2)
            }
            .font(.subheadline)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    private func rival(_ row: HomeGameRow) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                if let level = row.level {
                    Image(level.rival.portraitName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                }
                Text(row.game.opponent)
            }
            .fixedSize()
            Text(row.game.opponent)
                .lineLimit(1)
        }
        .foregroundStyle(tone.ink)
    }

    private func result(_ result: SavedGame.Result) -> some View {
        HStack(spacing: 5) {
            Image(systemName: Self.mark(result))
                .font(.caption2.weight(.bold))
                .foregroundStyle(result == .win ? tone.metal : tone.ink2)
            Text(result.title)
                .foregroundStyle(tone.ink)
        }
    }

    private func fix(_ row: HomeGameRow) -> some View {
        Text(row.toFix > 0 ? "\(row.toFix) to fix" : "–")
            .foregroundStyle(row.toFix > 0 ? tone.metal : tone.ink3)
    }

    /// A filled disc for a win, a ring for a loss, half of each for a draw.
    static func mark(_ result: SavedGame.Result) -> String {
        switch result {
        case .win: return "circle.fill"
        case .loss: return "circle"
        case .draw: return "circle.lefthalf.filled"
        case .unfinished: return "circle.dotted"
        }
    }

    private func spoken(_ row: HomeGameRow) -> String {
        let game = row.game
        let outcome: String
        switch game.result {
        case .win: outcome = "you won"
        case .loss: outcome = "you lost"
        case .draw: outcome = "a draw"
        case .unfinished: outcome = "unfinished"
        }
        var parts = ["\(row.day), against \(game.opponent), \(outcome)"]
        if let accuracy = game.accuracy { parts.append("accuracy \(accuracy) percent") }
        if row.toFix > 0 { parts.append(row.toFix == 1 ? "1 move to fix" : "\(row.toFix) moves to fix") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Friends

/// Games with friends (filled in by the challenge feature) and the way to start one.
struct HomeFriendsCard: View {
    let tone: HomeTone
    let games: AnyView
    let challenge: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            games
            HomeLinkRow(glyph: "plus", title: "Challenge a friend", detail: "Send a game by text or email",
                        tone: tone, action: challenge)
        }
        .padding(.horizontal, 14)
        .homePane(RoundedRectangle(cornerRadius: 28, style: .continuous), tone: tone)
    }
}

// MARK: - The rest

/// The rest of the app, at the foot of the page: Analyze, your pieces and Settings.
struct HomeMoreCard: View {
    let tone: HomeTone
    let piecesLine: String
    let actions: HomeActions

    var body: some View {
        VStack(spacing: 0) {
            HomeLinkRow(glyph: Glyphs.analyze, title: "Analyze a position", detail: "Photo, screenshot or set it up",
                        tone: tone, action: actions.analyze)
            HomeHairline(tone: tone, inset: 46)
            HomeLinkRow(glyph: Glyphs.army, title: "Your pieces", detail: piecesLine, tone: tone, action: actions.army)
            HomeHairline(tone: tone, inset: 46)
            HomeLinkRow(glyph: Glyphs.settings, title: "Settings", detail: "Board look, sound, hints",
                        tone: tone, action: actions.settings)
            if let premium = actions.premium {
                HomeHairline(tone: tone, inset: 46)
                HomeLinkRow(glyph: "crown", title: "Chess Game Killer Pro", detail: "Everything, with no limits",
                            tone: tone, action: premium)
            }
        }
        .padding(.horizontal, 14)
        .homePane(RoundedRectangle(cornerRadius: 28, style: .continuous), tone: tone)
    }
}
