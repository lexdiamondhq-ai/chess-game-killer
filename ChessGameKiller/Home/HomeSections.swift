import ChessKit
import SwiftUI

// The cards below the clock: today's puzzle and session, the ladder of rivals, and the
// scoresheet of your games.

// MARK: - Today

/// A real puzzle printed as a diagram, the way a chess column prints one, and today's
/// session with Coach Leo. Solve opens Puzzles on this very puzzle; Start starts the session.
struct HomeTodayCard: View {
    let puzzle: HomePuzzle?
    let rating: Int
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
        .padding(HomeMetrics.inset)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous), tone: tone)
    }

    // MARK: The puzzle

    @ViewBuilder
    private var puzzleBlock: some View {
        if let puzzle, let draft = PositionDraft(fen: puzzle.fen) {
            Button(action: solve) {
                HomeDiagram(draft: draft, flipped: puzzle.solver == .black, theme: pieceTheme, tone: tone)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .padding(.bottom, 16)
            label("Puzzle rated \(puzzle.puzzle.rating)")
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

    /// Your puzzle rating, said as such: the ladder shows your level in games.
    /// Chess ratings are written without a thousands separator.
    private var ratingLine: String { "Your puzzle rating \(rating)" }

    /// A block's small name, over its title.
    private func label(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tone.ink2)
    }

    // MARK: Coach Leo

    @ViewBuilder
    private var coachBlock: some View {
        label("Today with Coach Leo")
        if trainedToday {
            // Done: said once, with a quiet way to go on.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Done for today.")
                    .font(HomeType.title)
                    .foregroundStyle(tone.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: train) {
                    HStack(spacing: 3) {
                        Text("Train more")
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone.metal)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens training")
            }
            .padding(.top, 2)
        } else {
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
                if let plan {
                    Button("Start") { startSession(plan) }
                        .buttonStyle(HomeGlassButtonStyle(tone: tone, compact: true))
                        .accessibilityLabel("Start today's session: \(coachTitle)")
                } else {
                    Button("Train", action: train)
                        .buttonStyle(HomeGlassButtonStyle(tone: tone, compact: true))
                        .accessibilityLabel("Open training")
                }
            }
            .padding(.top, 4)
        }
    }

    private var coachTitle: String {
        guard let plan else { return "Lessons and drills" }
        return "\(plan.focus?.title ?? plan.headline ?? "Today's session") · \(plan.minutes) min"
    }

    private var coachDetail: String {
        guard let plan else { return "Short lessons, then positions picked for you." }
        let count = plan.items.count
        let positions = count == 1 ? "1 position" : "\(count) positions"
        let shape = plan.lesson == nil ? "\(positions), picked for you." : "A short lesson, then \(positions)."
        if let blurb = plan.focus?.blurb { return "\(blurb) \(shape)" }
        // Past the course: why today's puzzles, like "Your games say: shaky starts."
        if plan.focus == nil, let reason = plan.reason { return reason }
        return shape
    }
}

/// A position printed the way a chess column prints it: flat squares in the board look's
/// two colors, the pieces, a fine rule round the edge and the coordinates outside it. It is
/// a picture of a position, so it stays quiet beside the real board behind the page.
struct HomeDiagram: View {
    let draft: PositionDraft
    /// Black at the bottom, for a puzzle Black solves.
    let flipped: Bool
    let theme: BoardTheme
    let tone: HomeTone

    @ScaledMetric(relativeTo: .caption2) private var labelSize: CGFloat = 11

