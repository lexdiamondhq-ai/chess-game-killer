import ChessKit
import SwiftUI

/// The Aurora home (Alex's pick, 2026-11-07: "Spotlight" with "Bento" tiles). Your game is the
/// hero: a clean flat board (the Gilded board with the app's cut-out pieces) under one serif
/// line and a gold button; swipe sideways to your other games, the next one peeking at the
/// right. Under it, tiles for your rating, streak, Today's Move, Coach Leo, Analyze and the
/// masterpiece. The room is deep ink with a soft violet, rose and gold glow and fine gold
/// engraved rings, or ivory by day. A glass tab bar with the gold knight beside it.
struct HomeAuroraInfo {
    var stage: HomeStageInfo
    /// Every game still going, your move first. Empty when none is.
    var games: [HomeCurrentGame]
    /// The 3D board turning at the top: its look and the game's pieces.
    var look: SculptedLook
    var pieces: [Piece]
}

struct HomeAuroraActions {
    var stage: HomeStageActions
    /// Opens one of your games.
    var open: (HomeCurrentGame) -> Void
}

/// Aurora's colors, night and day.
struct HomeAuroraPalette {
    let dark: Bool

    var bg: Color { dark ? Color(hex: 0x08080C) : Color(hex: 0xF6F3EE) }
    var bgLow: Color { dark ? Color(hex: 0x0C0B10) : Color(hex: 0xEFEAE2) }
    var ink: Color { dark ? Color(hex: 0xF2EEE6) : Color(hex: 0x1C1813) }
    var ink2: Color { ink.opacity(dark ? 0.62 : 0.6) }
    var ink3: Color { ink.opacity(dark ? 0.36 : 0.38) }
    var line: Color { dark ? Color.white.opacity(0.08) : Color(hex: 0x1C1813).opacity(0.08) }
    var glass: Color { dark ? Color.white.opacity(0.06) : Color.white.opacity(0.72) }
    var glassHi: Color { dark ? Color.white.opacity(0.12) : Color.white }
    var card: Color { dark ? Color(hex: 0x15171F) : Color.white }
    /// The page that slides up over the board.
    var sheet: Color { dark ? Color(hex: 0x0C0D12).opacity(0.97) : Color(hex: 0xF8F5F0).opacity(0.98) }
    var gold: Color { dark ? Color(hex: 0xE8C27A) : Color(hex: 0xB7832E) }
    var rose: Color { dark ? Color(hex: 0xF0708A) : Color(hex: 0xD9466A) }
    var violet: Color { dark ? Color(hex: 0x8B6CFF) : Color(hex: 0x6A4BE0) }
    var teal: Color { dark ? Color(hex: 0x3FD1B8) : Color(hex: 0x169C86) }
    var shadow: Color { .black.opacity(dark ? 0.45 : 0.12) }
    var glow: Double { dark ? 1 : 0.5 }