    var body: some View {
        GeometryReader { geo in
            let margin = labelSize + 5
            let side = max(min(geo.size.width, geo.size.height) - margin, 8)
            let square = side / 8
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    VStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { row in
                            coordinate("\(flipped ? row + 1 : 8 - row)")
                                .frame(width: labelSize, height: square)
                        }
                    }
                    board(square: square)
                        .frame(width: side, height: side)
                }
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        coordinate(Self.files[flipped ? 7 - column : column])
                            .frame(width: square, height: labelSize)
                    }
                }
                .padding(.leading, margin)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
    }

    private static let files = ["a", "b", "c", "d", "e", "f", "g", "h"]

    private func coordinate(_ text: String) -> some View {
        Text(text)
            .font(.system(size: labelSize, weight: .medium))
            .foregroundStyle(tone.ink3)
    }

    private func board(square: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { column in
                        let at = flipped ? Square(file: 7 - column, rank: row) : Square(file: column, rank: 7 - row)
                        ZStack {
                            Rectangle().fill((at.fileIndex + at.rankIndex) % 2 == 1 ? theme.light : theme.dark)
                            if let token = draft[at] {
                                PieceImage(piece: token.piece(at: at), theme: theme, size: square)
                            }
                        }
                        .frame(width: square, height: square)
                    }
                }
            }
        }
        .overlay { Rectangle().strokeBorder(tone.ink.opacity(0.35), lineWidth: 0.5) }
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
    @Environment(\.dynamicTypeSize) private var typeSize

    /// At the accessibility text sizes a rung puts the score under the name.
    private var large: Bool { typeSize.isAccessibilitySize }
    /// The portrait grows with the text, but stops where it would squeeze the name.
    private var face: CGFloat { min(portrait, 52) }

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
                    HomeHairline(tone: tone, inset: face + 12)
                }
                switch entry {
                case .rung(let rung): rungRow(rung)
                case .you(let rating): youRow(rating)
                }
            }
        }
        .padding(.horizontal, HomeMetrics.inset)
        .padding(.vertical, 4)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous), tone: tone)
    }

    private func rungRow(_ rung: HomeLadder.Rung) -> some View {
        let rival = rung.level.rival
        let isNext = ladder.nextToBeat == rung.level
        return Button {
            play(rung.level)
        } label: {
            HStack(spacing: 12) {
                HomeRivalPortrait(rival: rival, tone: tone, size: face)
                VStack(alignment: .leading, spacing: 2) {
                    let nameLayout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                                           : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                    nameLayout {
                        Text(rival.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(tone.ink)
                            .minimumScaleFactor(0.7)
                        Text(rival.elo)
                            .font(.subheadline)
                            .foregroundStyle(tone.ink2)
                    }
                    Text(isNext ? "Next to beat · \(rung.level.tagline)" : rung.level.tagline)
                        .font(.footnote)
                        .foregroundStyle(isNext ? tone.metal : tone.ink2)
                    if large {
                        score(rung)
                    }
                }
                .lineLimit(large ? 2 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !large {
                    VStack(alignment: .trailing, spacing: 2) {
                        score(rung)
                    }
                    .lineLimit(1)
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeRowPressStyle(tone: tone))
        .background {
            if isNext {
                RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous)
                    .fill(tone.metal.opacity(0.09))
                    .padding(.horizontal, -8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(rung, isNext: isNext))
        .accessibilityHint("Sets up a game against \(rival.name)")
        .accessibilityAddTraits(.isButton)
    }

    /// The match score and where you stand: "3½–1½", "You lead".
    @ViewBuilder
    private func score(_ rung: HomeLadder.Rung) -> some View {
        Text(rung.score ?? "–")
            .font(HomeType.score)
            .monospacedDigit()
            .foregroundStyle(rung.played == 0 ? tone.ink3 : tone.ink)
        Text(rung.standingText)
            .font(.caption)
            .foregroundStyle(tone.ink3)
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
            PieceImage(piece: Piece(.king, color: youColor, square: youColor == .white ? .e1 : .e8),
                       theme: pieceTheme, size: face)
                .frame(width: face, height: face)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("You")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tone.ink)
                    Text(verbatim: "~\(rating)")
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

/// A rival's portrait, printed in the page's ivory rather than its own neon, so the ladder
/// keeps one palette while every rival keeps the face it has across the app.
struct HomeRivalPortrait: View {
    let rival: Rival
    let tone: HomeTone
    let size: CGFloat

    var body: some View {
        Image(rival.portraitName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            // A little closer in, so the rival's shape fills the small circle.
            .scaleEffect(1.2)
            .grayscale(1)
            .colorMultiply(tone.ivory)
            .contrast(1.3)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(tone.ink.opacity(0.18), lineWidth: 0.5) }
            .accessibilityHidden(true)
    }
}

// MARK: - Your games

/// Your last games as a tournament scoresheet: the day, the rival, the result as a score
/// sheet writes it (1, ½, 0), your accuracy and the moves left to fix. A row opens that game in Rewind.
struct HomeScoresheet: View {
    let rows: [HomeGameRow]
    let total: Int
    let tone: HomeTone
    let open: (SavedGame) -> Void
    let openAll: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var dayWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .subheadline) private var resultWidth: CGFloat = 50
    @ScaledMetric(relativeTo: .subheadline) private var accuracyWidth: CGFloat = 74
    @ScaledMetric(relativeTo: .subheadline) private var fixWidth: CGFloat = 46

    /// The width inside the card, measured, so the columns are used only where they fit.
    @State private var width: CGFloat = 338

    /// Date, result, accuracy and moves to fix at their size, the gaps between the five
    /// columns, and room for a rival's name.
    private var columnsNeed: CGFloat { dayWidth + resultWidth + accuracyWidth + fixWidth + 4 * 8 + 80 }

    /// Columns while they fit; at large text sizes or on a narrow phone each game takes two lines instead.
    private var columns: Bool { typeSize <= .xLarge && width >= columnsNeed }

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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { measured in
            width = measured
        }
        .padding(.horizontal, HomeMetrics.inset)
        .padding(.top, 2)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous), tone: tone)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Date").frame(width: dayWidth, alignment: .leading)
            Text("Rival").frame(maxWidth: .infinity, alignment: .leading)
            Text("Result").frame(width: resultWidth, alignment: .center)
            Text("Accuracy").frame(width: accuracyWidth, alignment: .trailing)
            Text("To fix").frame(width: fixWidth, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .tracking(0.5)
        .lineLimit(1)
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
                    .minimumScaleFactor(0.85)
                    .frame(width: dayWidth, alignment: .leading)
                Text(row.game.opponent)
                    .foregroundStyle(tone.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                result(row.game.result)
                    .frame(width: resultWidth, alignment: .center)
                Text(row.game.accuracy.map { "\($0)%" } ?? "–")
                    .monospacedDigit()
                    .foregroundStyle(tone.ink)
                    .frame(width: accuracyWidth, alignment: .trailing)
                fix(row, words: false)
                    .frame(width: fixWidth, alignment: .trailing)
            }
            .font(.subheadline)
            .lineLimit(1)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.game.opponent)
                        .foregroundStyle(tone.ink)
                    Spacer(minLength: 8)
                    result(row.game.result)
                }
                HStack(spacing: 8) {
                    Text(row.day)
                    Text(row.game.accuracy.map { "\($0)% accuracy" } ?? "No accuracy")
                    Spacer(minLength: 8)
                    fix(row, words: true)
                }
                .foregroundStyle(tone.ink2)
            }
            .font(.subheadline)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    /// The result as a scoresheet writes it: 1 for a win, ½ for a draw, 0 for a loss.
    private func result(_ result: SavedGame.Result) -> some View {
        Text(Self.score(result))
            .font(HomeType.score)
            .foregroundStyle(result == .win ? tone.ink : (result == .draw ? tone.ink2 : tone.ink3))
    }

    static func score(_ result: SavedGame.Result) -> String {
        switch result {
        case .win: return "1"
        case .draw: return "½"
        case .loss: return "0"
        case .unfinished: return "–"
        }
    }

    /// The moves left to fix in Rewind: a plain count in the column, words on two lines.
    private func fix(_ row: HomeGameRow, words: Bool) -> some View {
        let text: String
        if row.toFix == 0 {
            text = words ? "" : "–"
        } else {
            text = words ? "\(row.toFix) to fix" : "\(row.toFix)"
        }
        return Text(text)
            .monospacedDigit()
            .foregroundStyle(row.toFix > 0 ? tone.ink2 : tone.ink3)
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

/// Your games with friends still going, your move first, and the way to start one. A game
/// that has ended is kept with your games, so it shows on the scoresheet instead.
struct HomeFriendsCard: View {
    let games: [FriendGame]
    let tone: HomeTone
    let open: (FriendGame) -> Void
    let challenge: () -> Void

    @State private var showsAll = false

    /// How many games show before "Show all".
    static let limit = 3

    var body: some View {
        let shown = showsAll ? games : Array(games.prefix(Self.limit))
        VStack(spacing: 0) {
            ForEach(shown, id: \.code) { game in
                row(game)
                HomeHairline(tone: tone)
            }
            if games.count > Self.limit {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { showsAll.toggle() }
                } label: {
                    Text(showsAll ? "Show fewer" : "Show all \(games.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tone.metal)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomeRowPressStyle(tone: tone))
                HomeHairline(tone: tone)
            }
            HomeLinkRow(title: "Challenge a friend", detail: "Send a game by text or email",
                        tone: tone, action: challenge)
        }
        .padding(.horizontal, HomeMetrics.inset)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous), tone: tone)
    }

    /// The friend, whose move it is (in gold when it is yours), and the clock.
    private func row(_ game: FriendGame) -> some View {
        let clock = game.clock?.label ?? "No clock"
        return Button {
            open(game)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tone.ink)
                    Text(game.statusLine)
                        .font(.subheadline.weight(game.isYourMove ? .semibold : .regular))
                        .foregroundStyle(game.isYourMove ? tone.metal : tone.ink2)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(clock)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(tone.ink3)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tone.ink3)
            }
            .padding(.vertical, 13)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeRowPressStyle(tone: tone))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(game.title), \(game.statusLine), \(game.clock == nil ? "no clock" : clock)")
        .accessibilityAddTraits(.isButton)
    }
}