    static let goldButton = LinearGradient(colors: [Color(hex: 0xF6DEA3), Color(hex: 0xC99B4E)],
                                           startPoint: .top, endPoint: .bottom)
    static let roseTile = LinearGradient(colors: [Color(hex: 0xFFB86B), Color(hex: 0xF0708A)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let violetTile = LinearGradient(colors: [Color(hex: 0x8B6CFF), Color(hex: 0x4C8DFF)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
    static let tealTile = LinearGradient(colors: [Color(hex: 0x3FD1B8), Color(hex: 0x2E8C9E)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let goldTile = LinearGradient(colors: [Color(hex: 0xE8C27A), Color(hex: 0xB0763A)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct HomeAuroraView: View {
    let tone: HomeTone
    let info: HomeAuroraInfo
    let actions: HomeAuroraActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("haptics") private var hapticsOn = true
    @AppStorage(HomeToneMode.key) private var toneMode = HomeToneMode.defaultMode
    @State private var music = HomeMusic.shared
    @State private var boardStage = SculptedStage()
    /// How far the page has been pulled up over the board, in points.
    @State private var pulled: CGFloat = 0

    private var palette: HomeAuroraPalette { HomeAuroraPalette(dark: tone.scheme == .dark) }
    private var stage: HomeStageInfo { info.stage }

    /// Your games, or the next game when none is going.
    private var cards: [HomeAuroraGameCard] {
        if info.games.isEmpty {
            return [HomeAuroraGameCard.next(stage.upNext, fen: stage.gameFEN)]
        }
        return info.games.map(HomeAuroraGameCard.init)
    }

    var body: some View {
        GeometryReader { geo in
            let boardHeight: CGFloat = max(300, geo.size.height * 0.46)
            let lift: CGFloat = min(max(pulled / boardHeight, 0), 1)
            ZStack(alignment: .top) {
                HomeAuroraBackdrop(palette: palette)
                spinningBoard(height: boardHeight + geo.safeAreaInsets.top, lift: lift)
                    .ignoresSafeArea(edges: .top)
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        // The board shows through here; a tap on it plays.
                        Color.clear
                            .frame(height: boardHeight - 70)
                            .contentShape(Rectangle())
                            .onTapGesture { actions.stage.play() }
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                -proxy.frame(in: .scrollView).minY
                            } action: { value in
                                pulled = value
                            }
                        page
                    }
                }
                .scrollIndicators(.hidden)
                header
                    .background(alignment: .top) {
                        // The header gets a soft backing once the page covers the board.
                        LinearGradient(colors: [palette.bg, palette.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 120)
                            .opacity(Double(lift))
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                    }
                VStack {
                    Spacer()
                    HomeAuroraTabBar(palette: palette, play: { actions.stage.play() }, learn: actions.stage.learn,
                                     you: actions.stage.you, rooms: actions.stage.rooms)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .environment(\.colorScheme, tone.scheme)
        .onAppear { music.homeAppeared() }
        .onDisappear { music.homeDisappeared() }
    }

    // MARK: The board

    /// The game's own 3D board turning slowly in the light; it sinks back and dims as the page
    /// comes up over it.
    private func spinningBoard(height: CGFloat, lift: CGFloat) -> some View {
        let upNext: HomeUpNext = stage.upNext
        return ZStack {
            if SculptedAssets.shared.isLoaded {
                HomeStageBoard(stage: boardStage, look: info.look, pieces: info.pieces,
                               black: upNext.playerColor == .black, light: upNext.rival.lightUI,
                               leaning: upNext.inProgress && upNext.yourMove, plinth: nil,
                               still: reduceMotion, dive: 0)
                    .id(info.look.name)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .scaleEffect(1 - 0.1 * lift, anchor: .top)
        .opacity(1 - 0.55 * Double(lift))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            (Text("Beauty ") + Text("of").italic().foregroundColor(palette.gold) + Text(" Chess"))
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if music.available {
                circle(label: music.on ? "Music off" : "Music on", action: music.toggle) {
                    HomeMusicBars(on: music.on, gold: palette.gold, off: palette.ink3)
                }
            }
            circle(label: palette.dark ? "Light mode" : "Dark mode", action: flipLight) {
                Image(systemName: palette.dark ? "sun.max" : "moon")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.gold)
            }
            circle(label: "You", action: actions.stage.you) {
                Image(systemName: "crown")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.gold)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func circle<Label: View>(label: String, action: @escaping () -> Void,
                                     @ViewBuilder content: () -> Label) -> some View {
        Button(action: action) {
            content()
                .frame(width: 36, height: 36)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(palette.line, lineWidth: 1))
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel(label)
    }

    private func flipLight() {
        withAnimation(.easeInOut(duration: 0.4)) {
            toneMode = palette.dark ? .light : .dark
        }
    }

    // MARK: The page

    /// The page that slides up over the board: your games first, then a slim line of numbers,
    /// then today's things as long rows.
    private var page: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 34, bottomLeading: 0,
                                                              bottomTrailing: 0, topTrailing: 34),
                                           style: .continuous)
        return VStack(spacing: 0) {
            Capsule()
                .fill(palette.ink3)
                .frame(width: 38, height: 4)
                .padding(.top, 10)
            HomeAuroraSection(title: gamesTitle, palette: palette, note: gamesNote)
            gameRow
            numbers
                .padding(.horizontal, 20)
                .padding(.top, 22)
            HomeAuroraSection(title: "For today", palette: palette, note: nil)
            VStack(spacing: 10) {
                todayRows
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 130)
        .frame(maxWidth: .infinity)
        .background {
            shape.fill(palette.sheet)
                .overlay(alignment: .top) {
                    // A fine gold edge along the top of the page.
                    shape.strokeBorder(LinearGradient(colors: [palette.gold.opacity(0.5), palette.gold.opacity(0)],
                                                      startPoint: .top, endPoint: .center), lineWidth: 1)
                }
                .shadow(color: .black.opacity(palette.dark ? 0.5 : 0.1), radius: 30, y: -10)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var gamesTitle: String {
        if info.games.isEmpty { return "Next game" }
        return info.games.count == 1 ? "Your game" : "Your games"
    }

    private var gamesNote: String? {
        let yours: Int = info.games.filter(\.isYourMove).count
        guard !info.games.isEmpty else { return nil }
        return yours == 0 ? "Waiting on them" : (yours == 1 ? "1 needs you" : "\(yours) need you")
    }

    /// Your games as wide cards, the next one peeking in at the right.
    private var gameRow: some View {
        let all: [HomeAuroraGameCard] = cards
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(all) { card in
                    HomeAuroraGameTile(card: card, palette: palette) { open(card) }
                        .containerRelativeFrame(.horizontal) { width, _ in
                            all.count > 1 ? width - 72 : width - 32
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    /// Rating, level and streak in one slim engraved line.
    private var numbers: some View {
        HStack(spacing: 0) {
            number(stage.rating.map { $0.formatted(.number) } ?? "New", label: "Rating", action: actions.stage.you)
            hairline
            number("\(stage.rankNumber)", label: "Level", action: actions.stage.learn)
            hairline
            number("\(stage.day.streak)", label: "Day streak",
                   action: actions.stage.dailyMove)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { palette.line.frame(height: 1) }
        .overlay(alignment: .bottom) { palette.line.frame(height: 1) }
    }

    private var hairline: some View {
        LinearGradient(colors: [palette.gold.opacity(0), palette.gold.opacity(0.5), palette.gold.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: 1, height: 40)
    }

    private func number(_ value: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(palette.ink)
                    .monospacedDigit()
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(palette.ink2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(HomeStagePress())
    }

    @ViewBuilder
    private var todayRows: some View {
        HomeAuroraRow(eyebrow: "Today's Move", title: todayTitle, detail: todayDetail,
                      accent: palette.violet, palette: palette, action: actions.stage.dailyMove) {
            HomeAuroraBoard(fen: stage.todayFEN, flipped: stage.todaySolver == .black, lit: false)
        }
        HomeAuroraRow(eyebrow: "Coach Leo", title: stage.plan?.title ?? "Today's lesson", detail: coachLine,
                      accent: palette.teal, palette: palette, action: actions.stage.coach) {
            HomeAuroraEmblem(glyph: Glyphs.coach, fill: HomeAuroraPalette.tealTile)
        }
        HomeAuroraRow(eyebrow: "Analyze", title: "Any position", detail: "A photo, a screenshot or a board you set up",
                      accent: palette.gold, palette: palette, action: actions.stage.analyze) {
            HomeAuroraEmblem(glyph: Glyphs.analyze, fill: HomeAuroraPalette.goldTile)
        }
        if let masterpiece = stage.masterpiece {
            HomeAuroraRow(eyebrow: "Masterpiece of the day", title: masterpiece.title, detail: masterpiece.players,
                          accent: palette.rose, palette: palette, action: {
                              if let fen = masterpiece.frames.first { actions.stage.analyzePosition(fen) }
                          }) {
                HomeAuroraBoard(fen: masterpiece.frames.first, flipped: masterpiece.flipped, lit: false)
            }
        }
    }

    private var todayTitle: String {
        if stage.day.found { return "Found it" }
        return stage.todaySolver == .black ? "Black to play and win" : "White to play and win"
    }

    private var todayDetail: String {
        if stage.day.played { return "Back tomorrow for the next one" }
        let streak: Int = stage.day.streak
        return streak > 0 ? "Keep your \(streak)-day streak" : "One puzzle, the same for everyone"
    }

    private var coachLine: String {
        if stage.trainedToday { return "Done today. Another round?" }
        guard let plan = stage.plan else { return "Pick up where you stopped" }
        return "\(plan.minutes) min with Leo"
    }

    private func open(_ card: HomeAuroraGameCard) {
        if let game = card.game {
            actions.open(game)
        } else {
            actions.stage.play()
        }
    }
}

/// One of your games as a wide card: its board on the left, who and where on the right.
struct HomeAuroraGameTile: View {
    let card: HomeAuroraGameCard
    let palette: HomeAuroraPalette
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        Button(action: action) {
            HStack(spacing: 14) {
                HomeAuroraBoard(fen: card.fen, flipped: card.flipped, lit: card.yourMove)
                    .frame(width: 104, height: 104)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(card.yourMove ? palette.teal : palette.ink3)
                            .frame(width: 6, height: 6)
                        Text(card.status.uppercased())
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(card.yourMove ? palette.teal : palette.ink2)
                    }
                    Text(card.title)
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(card.tags.joined(separator: " · "))
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.ink2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Text(card.button)
                            .font(.system(size: 13, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(card.yourMove ? Color(hex: 0x2A1E0F) : palette.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background {
                        if card.yourMove {
                            Capsule().fill(HomeAuroraPalette.goldButton)
                        } else {
                            Capsule().strokeBorder(palette.line, lineWidth: 1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(height: 128)
            .background(shape.fill(palette.card))
            .overlay(shape.strokeBorder(card.yourMove ? palette.gold.opacity(0.4) : palette.line, lineWidth: 1))
        }
        .buttonStyle(HomeStagePress())
        .accessibilityElement(children: .combine)
    }
}

/// A long row for one of today's things: a thin color edge, small caps, a serif title, a line,
/// and a picture at the right.
struct HomeAuroraRow<Picture: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    let accent: Color
    let palette: HomeAuroraPalette
    let action: () -> Void
    @ViewBuilder let picture: () -> Picture

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            HStack(spacing: 14) {
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3)
                    .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.system(size: 19, weight: .regular, design: .serif))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                picture()
                    .frame(width: 64, height: 64)
            }
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity)
            .background(shape.fill(palette.card))
            .overlay(shape.strokeBorder(palette.line, lineWidth: 1))
        }
        .buttonStyle(HomeStagePress())
        .accessibilityElement(children: .combine)
    }
}

/// A square of color with one of the app's glyphs, for a row without a board.
struct HomeAuroraEmblem: View {
    let glyph: String
    let fill: LinearGradient

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(fill)
            .overlay {
                Glyph(name: glyph, size: 30, weight: .bold)
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)
    }
}

/// One board in the swipe row, and the words around it while it's in front.
struct HomeAuroraGameCard: Identifiable, Equatable {
    let id: String
    let game: HomeCurrentGame?
    let title: String
    let fen: String?
    let flipped: Bool
    let yourMove: Bool
    let eyebrow: String
    /// "Your move", "Their move", "Up next".
    let status: String
    let headline: String
    let headlineEnd: String
    let button: String
    let tags: [String]

    init(_ game: HomeCurrentGame) {
        let name: String = game.title.hasPrefix("vs ") ? String(game.title.dropFirst(3)) : game.title
        let parts: [String] = game.detail.components(separatedBy: " · ")
        id = game.id
        self.game = game
        title = game.title
        fen = game.fen
        flipped = game.flipped
        yourMove = game.isYourMove
        eyebrow = parts.last.map { "\(game.status.words) · \($0)" } ?? game.status.words
        status = game.status.words
        switch game.status {
        case .yourMove:
            headline = "\(name) is waiting\nfor "
            headlineEnd = "you"
            button = "Make your move"
        case .theirMove:
            headline = "\(name) is "
            headlineEnd = "thinking"
            button = "See the game"
        case .waiting:
            headline = "Waiting for "
            headlineEnd = "\(name)"
            button = "See the game"
        }
        var shown: [String] = Array(parts.dropLast())
        shown.append(game.flipped ? "You're Black" : "You're White")
        tags = shown
    }

    private init(next upNext: HomeUpNext, fen: String) {
        id = "next"
        game = nil
        title = "Play \(upNext.rival.name)"
        self.fen = fen
        flipped = upNext.playerColor == .black
        yourMove = false
        eyebrow = "Your next game"
        status = "Up next"
        headline = "\(upNext.rival.name) is ready\nwhen "
        headlineEnd = "you are"
        button = "Play \(upNext.rival.name)"
        tags = [upNext.timeControl.isTimed ? upNext.timeControl.name : "No clock"]
    }

    static func next(_ upNext: HomeUpNext, fen: String) -> HomeAuroraGameCard {
        HomeAuroraGameCard(next: upNext, fen: fen)
    }
}

// MARK: - The board

/// A position on the Gilded board with the app's flat cut-out pieces, each with its soft
/// shadow: the same pieces as the game's Flat view, clean and sharp at any size.
struct HomeAuroraBoard: View {
    let fen: String?
    let flipped: Bool
    /// Your move: a fine gold rim.
    let lit: Bool

    /// The board picture's frame, as a share of its side.
    private static let inset: CGFloat = 0.046
    private static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"

    private struct Placed: Identifiable {
        let id: Int
        let letter: Character
        let column: Int
        let row: Int
    }

    private var placed: [Placed] {
        let placement: String = (fen ?? Self.start).split(separator: " ").first.map(String.init) ?? Self.start
        var out: [Placed] = []
        var row: Int = 0
        var column: Int = 0
        for ch in placement {
            if ch == "/" {
                row += 1
                column = 0
            } else if let skip = ch.wholeNumberValue {
                column += skip
            } else {
                let c: Int = flipped ? 7 - column : column
                let r: Int = flipped ? 7 - row : row
                out.append(Placed(id: out.count, letter: ch, column: c, row: r))
                column += 1
            }
        }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height)
            let margin: CGFloat = side * Self.inset
            let square: CGFloat = (side - 2 * margin) / 8
            let pieces: [Placed] = placed
            ZStack(alignment: .topLeading) {
                Image("board-gilded")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                ForEach(pieces) { piece in
                    Image(Self.shadowName(piece.letter))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: square, height: square)
                        .opacity(0.32)
                        .offset(x: margin + CGFloat(piece.column) * square + square * 0.075,
                                y: margin + CGFloat(piece.row) * square + square * 0.1)
                }
                ForEach(pieces) { piece in
                    Image(Self.pictureName(piece.letter))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: square * 0.92, height: square * 0.92)
                        .offset(x: margin + CGFloat(piece.column) * square + square * 0.04,
                                y: margin + CGFloat(piece.row) * square + square * 0.04)
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(hex: 0xE8C27A).opacity(lit ? 0.55 : 0), lineWidth: 1)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private static func pictureName(_ letter: Character) -> String {
        let side: String = letter.isUppercase ? "w" : "b"
        return "cutout-\(side)\(String(letter).uppercased())"
    }

    private static func shadowName(_ letter: Character) -> String {
        "cutout-shadow-\(String(letter).uppercased())"
    }
}

// MARK: - Pieces of the page

struct HomeAuroraSection: View {
    let title: String
    let palette: HomeAuroraPalette
    var note: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(palette.ink)
            Spacer()
            if let note {
                Text(note)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One Bento tile: plain card or a color gradient, a small caps label, and what's in it.
struct HomeAuroraTile<Content: View>: View {
    let eyebrow: String
    let palette: HomeAuroraPalette
    let fill: LinearGradient?
    var mark: String? = nil
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.3)
                    .opacity(fill == nil ? 1 : 0.85)
                    .foregroundStyle(fill == nil ? palette.ink2 : Color.white)
                content()
                Spacer(minLength: 0)
            }
            .foregroundStyle(fill == nil ? palette.ink : Color.white)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(alignment: .bottomTrailing) {
                if let mark {
                    Glyph(name: mark, size: 86, weight: .bold)
                        .foregroundStyle(Color.white.opacity(0.22))
                        .offset(x: 14, y: 14)
                }
            }
            .background {
                if let fill {
                    shape.fill(fill)
                } else {
                    shape.fill(palette.card)
                        .overlay(shape.strokeBorder(palette.line, lineWidth: 1))
                }
            }
            .clipShape(shape)
        }
        .buttonStyle(HomeStagePress())
    }
}

/// The room: deep ink (ivory by day) with a soft violet, rose and gold glow at the top and fine
/// gold rings engraved around where the board sits, like a watch dial.
struct HomeAuroraBackdrop: View {
    let palette: HomeAuroraPalette

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            ZStack(alignment: .top) {
                LinearGradient(colors: [palette.bg, palette.bgLow], startPoint: .top, endPoint: .bottom)
                glow(Color(hex: 0x8B6CFF), opacity: 0.42, at: CGPoint(x: w * 0.12, y: 40), size: w * 1.0)
                glow(Color(hex: 0xF0708A), opacity: 0.34, at: CGPoint(x: w * 0.92, y: 20), size: w * 0.9)
                glow(Color(hex: 0xE8C27A), opacity: 0.26, at: CGPoint(x: w * 0.5, y: 330), size: w * 1.2)
                HomeAuroraRings(color: palette.gold, opacity: palette.dark ? 0.07 : 0.1)
                    .frame(width: w * 1.6, height: w * 1.6)
                    .position(x: w / 2, y: 330)
                    .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, opacity: Double, at point: CGPoint, size: CGFloat) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [color.opacity(opacity * palette.glow), color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size * 0.8)
            .position(point)
    }
}

/// Fine engraved rings: circles in step, crossed by a slow rosette of offset circles.
struct HomeAuroraRings: View {
    let color: Color
    let opacity: Double

    var body: some View {
        Canvas { gc, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer: CGFloat = min(size.width, size.height) / 2
            let style = GraphicsContext.Shading.color(color.opacity(opacity))
            for i in 1...22 {
                let r: CGFloat = outer * CGFloat(i) / 22
                gc.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                          with: style, lineWidth: 0.5)
            }
            let petals: Int = 36
            let r: CGFloat = outer * 0.42
            for i in 0..<petals {
                let angle: Double = Double(i) / Double(petals) * 2 * Double.pi
                let cx: CGFloat = center.x + CGFloat(cos(angle)) * outer * 0.2
                let cy: CGFloat = center.y + CGFloat(sin(angle)) * outer * 0.2
                gc.stroke(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)),
                          with: style, lineWidth: 0.4)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A glass tab bar (Today, Learn, You, Rooms) with the gold knight as its own round button.
struct HomeAuroraTabBar: View {
    let palette: HomeAuroraPalette
    let play: () -> Void
    let learn: () -> Void
    let you: () -> Void
    let rooms: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                tab("Today", glyph: Glyphs.today, on: true) {}
                tab("Learn", glyph: Glyphs.coach, on: false, action: learn)
                tab("You", glyph: Glyphs.king, on: false, action: you)
                tab("Rooms", glyph: Glyphs.home, on: false, action: rooms)
            }
            .padding(.horizontal, 6)
            .frame(height: 64)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(palette.dark ? Color(hex: 0x14161E).opacity(0.55) : Color.white.opacity(0.6)))
                    .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
                    .shadow(color: palette.shadow, radius: 18, y: 12)
            }
            Button(action: play) {
                Glyph(name: Glyphs.train, size: 32, weight: .bold)
                    .foregroundStyle(Color(hex: 0x2A1C08))
                    .frame(width: 64, height: 64)
                    .background {
                        Circle().fill(RadialGradient(stops: [.init(color: Color(hex: 0xFFF1CC), location: 0),
                                                             .init(color: Color(hex: 0xE8C27A), location: 0.45),
                                                             .init(color: Color(hex: 0xA66F25), location: 1)],
                                                     center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: 40))
                    }
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Color(hex: 0xE8C27A).opacity(0.45), radius: 15, y: 12)
            }
            .buttonStyle(HomeStagePress())
            .accessibilityLabel("Play")
        }
    }

    private func tab(_ title: String, glyph: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Glyph(name: glyph, size: 22, weight: .semibold)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(on ? palette.ink : palette.ink3)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(on ? palette.glassHi : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
