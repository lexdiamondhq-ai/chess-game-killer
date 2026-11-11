import ChessKit
import SwiftUI

/// The Aurora home (Alex's pick, 2026-11-07: "Spotlight" with "Bento" tiles). Your game is the
/// hero: a clean flat board (the Gilded board with the app's cut-out pieces) under one serif
/// line and a gold button; swipe sideways to your other games, the next one peeking at the
/// right. Under it, rows for Today's Move, Puzzles, Coach Leo and the game of the day; Analyze
/// is the gold knight in the bar (one button for it, Alex 2026-11-08). The room is deep ink
/// with a soft violet, rose and gold glow and fine gold engraved rings, or ivory by day. A glass tab bar with the gold knight beside it.
struct HomeAuroraInfo {
    var stage: HomeStageInfo
    /// Every game still going, your move first. Empty when none is.
    var games: [HomeCurrentGame]
    /// The 3D board turning at the top: its look and the game's pieces.
    var look: SculptedLook
    var pieces: [Piece]
    /// Your finest move of the week, framed, when you played one.
    var finest: HomeFinestMove? = nil
    /// Your Chess DNA, once it has been read from your games.
    var dna: ChessDNA? = nil
}

struct HomeAuroraActions {
    var stage: HomeStageActions
    /// Opens one of your games.
    var open: (HomeCurrentGame) -> Void
    /// Starts a game against one of the five rivals.
    var playRival: (MatchController.Level) -> Void = { _ in }
    /// Opens the New Game sheet on this rival, for Options on a rival swiped to.
    var options: (MatchController.Level) -> Void = { _ in }
    /// Opens the rivals' hall, on this rival or on the one up next.
    var rivals: (MatchController.Level?) -> Void = { _ in }
    /// Opens your Chess DNA.
    var chessDNA: () -> Void = {}
    /// Opens Puzzles.
    var puzzles: () -> Void = {}
    /// Opens one of your finished games in Rewind.
    var replay: (UUID) -> Void = { _ in }
}

/// Aurora's colors, night and day.
struct HomeAuroraPalette {
    let dark: Bool

    // Dark is the warm espresso of the other dark screens (Alex, 2026-11-09): the page, the
    // cards and the sheet were a cool blue-black that only Home wore. The glows above are kept.
    var bg: Color { dark ? Color(hex: 0x100B08) : Color(hex: 0xF6F3EE) }
    var bgLow: Color { dark ? Color(hex: 0x140F0C) : Color(hex: 0xEFEAE2) }
    var ink: Color { dark ? Color(hex: 0xF2EEE6) : Color(hex: 0x1C1813) }
    var ink2: Color { ink.opacity(dark ? 0.62 : 0.6) }
    var ink3: Color { ink.opacity(dark ? 0.36 : 0.38) }
    var line: Color { dark ? Color.white.opacity(0.08) : Color(hex: 0x1C1813).opacity(0.08) }
    var glass: Color { dark ? Color.white.opacity(0.06) : Color.white.opacity(0.72) }
    var glassHi: Color { dark ? Color.white.opacity(0.12) : Color.white }
    var card: Color { dark ? Color(hex: 0x1D1814) : Color.white }
    /// The page that slides up over the board.
    var sheet: Color { dark ? Color(hex: 0x110C09).opacity(0.97) : Color(hex: 0xF8F5F0).opacity(0.98) }
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
    @State private var music = HomeMusic.shared
    @State private var boardStage = SculptedStage()
    /// How far the page has been pulled up over the board, in points.
    @State private var pulled: CGFloat = 0
    /// The header's height, so it knows when the page's top edge reaches it.
    @State private var headerHeight: CGFloat = 52
    /// Which position of the game of the day the turning board shows: it plays itself slowly.
    @State private var boardFrame = 0
    /// The rival in front on the Up next card, as you swipe through them. Nil: the one up next.
    @State private var rivalShown: MatchController.Level?
    /// The card in front under For today, as you swipe through your games and Today's Move.
    @State private var todayShown: String?
    /// How far the bottom bar has faded, 0 to 1: it goes as you scroll down, comes back up.
    @State private var barHidden: CGFloat = 0

    private var palette: HomeAuroraPalette { HomeAuroraPalette(dark: tone.scheme == .dark) }
    private var stage: HomeStageInfo { info.stage }

    /// Your games, or the next game when none is going. Only games: Today's Move and the game
    /// of the day are rows under For today (Alex, 2026-11-08).
    /// The games you're playing live under For today now (Alex, 2026-11-10), so the top card is
    /// always the rival up next.
    private var cards: [HomeAuroraGameCard] {
        [HomeAuroraGameCard.next(stage.upNext, fen: stage.gameFEN)]
    }

    var body: some View {
        GeometryReader { geo in
            // Small enough that the name and the header sit clear above it.
            let boardHeight: CGFloat = max(230, geo.size.height * 0.34)
            let lift: CGFloat = min(max(pulled / boardHeight, 0), 1)
            // The page's top edge, measured from the top of the screen under the status bar.
            let pageTop: CGFloat = boardHeight + 18 - pulled
            // The header gives way as the page's edge touches it, and comes back as the page
            // goes down again, following your finger both ways (Alex, 2026-11-08).
            let tuck: CGFloat = min(max((headerHeight + 6 - pageTop) / (headerHeight * 0.75), 0), 1)
            ZStack(alignment: .top) {
                HomeAuroraBackdrop(palette: palette)
                // The marble starts just under the header's gold line, never above it.
                // "Beauty of Chess" is cut into the slab under the board; it shows as the page
                // is pulled down.
                HomeAuroraMarble(palette: palette, carvingTop: boardHeight + 10,
                                 carving: Double(min(max(-pulled / 70, 0), 1)))
                    .frame(height: boardHeight + 130)
                    .padding(.top, 54)
                    .opacity(1 - 0.6 * Double(lift))
                spinningBoard(height: boardHeight, lift: lift)
                    .padding(.top, 58)
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        // The board shows through here; a tap on it plays.
                        Color.clear
                            .frame(height: boardHeight + 58 - 40)
                            .contentShape(Rectangle())
                            .onTapGesture { actions.stage.play() }
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                -proxy.frame(in: .scrollView).minY
                            } action: { value in
                                hideBar(from: pulled, to: value,
                                        tuckStart: boardHeight + 18 - headerHeight - 6)
                                pulled = value
                            }
                        page
                    }
                }
                .scrollIndicators(.hidden)
                // Once the header has tucked away, a slim veil keeps the cards from running
                // sharp under the clock and battery.
                LinearGradient(colors: [palette.bg, palette.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 14)
                    .ignoresSafeArea(edges: .top)
                    .opacity(Double(tuck))
                    .allowsHitTesting(false)
                header
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    .background(alignment: .top) {
                        // The header gets a soft backing once the page covers the board.
                        LinearGradient(colors: [palette.bg, palette.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 120)
                            .opacity(Double(lift))
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                    }
                    .opacity(1 - Double(tuck))
                    .offset(y: reduceMotion ? 0 : -14 * tuck)
                    .blur(radius: reduceMotion ? 0 : 4 * tuck)
                    .allowsHitTesting(tuck < 0.5)
                    .accessibilityHidden(tuck >= 1)
                VStack(spacing: 0) {
                    Spacer()
                    HomeAuroraTabBar(palette: palette, play: actions.stage.analyze, learn: actions.stage.learn,
                                     rooms: actions.stage.rooms, you: actions.stage.you)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .background(alignment: .bottom) {
                            // The cards fade into the room before they reach the bar, so nothing
                            // shows through or clashes behind it.
                            LinearGradient(stops: [.init(color: palette.bg.opacity(0), location: 0),
                                                   .init(color: palette.bg.opacity(0.94), location: 0.45),
                                                   .init(color: palette.bg, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 150)
                                .ignoresSafeArea(edges: .bottom)
                                .allowsHitTesting(false)
                        }
                        // The bar fades as you read down the page, from where the header
                        // tucks away, and is back the moment you scroll up (Alex, 2026-11-09:
                        // "slowly disappear as you are scrolling down, about the same time as
                        // the top area"; "it reappears as soon as you start to scroll up").
                        .opacity(1 - Double(barHidden))
                        .offset(y: reduceMotion ? 0 : 18 * barHidden)
                        .allowsHitTesting(barHidden < 0.5)
                        .accessibilityHidden(barHidden >= 1)
                }
            }
        }
        .environment(\.colorScheme, tone.scheme)
        .onAppear { music.homeAppeared() }
        .onDisappear { music.homeDisappeared() }
        .task(id: reduceMotion) { await playThrough() }
    }

    /// Scrolling down past where the header tucks away fades the bar over about 80 points;
    /// any scroll up, or a return above that point, brings it straight back.
    private func hideBar(from old: CGFloat, to new: CGFloat, tuckStart: CGFloat) {
        let delta: CGFloat = new - old
        if new <= tuckStart || delta < -2 {
            if barHidden > 0 { withAnimation(.easeOut(duration: 0.25)) { barHidden = 0 } }
        } else if delta > 0 {
            barHidden = min(1, barHidden + delta / 80)
        }
    }

    /// The pieces move slowly: the game of the day's finish, a move every few seconds, a rest on
    /// the final position, then again from the start.
    private func playThrough() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            let count: Int = stage.masterpiece?.frames.count ?? 0
            guard count > 1 else { return }
            let last: Bool = boardFrame >= count - 1
            try? await Task.sleep(for: .seconds(last ? 6 : 3.2))
            guard !Task.isCancelled else { return }
            boardFrame = last ? 0 : boardFrame + 1
        }
    }

    /// What stands on the turning board: the game of the day as it plays, or your game's pieces.
    private var boardPieces: [Piece] {
        guard let frames = stage.masterpiece?.frames, !frames.isEmpty else { return info.pieces }
        let fen: String = frames[min(boardFrame, frames.count - 1)]
        return PositionDraft(fen: fen)?.pieces ?? info.pieces
    }

    // MARK: The board

    /// The game's own 3D board turning slowly in the light; it sinks back and dims as the page
    /// comes up over it.
    private func spinningBoard(height: CGFloat, lift: CGFloat) -> some View {
        let upNext: HomeUpNext = stage.upNext
        return ZStack {
            if SculptedAssets.shared.isLoaded {
                HomeStageBoard(stage: boardStage, look: SculptedLook.clay, pieces: boardPieces,
                               black: stage.masterpiece?.flipped ?? (upNext.playerColor == .black),
                               // No rival light over it: its warm pool washed out the middle of
                               // the board (Alex, 2026-11-07). The clay board keeps its own even light.
                               light: nil,
                               leaning: upNext.inProgress && upNext.yourMove, plinth: nil,
                               still: reduceMotion, dive: 0,
                               // Far enough back that the turning board's corners never reach
                               // the view's edge: nothing cuts it off (Alex, 2026-11-08).
                               pullBack: 5)
                    .id(SculptedLook.clay.name)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .scaleEffect(1 - 0.12 * lift, anchor: .top)
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
            Spacer(minLength: 8)
            // Your numbers sit at the top right, in place of the music and crown buttons
            // (Alex, 2026-11-07); Home music is in Settings > Sound & feel.
            numbers
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            // A slight gold underline, fading at both ends.
            LinearGradient(colors: [palette.gold.opacity(0), palette.gold.opacity(0.4), palette.gold.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 0.75)
                .padding(.horizontal, 20)
        }
    }

    // MARK: The page

    /// The page that slides up over the board: your games first, then a slim line of numbers,
    /// then today's things as long rows, led by your finest move of the week.
    private var page: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 34, bottomLeading: 0,
                                                              bottomTrailing: 0, topTrailing: 34),
                                           style: .continuous)
        return VStack(spacing: 0) {
            Capsule()
                .fill(palette.ink3)
                .frame(width: 38, height: 4)
                .padding(.top, 10)
            // The Face a rival coins are gone: the rival you're on stands big in the Next game
            // card instead (Alex, 2026-11-08). No All rivals link in the corner (Alex,
            // 2026-11-10): the card swipes through them, and Rivals is in Rooms.
            HomeAuroraSection(title: "Next game", palette: palette)
            gameRow
            // Your Chess DNA right under Next game (Alex, 2026-11-10: "Move your chess DNA under the
            // next game"); it came in where Your Grudge was (2026-11-09: "Chess DNA is a nice
            // selling point").
            if let dna = info.dna {
                HomeAuroraSection(title: "Your Chess DNA", palette: palette,
                                  note: dna.gamesRead > 0 ? ChessDNAView.basis(dna) : nil)
                HomeAuroraDNA(dna: dna, palette: palette, action: actions.chessDNA)
                    .padding(.horizontal, 16)
            }
            HomeAuroraSection(title: "For today", palette: palette, note: gamesNote)
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

    private var gamesNote: String? {
        let yours: Int = info.games.filter(\.isYourMove).count
        guard !info.games.isEmpty else { return nil }
        return yours == 0 ? "Waiting on them" : (yours == 1 ? "1 needs you" : "\(yours) need you")
    }

    /// Your games as wide cards, the next one peeking in at the right.
    @ViewBuilder
    private var gameRow: some View {
        let all: [HomeAuroraGameCard] = cards
        if all.count == 1, let only = all.first, let upNext = only.upNext, !upNext.isGrudge, !upNext.inProgress {
            // The next game: swipe sideways through every rival (Alex, 2026-11-08: "I should
            // be able to swipe thru the cards").
            rivalPager(only, upNext: upNext)
        } else if all.count == 1, let only = all.first {
            // One card sits on the page like your finest move below it, edge to edge with the
            // same margins (Alex, 2026-11-08: "the same size in length as the one below").
            tile(only)
                .padding(.horizontal, 16)
        } else {
            swipeRow(all)
        }
    }

    private func swipeRow(_ all: [HomeAuroraGameCard]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(all) { card in
                    tile(card)
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

    /// Every rival, one card each, starting on the one up next. The card stays the width of the
    /// page; the next one waits just off the edge and glides in as you swipe. Fine gold dashes
    /// under it say where you are. Play starts the rival in front; a locked one says who to
    /// beat first.
    private func rivalPager(_ card: HomeAuroraGameCard, upNext: HomeUpNext) -> some View {
        let ladder = RivalLadder()
        let levels: [MatchController.Level] = MatchController.Level.allCases
        let shown: MatchController.Level = rivalShown ?? upNext.level
        return VStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(levels) { level in
                            rivalCard(level, card: card, upNext: upNext, ladder: ladder)
                                .containerRelativeFrame(.horizontal)
                                .id(level)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .scrollPosition(id: Binding(get: { rivalShown ?? upNext.level }, set: { rivalShown = $0 }))
                // The tick follows the rival in front, so putting the pager in place below is silent.
                .sensoryFeedback(.selection, trigger: shown) { _, _ in hapticsOn }
                // A position handed over as the pager first appears is not always kept: the home
                // opened on the first rival, beaten or not, under dashes that pointed at the next
                // one. So the pager is put on the rival up next by hand, once it is laid out.
                .task { proxy.scrollTo(shown, anchor: .leading) }
            }
            HStack(spacing: 6) {
                ForEach(levels) { level in
                    Capsule()
                        .fill(level == shown ? palette.gold : palette.gold.opacity(ladder.isOpen(level) ? 0.3 : 0.14))
                        .frame(width: level == shown ? 16 : 5, height: 5)
                }
            }
            .animation(.snappy, value: shown)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .onChange(of: upNext.level) { rivalShown = nil }
    }

    private func rivalCard(_ level: MatchController.Level, card: HomeAuroraGameCard, upNext: HomeUpNext,
                           ladder: RivalLadder) -> some View {
        let rival: Rival = level.rival
        let isOpen: Bool = ladder.isOpen(level)
        let lockedBy: Rival? = isOpen ? nil : MatchController.Level(rawValue: level.rawValue - 1)?.rival
        let status: String = {
            if level == upNext.level { return card.status }
            if !isOpen { return "Locked" }
            let place = "Rival \(level.rawValue + 1) of \(MatchController.Level.allCases.count)"
            return ladder.beaten(rival) ? "\(place) · Beaten" : place
        }()
        return HomeAuroraNextRival(card: card, rival: rival, palette: palette, status: status, lockedBy: lockedBy,
                                   play: { level == upNext.level ? open(card) : actions.playRival(level) },
                                   change: { level == upNext.level ? actions.stage.change() : actions.options(level) },
                                   meet: { actions.rivals(level) })
    }

    /// The next game gets the rival's own card, like your finest move (Alex, 2026-11-08);
    /// your games keep their boards.
    @ViewBuilder
    private func tile(_ card: HomeAuroraGameCard) -> some View {
        if let upNext = card.upNext {
            HomeAuroraNextRival(card: card, rival: upNext.rival, palette: palette,
                                play: { open(card) }, change: actions.stage.change,
                                meet: { actions.rivals(upNext.isGrudge ? nil : upNext.level) })
        } else {
            HomeAuroraGameTile(card: card, palette: palette) { open(card) }
        }
    }

    /// Rating, rank and streak, small in the header: serif figures over fine caps, parted by
    /// gold hairlines. Each opens what it counts.
    private var numbers: some View {
        HStack(spacing: 0) {
            number(stage.rating.map { $0.formatted(.number) } ?? "New", label: "Rating", action: actions.stage.you)
            hairline
            // Your training rank, Pawn to King. "Level" beside Rating read as the rival's level.
            number("\(stage.rankNumber)", label: "Rank", action: actions.stage.learn)
            hairline
            number("\(stage.day.streak)", label: "Streak", action: actions.stage.dailyMove)
        }
        .fixedSize()
    }

    private var hairline: some View {
        LinearGradient(colors: [palette.gold.opacity(0), palette.gold.opacity(0.55), palette.gold.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: 1, height: 26)
    }

    private func number(_ value: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(palette.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(label.uppercased())
                    .font(.system(size: 7.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(palette.gold)
            }
            .frame(minWidth: 40)
            .padding(.horizontal, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel("\(label) \(value)")
    }

    @ViewBuilder
    private var todayRows: some View {
        // Today's Move leads For today in the large gold-framed card; your finest move follows
        // as a row the size of Puzzles (Alex, 2026-11-09: "For Today should be todays move, the
        // finest move should be below in the same size area as the puzzles format"; "still have
        // the larger card view"; "just say todays move instead of your finest move").
        // With games under way, the large card swipes: your games first, the ones waiting on
        // you leading, then Today's Move (Alex, 2026-11-10: "if theres a game they're currently
        // playing, show that and allow them to swipe through for other games they may have and
        // today's move").
        todayPager
        if let finest = info.finest {
            HomeAuroraFinestRow(finest: finest, palette: palette) { actions.replay(finest.gameID) }
        }
        HomeAuroraRow(eyebrow: "Puzzles", title: "Sharpen your eye", detail: "Tactics at your level, one after another",
                      accent: palette.violet, palette: palette, action: actions.puzzles) {
            HomeAuroraJewel(glyph: Glyphs.fineEye, stone: .amethyst)
        }
        HomeAuroraRow(eyebrow: "Coach Leo", title: stage.plan?.title ?? "Today's lesson", detail: coachLine,
                      accent: palette.teal, palette: palette, action: actions.stage.coach) {
            HomeAuroraJewel(glyph: Glyphs.fineLaurel, stone: .jade)
        }
        // Analyze is the gold knight, its one button on Home (Alex, 2026-11-08), so it has no
        // row here. The game of the day, which the board up top plays, opens from its own row.
        if let masterpiece = stage.masterpiece {
            HomeAuroraRow(eyebrow: "Game of the day", title: masterpiece.title, detail: masterpiece.players,
                          accent: palette.gold, palette: palette, action: openMasterpiece) {
                HomeAuroraBoard(fen: masterpiece.frames.first, flipped: masterpiece.flipped, lit: false)
            }
        }
    }

    /// Your games under way, then Today's Move, one large card each; gold dashes under them when
    /// there is more than one.
    @ViewBuilder
    private var todayPager: some View {
        let today = HomeAuroraTodayCard(eyebrow: "Today's Move", fen: stage.todayFEN,
                                        flipped: stage.todaySolver == .black, title: todayTitle,
                                        detail: todayDetail, button: stage.day.played ? "See it" : "Play",
                                        symbol: stage.day.played ? "checkmark" : "play.fill",
                                        palette: palette, open: actions.stage.dailyMove)
        let games: [HomeCurrentGame] = info.games.filter(\.isYourMove) + info.games.filter { !$0.isYourMove }
        if games.isEmpty {
            today
        } else {
            let ids: [String] = games.map(\.id) + ["today"]
            let shown: String = todayShown ?? ids[0]
            VStack(spacing: 12) {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(games) { game in
                            let card = HomeAuroraGameCard(game)
                            HomeAuroraTodayCard(eyebrow: card.eyebrow, fen: game.fen, flipped: game.flipped,
                                                title: game.title, detail: card.tags.joined(separator: " · "),
                                                button: game.isYourMove ? "Your move" : "See the game",
                                                symbol: game.isYourMove ? "play.fill" : "eye",
                                                lit: game.isYourMove, palette: palette) { actions.open(game) }
                                .containerRelativeFrame(.horizontal)
                                .id(game.id)
                        }
                        today
                            .containerRelativeFrame(.horizontal)
                            .id("today")
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .scrollPosition(id: $todayShown)
                .sensoryFeedback(.selection, trigger: todayShown) { _, _ in hapticsOn }
                HStack(spacing: 6) {
                    ForEach(ids, id: \.self) { id in
                        Capsule()
                            .fill(id == shown ? palette.gold : palette.gold.opacity(0.3))
                            .frame(width: id == shown ? 16 : 5, height: 5)
                    }
                }
                .animation(.snappy, value: shown)
                .accessibilityHidden(true)
            }
        }
    }

    /// The game of the day, in Analyze from its first position, ready to play through.
    private func openMasterpiece() {
        if let fen = stage.masterpiece?.frames.first { actions.stage.analyzePosition(fen) }
    }

    private var todayTitle: String {
        if stage.day.found { return "Found it" }
        return stage.todaySolver == .black ? "Black to play and win" : "White to play and win"
    }

    private var todayDetail: String {
        if stage.day.played { return "Back tomorrow for the next one" }
        let streak: Int = stage.day.streak
        // The week's rest day is spent: a miss now ends the streak, so say so where it's kept.
        if stage.day.restDayUsed { return "Rest day used. Keep your \(streak)-day streak" }
        return streak > 0 ? "Keep your \(streak)-day streak" : "One puzzle, the same for everyone"
    }

    private var coachLine: String {
        if stage.trainedToday { return "Done today. Another round?" }
        guard let plan = stage.plan else { return "Pick up where you stopped" }
        return "\(plan.minutes) min with Leo"
    }

    private func open(_ card: HomeAuroraGameCard) {
        switch card.kind {
        case .game:
            if let game = card.game { actions.open(game) }
        case .next:
            actions.stage.play()
        case .today:
            actions.stage.dailyMove()
        case .masterpiece:
            openMasterpiece()
        }
    }
}

/// One of your games as a wide card: its board on the left, who and where on the right.
struct HomeAuroraGameTile: View {
    let card: HomeAuroraGameCard
    let palette: HomeAuroraPalette
    /// The next game's card offers Change beside Play: it opens the New Game sheet, for your
    /// side, clock and rival (Alex, 2026-11-08). Nil on every other card.
    var change: (() -> Void)? = nil
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
                    tagLine
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Text(card.button)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
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
                // The words take all the room beside the board. (A spacer after them cost its
                // own gap, and "Make your move" was cut to "Make your m…".)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(height: 128)
            .background(shape.fill(palette.card))
            .overlay(shape.strokeBorder(card.yourMove ? palette.gold.opacity(0.4) : palette.line, lineWidth: 1))
        }
        .buttonStyle(HomeStagePress())
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottomTrailing) {
            // On the same line as Play, at the card's right edge.
            if let change {
                Button(action: change) {
                    Text("Change")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.gold)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().strokeBorder(palette.gold.opacity(0.45), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(HomeStagePress())
                .padding(12)
                .accessibilityLabel("Change the next game")
                .accessibilityHint("Pick your side, clock and rival")
            }
        }
    }
}

extension HomeAuroraGameTile {
    /// Who, the clock and your side on one line. When the line runs out of room your side goes
    /// first, since the board beside it already shows it, rather than the line ending "You'…".
    private var tagLine: some View {
        let all: String = card.tags.joined(separator: " · ")
        let short: String = card.tags.count > 1 ? card.tags.dropLast().joined(separator: " · ") : all
        return ViewThatFits(in: .horizontal) {
            Text(all)
            Text(short)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(palette.ink2)
        .lineLimit(1)
    }
}

/// The next game, dressed like your finest move (Alex, 2026-11-08: "Change the Rival to look
/// like this, use the main pic for the rival, get rid of the coin"): the rival's own picture,
/// the still from its welcome film, in a gold frame on the left; small gold caps, the rival's
/// name in serif, the match in grey, and Play and Options as gold pills. The picture opens the
/// rival in the hall, where its film plays.
struct HomeAuroraNextRival: View {
    let card: HomeAuroraGameCard
    let rival: Rival
    let palette: HomeAuroraPalette
    /// The gold caps over the name; the card's own ("Up next") when nil.
    var status: String? = nil
    /// Set when this rival is still locked: the one to beat first.
    var lockedBy: Rival? = nil
    let play: () -> Void
    let change: () -> Void
    let meet: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        HStack(spacing: 14) {
            Button(action: meet) {
                HomeRivalFrame(rival: rival, side: 112)
                    .saturation(lockedBy == nil ? 1 : 0.15)
                    .opacity(lockedBy == nil ? 1 : 0.75)
                    .overlay {
                        if lockedBy != nil {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xF3D99A))
                                .shadow(color: .black.opacity(0.6), radius: 6)
                        }
                    }
            }
            .buttonStyle(HomeStagePress())
            .accessibilityLabel(rival.name)
            .accessibilityHint("Opens \(rival.name) in the rivals' hall")
            VStack(alignment: .leading, spacing: 4) {
                Text((status ?? card.status).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(palette.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(rival.name)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let lockedBy {
                        // Who opens it, in place of Play; the picture still opens the hall.
                        pill("Beat \(lockedBy.shortName)", symbol: "lock.fill")
                            .opacity(0.7)
                            .accessibilityLabel("Locked. Beat \(lockedBy.name) first")
                    } else {
                        Button(action: play) {
                            pill(card.upNext?.inProgress == true ? "Resume" : "Play", symbol: "play.fill")
                        }
                            .buttonStyle(HomeStagePress())
                            .accessibilityLabel("Play \(rival.name)")
                        Button(action: change) { pill("Options", symbol: "slider.horizontal.3") }
                            .buttonStyle(HomeStagePress())
                            .accessibilityLabel("Change the next game")
                            .accessibilityHint("Pick your side, clock and rival")
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(shape.fill(palette.card))
        .background(alignment: .topLeading) {
            // A warm gold light from the frame's corner, as on your finest move.
            RadialGradient(colors: [palette.gold.opacity(palette.dark ? 0.18 : 0.14), palette.gold.opacity(0)],
                           center: .topLeading, startRadius: 0, endRadius: 220)
                .clipShape(shape)
                .allowsHitTesting(false)
        }
        .overlay(shape.strokeBorder(palette.gold.opacity(0.32), lineWidth: 1))
    }

    /// "1000 · No clock · You're White".
    private var detail: String {
        ([rival.elo.replacingOccurrences(of: "~", with: "")] + card.tags).joined(separator: " · ")
    }

    private func pill(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(palette.gold)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .overlay(Capsule().strokeBorder(palette.gold.opacity(0.45), lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// A rival's own picture, the still from its welcome film, cut square on its face and set in
/// the same gold frame as your finest move. Your Grudge, who has no film, shows its portrait.
struct HomeRivalFrame: View {
    let rival: Rival
    let side: CGFloat

    /// The stills, read once each.
    @MainActor private static var stills: [String: UIImage] = [:]

    @MainActor
    private var still: UIImage? {
        guard !rival.isGrudge else { return nil }
        if let cached = Self.stills[rival.slug] { return cached }
        let image = RivalFilm.of(rival.level).cardImage
        Self.stills[rival.slug] = image
        return image
    }

    /// Where the square starts down the 9:16 still, so it sits on the rider's face: the Ashen
    /// King sits low on his throne under the dragon.
    private var top: CGFloat { rival.level == .grandmaster ? 0.2 : 0.07 }

    var body: some View {
        let pad: CGFloat = side * 0.055
        let inner: CGFloat = side - 2 * pad
        Group {
            if let still {
                Image(uiImage: still)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: inner, height: inner * 16 / 9)
                    .offset(y: -top * inner * 16 / 9)
                    .frame(width: inner, height: inner, alignment: .top)
                    .clipped()
            } else {
                Image(rival.portraitName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: inner, height: inner)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .padding(pad)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: Color(hex: 0xF3D99A), location: 0),
                                             .init(color: Color(hex: 0x9C6B2C), location: 0.45),
                                             .init(color: Color(hex: 0xE9C47C), location: 0.7),
                                             .init(color: Color(hex: 0x7E5520), location: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
        .accessibilityHidden(true)
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

/// Your Chess DNA on Home (Alex, 2026-11-09), dressed like the rows for today: a white card with
/// a thin gold edge, your style in serif with its portrait, a gold emblem at the right, then the
/// four habits as fine gold bars and your weapon and leak. A tap opens the Chess DNA page. Before
/// three games are read, it says how many more Coach Leo needs.
struct HomeAuroraDNA: View {
    let dna: ChessDNA
    let palette: HomeAuroraPalette
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if dna.hasStyle {
                    bars
                }
                if dna.weapon != nil || dna.leak != nil {
                    HStack(alignment: .top, spacing: 10) {
                        if let weapon = dna.weapon {
                            chip("Weapon", weapon.title, symbol: weapon.symbol, tint: palette.teal)
                        }
                        if let leak = dna.leak {
                            chip("Leak", leak.headline, symbol: leak.area.symbol, tint: palette.rose)
                        }
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(palette.card))
            .overlay(shape.strokeBorder(palette.line, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(HomeStagePress())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your Chess DNA")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Capsule()
                .fill(LinearGradient(colors: [palette.gold, palette.gold.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
                .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(dna.hasStyle ? "YOUR STYLE" : "STILL READING YOU")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(palette.gold)
                Text(dna.style?.title ?? "Your style, named")
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HomeAuroraJewel(style: dna.style)
                .frame(width: 64, height: 64)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var detail: String {
        if let style = dna.style { return style.portrait }
        let left = max(1, ChessDNA.gamesForStyle - dna.gamesRead)
        let games = left == 1 ? "one more game" : "\(left) more games"
        return "Play \(games) against any rival and \(Coach.current.name) will read how you play."
    }

    /// The four habits two by two, each a fine gold line with a dot where you sit.
    private var bars: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                  alignment: .leading, spacing: 12) {
            ForEach(dna.traits) { trait in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(trait.kind.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(palette.ink)
                        Spacer(minLength: 4)
                        Text(trait.word)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(trait.value == nil ? palette.ink3 : palette.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    track(trait.value)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(trait.kind.title): \(trait.word)")
            }
        }
        .padding(.leading, 17)
    }

    private func track(_ value: Double?) -> some View {
        GeometryReader { geo in
            let dot: CGFloat = 8
            let x: CGFloat = (geo.size.width - dot) * CGFloat(value ?? 0.5)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.ink.opacity(0.08)).frame(height: 2)
                Capsule().fill(palette.gold.opacity(0.55)).frame(width: x + dot / 2, height: 2)
                    .opacity(value == nil ? 0 : 1)
                Circle().fill(palette.gold).frame(width: dot, height: dot)
                    .offset(x: x)
                    .opacity(value == nil ? 0.25 : 1)
            }
            .frame(height: dot)
        }
        .frame(height: 8)
    }

    private func chip(_ label: String, _ title: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(palette.dark ? 0.12 : 0.07)))
    }
}

/// Your Grudge on Home, dressed like the rows for today (Alex, 2026-11-07: "match the other
/// areas"): a white card with a thin red edge, small caps, a serif line, and the onyx king at the
/// right. A tap opens it into the summons, with Settle it to start the game; another tap on the
/// summons closes it. Before the Grudge exists, the card says what wakes it.
struct HomeAuroraGrudge: View {
    let record: GrudgeRecord?
    let isOpen: Bool
    let palette: HomeAuroraPalette
    var born = false
    var lastSeen: (you: Int, it: Int)? = nil
    let select: () -> Void
    let settle: () -> Void

    private var red: Color { palette.dark ? Color(hex: 0xF0606C) : Color(hex: 0xC8283A) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Group {
            if let record, isOpen {
                VStack(spacing: 16) {
                    GrudgeStage(record: record, born: born, lastSeen: lastSeen)
                    Button(action: settle) {
                        Label("Settle it", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Capsule().fill(red.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(red.opacity(0.55), lineWidth: 1))
                    }
                    .buttonStyle(HomeStagePress())
                }
                .padding(16)
                .contentShape(shape)
                .onTapGesture(perform: select)
                .transition(.opacity)
            } else {
                Button(action: select) { row }
                    .buttonStyle(HomeStagePress())
                    .disabled(record == nil)
                    .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .background(shape.fill(palette.card))
        .overlay(shape.strokeBorder(isOpen ? red.opacity(0.35) : palette.line, lineWidth: 1))
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: isOpen)
    }

    private var row: some View {
        HStack(spacing: 14) {
            Capsule()
                .fill(LinearGradient(colors: [red, red.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
                .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.map { "\($0.mood.title) · \($0.score)" }?.uppercased() ?? "Not yet")
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                    .tracking(1.3)
                    .foregroundStyle(record == nil ? palette.ink3 : red)
                Text(record == nil ? "Someone is watching" : "Settle the score")
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(record.map { "Remembers every game. About \($0.rating.formatted()) now." }
                     ?? "Lose to a rival once and it takes it personally.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            GrudgeKing(scars: record?.scars ?? 0, size: 64, light: record == nil ? 0.1 : 0.55)
                .opacity(record == nil ? 0.45 : 1)
                .frame(width: 64, height: 64)
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
    }
}

/// Your Grudge's room, from Rooms (Alex, 2026-11-09: "place in rooms"): a sheet the height of
/// what it holds, the summons with Settle it once the Grudge is born, and before then the card
/// that says what wakes it. Meeting it here counts as seeing it, so the summons plays what
/// changed since last time, or its birth the first time.
struct HomeGrudgeRoom: View {
    let grudges: GrudgeStore
    let palette: HomeAuroraPalette
    let settle: () -> Void

    /// The score when you last saw your Grudge ("7-11"), so what changed since plays out.
    @AppStorage("grudge.lastSeen") private var lastSeen = ""
    @State private var since: (you: Int, it: Int)?
    @State private var born = false
    @State private var met = false
    @State private var height: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your Grudge")
                .font(.system(size: 20, weight: .medium, design: .serif))
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            if met {
                HomeAuroraGrudge(record: grudges.record, isOpen: grudges.record != nil, palette: palette,
                                 born: born, lastSeen: since, select: {}, settle: settle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(34)
        .environment(\.colorScheme, palette.dark ? .dark : .light)
        .onAppear(perform: meet)
    }

    /// Reads when you last met it, then marks it seen from here.
    private func meet() {
        guard !met else { return }
        if let record = grudges.record {
            let parts = lastSeen.split(separator: "-").compactMap { Int($0) }
            since = parts.count == 2 ? (you: parts[0], it: parts[1]) : nil
            born = grudges.unseen
            lastSeen = "\(record.yourWins)-\(record.itsWins)"
            grudges.markSeen()
        }
        met = true
    }
}

/// "Beauty of Chess" carved into the marble under the board in Cinzel Decorative Bold (Alex,
/// 2026-11-07, option 3). The letters are cut into the stone itself: each groove darkens the
/// marble under it (multiply) instead of covering it, so the slab's veins run on through the
/// letters as they would in a real inscription (Alex: "the lines would be inside the letters").
/// An inner shadow under each top edge, a faint shadowed wall above and a lit lower lip give
/// the cut its depth; "of" is gold leaf laid in the same cut.
/// On dark marble a darkened groove went black on black and the name vanished (Alex,
/// 2026-11-10, "Can't see the beauty of chess"), so there the cut is filled with pale
/// limestone instead (option B): the fill screens onto the slab, lightening it, and the veins
/// still run through the letters, brighter than the stone around them. "of" stays gold.
/// Cinzel Decorative's lowercase h carries a swash crossbar that read as broken, so the H is
/// plain Cinzel's.
struct HomeAuroraCarving: View {
    let palette: HomeAuroraPalette
    /// How much shows, 0 to 1. Applied to each layer, not the whole: an opacity on the group
    /// would flatten it and the grooves would stop multiplying with the marble.
    var reveal: Double = 1

    /// Cinzel Decorative Bold and Cinzel Bold (both SIL OFL), bundled in Home/Fonts.
    static let fontName = "CinzelDecorative-Bold"
    static let plainFontName = "Cinzel-Bold"

    private static let size: CGFloat = 33
    private var font: Font { .custom(Self.fontName, size: Self.size, relativeTo: .largeTitle) }
    private var plain: Font { .custom(Self.plainFontName, size: Self.size, relativeTo: .largeTitle) }

    /// The floor of each groove: on light marble a warm grey that darkens the stone (multiply),
    /// on dark marble pale limestone that lightens it (screen). Gold for "of".
    private var stone: Color { palette.dark ? Color(hex: 0xC9C0B2) : Color(hex: 0xDCD2C2) }
    private var gold: Color { palette.dark ? Color(hex: 0xD9A856) : Color(hex: 0xD9A24A) }
    private var floorBlend: BlendMode { palette.dark ? .screen : .multiply }

    private func words(_ body: AnyShapeStyle, of: AnyShapeStyle) -> Text {
        Text("Beauty ").font(font).foregroundStyle(body)
            + Text("of").font(font).foregroundStyle(of)
            + Text(" C").font(font).foregroundStyle(body)
            + Text("H").font(plain).foregroundStyle(body)
            + Text("ess").font(font).foregroundStyle(body)
    }

    private func words(_ style: some ShapeStyle) -> Text {
        words(AnyShapeStyle(style), of: AnyShapeStyle(style))
    }

    private func cut(_ color: Color) -> AnyShapeStyle {
        AnyShapeStyle(color
            .shadow(.inner(color: .black.opacity(palette.dark ? 0.55 : 0.3), radius: 1.4, x: 0, y: 1.6)))
    }

    var body: some View {
        ZStack {
            // The lit lower lip of each cut.
            words(Color.white.opacity(palette.dark ? 0.16 : 0.9))
                .offset(y: 1.2)
                .opacity(reveal)
            // The shadowed upper wall, just above.
            words(Color(hex: 0x3C2D19).opacity(palette.dark ? 0.35 : 0.18))
                .offset(y: -0.7)
                .opacity(reveal)
                .blendMode(.multiply)
            // The floor of the cut: it tints the marble, veins and all.
            words(cut(stone), of: cut(gold))
                .opacity(reveal)
                .blendMode(floorBlend)
        }
        .tracking(1.5)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 20)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

/// A fine gold drawing on a deep jewel tile with a thin gold edge (Alex, 2026-11-10: "more
/// elegant with color", picked Jewel and gold). Puzzles is amethyst, Coach Leo jade, and each
/// Chess DNA style has its own stone.
struct HomeAuroraJewel: View {
    enum Stone {
        case amethyst, jade, ruby, sapphire, emerald, amber, slate, violet

        /// Top-left to bottom-right.
        var colors: [Color] {
            switch self {
            case .amethyst: return [Color(hex: 0x5B3FB8), Color(hex: 0x2E1F6E)]
            case .jade: return [Color(hex: 0x1F8A7A), Color(hex: 0x0D4A45)]
            case .ruby: return [Color(hex: 0xB3283B), Color(hex: 0x5E0F1C)]
            case .sapphire: return [Color(hex: 0x2B5FB8), Color(hex: 0x13306B)]
            case .emerald: return [Color(hex: 0x2F8A57), Color(hex: 0x124A2C)]
            case .amber: return [Color(hex: 0xB8782A), Color(hex: 0x6A3F10)]
            case .slate: return [Color(hex: 0x4F5B6E), Color(hex: 0x232A36)]
            case .violet: return [Color(hex: 0x8A3FA8), Color(hex: 0x45185A)]
            }
        }
    }

    let glyph: String
    let stone: Stone

    init(glyph: String, stone: Stone) {
        self.glyph = glyph
        self.stone = stone
    }

    /// The emblem for a Chess DNA style; before the style is read, the compass on amber.
    init(style: ChessDNA.Style?) {
        switch style {
        case .attacker: self.init(glyph: Glyphs.fineAttacker, stone: .ruby)
        case .tactician: self.init(glyph: Glyphs.fineTactician, stone: .sapphire)
        case .counterpuncher: self.init(glyph: Glyphs.fineCounterpuncher, stone: .emerald)
        case .grinder: self.init(glyph: Glyphs.fineGrinder, stone: .amber)
        case .builder: self.init(glyph: Glyphs.fineBuilder, stone: .slate)
        case .allRounder: self.init(glyph: Glyphs.fineAllRounder, stone: .violet)
        case nil: self.init(glyph: Glyphs.fineAllRounder, stone: .amber)
        }
    }

    static let gold = LinearGradient(colors: [Color(hex: 0xF7E2A8), Color(hex: 0xD9AE5C), Color(hex: 0xB07E35)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 16, style: .continuous)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            tile
                .fill(LinearGradient(colors: stone.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    // A soft sheen from the top left, like light on a cut stone.
                    tile.fill(RadialGradient(colors: [.white.opacity(0.22), .white.opacity(0)],
                                             center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0,
                                             endRadius: side * 0.7))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                        .strokeBorder(Color(hex: 0xE2C27E).opacity(0.7), lineWidth: 0.7)
                        .padding(side * 0.055)
                }
                .overlay {
                    Glyph(name: glyph, size: side * 0.5625)
                        .foregroundStyle(Self.gold)
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

/// One board in the swipe row, and the words around it while it's in front.
struct HomeAuroraGameCard: Identifiable, Equatable {
    enum Kind: Equatable {
        case game, next, today, masterpiece
    }

    let id: String
    var kind: Kind = .game
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
    /// The next game, whose rival shows big in place of the board.
    var upNext: HomeUpNext? = nil
    var rival: Rival? { upNext?.rival }

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
        kind = .next
        game = nil
        title = "Play \(upNext.rival.name)"
        self.fen = fen
        flipped = upNext.playerColor == .black
        yourMove = false
        eyebrow = "Your next game"
        // A game against this rival is under way: the card picks it up (its board is under
        // For today with your other games).
        status = upNext.inProgress ? "Playing now" : "Up next"
        headline = "\(upNext.rival.name) is ready\nwhen "
        headlineEnd = "you are"
        // The title names the rival; the button just plays, with Change beside it.
        button = "Play"
        tags = [upNext.timeControl.isTimed ? upNext.timeControl.name : "No clock",
                upNext.playerColor == .black ? "You're Black" : "You're White"]
        self.upNext = upNext
    }

    static func next(_ upNext: HomeUpNext, fen: String) -> HomeAuroraGameCard {
        HomeAuroraGameCard(next: upNext, fen: fen)
    }

    private init(id: String, kind: Kind, title: String, status: String, fen: String?, flipped: Bool,
                 button: String, tags: [String]) {
        self.id = id
        self.kind = kind
        game = nil
        self.title = title
        self.fen = fen
        self.flipped = flipped
        yourMove = false
        eyebrow = status
        self.status = status
        headline = title
        headlineEnd = ""
        self.button = button
        self.tags = tags
    }

    /// Today's Move, after your games in the swipe row.
    static func today(_ day: HomeDailyState, fen: String?, solver: Piece.Color?) -> HomeAuroraGameCard {
        let side: String = solver == .black ? "Black" : "White"
        let title: String = day.found ? "Found it" : "\(side) to play and win"
        var tags: [String] = []
        if !day.difficulty.isEmpty { tags.append(day.difficulty) }
        if day.streak > 0 { tags.append("\(day.streak)-day streak") }
        return HomeAuroraGameCard(id: "today", kind: .today, title: title, status: "Move of the day", fen: fen,
                                  flipped: solver == .black, button: day.played ? "See it again" : "Solve",
                                  tags: tags.isEmpty ? ["The same for everyone"] : tags)
    }

    /// The game of the day: a famous finish.
    static func masterpiece(_ masterpiece: HomeMasterpiece) -> HomeAuroraGameCard {
        HomeAuroraGameCard(id: "masterpiece", kind: .masterpiece, title: masterpiece.title,
                           status: "Game of the day", fen: masterpiece.frames.first, flipped: masterpiece.flipped,
                           button: "Watch it", tags: [masterpiece.players])
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
    /// Makes the note a quiet link in the heading's corner ("All rivals ›").
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(palette.ink)
                // A slight gold underline.
                LinearGradient(colors: [palette.gold.opacity(0.7), palette.gold.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 44, height: 1)
            }
            Spacer()
            if let note, let action {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(note)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.gold)
                    // A bigger target than it looks, without making the heading taller.
                    .contentShape(Rectangle().inset(by: -12))
                }
                .buttonStyle(.plain)
            } else if let note {
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
                glow(Color(hex: 0xE8C27A), opacity: 0.12, at: CGPoint(x: w * 0.5, y: 420), size: w * 1.2)
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

/// The board's ground: a slab of veined marble (Calacatta by day, Nero Marquina by night) behind
/// the turning board, melting softly into the room below it.
struct HomeAuroraMarble: View {
    let palette: HomeAuroraPalette
    /// Where "Beauty of Chess" is cut, from the top of the slab, and how much of it shows (0 to 1).
    var carvingTop: CGFloat = 0
    var carving: Double = 0

    var body: some View {
        // The slab is exactly its frame: the image fills it from the top and nothing spills
        // above (a bare scaled-to-fill image would grow past its frame and creep up behind the header).
        Color.clear
            .overlay(alignment: .top) {
                Image(palette.dark ? "home-marble-dark" : "home-marble")
                    .resizable()
                    .scaledToFill()
            }
            .overlay(alignment: .top) {
                // Part of the slab: cut, clipped and faded with it.
                if carving > 0 {
                    HomeAuroraCarving(palette: palette, reveal: carving)
                        .padding(.top, carvingTop)
                }
            }
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                         .init(color: .black, location: 0.84),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

/// A glass tab bar (Today, Learn, Rooms, You) with the gold knight as its own round button.
/// You came back beside Rooms (Alex, 2026-11-09) so Settings is one tap from the bar; the Rating
/// at the top still opens it too.
struct HomeAuroraTabBar: View {
    let palette: HomeAuroraPalette
    let play: () -> Void
    let learn: () -> Void
    let rooms: () -> Void
    let you: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                tab("Today", icon: .today, on: true) {}
                tab("Learn", icon: .learn, on: false, action: learn)
                tab("Rooms", icon: .rooms, on: false, action: rooms)
                tab("You", icon: .you, on: false, action: you)
            }
            .padding(.horizontal, 6)
            .frame(height: 64)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(palette.dark ? Color(hex: 0x14161E).opacity(0.85) : Color.white.opacity(0.92)))
                    .overlay(Capsule().strokeBorder(palette.gold.opacity(0.35), lineWidth: 0.75))
                    .shadow(color: .black.opacity(palette.dark ? 0.5 : 0.14), radius: 20, y: 10)
            }
            // A tap opens Analyze; a press and hold brings up the Rooms panel (Alex, 2026-11-07).
            knight
        }
    }

    /// The knight carries its name like the tabs do, so nobody has to guess what it opens.
    private var knight: some View {
                VStack(spacing: 1) {
                    // The Gilded knight, a touch larger so its mane stripes read (Alex, 2026-11-10).
                    AnalyzeKnightGlyph()
                        .frame(width: 25, height: 30)
                    Text("Analyze")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                    .foregroundStyle(Color(hex: 0x2A1C08))
                    .frame(width: 64, height: 64)
                    .background {
                        Circle().fill(RadialGradient(stops: [.init(color: Color(hex: 0xFFF1CC), location: 0),
                                                             .init(color: Color(hex: 0xE8C27A), location: 0.45),
                                                             .init(color: Color(hex: 0xA66F25), location: 1)],
                                                     center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: 40))
                    }
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .shadow(color: .black.opacity(palette.dark ? 0.5 : 0.18), radius: 14, y: 8)
                    .contentShape(Circle())
                    .onTapGesture(perform: play)
                    .onLongPressGesture(minimumDuration: 0.35, perform: rooms)
                    .accessibilityElement()
                    .accessibilityLabel("Analyze")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Rooms", rooms)
    }

    private func tab(_ title: String, icon: HomeTabIcon.Kind, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // The icons stand out (Alex, 2026-11-08): larger, in full ink, the selected one in gold.
            VStack(spacing: 3) {
                HomeTabIcon(kind: icon,
                            color: on ? (palette.dark ? Color(hex: 0xE8C27A) : Color(hex: 0xB7832E)) : palette.ink.opacity(0.82))
                    .frame(width: 28, height: 28)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(on ? palette.ink : palette.ink2)
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

/// The bottom bar's tab icons (Alex, 2026-11-07: "Do B but make the You and Rooms from A").
/// Today and Learn are solid chess pieces in gold leaf: a pawn at sunrise and a bishop.
/// Rooms and You are engraved lines, a castle gate and a crowned shield, drawn a touch heavier so
/// they hold their own beside them.
/// Drawn on a 26-point grid; the selected tab shows in gold.
struct HomeTabIcon: View {
    enum Kind { case today, learn, rooms, you }

    let kind: Kind
    let color: Color

    var body: some View {
        Canvas { context, size in
            let k = min(size.width, size.height) / 26
            context.translateBy(x: (size.width - 26 * k) / 2, y: (size.height - 26 * k) / 2)
            context.scaleBy(x: k, y: k)
            let shading = GraphicsContext.Shading.color(color)
            let line = StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
            switch kind {
            case .today:
                // A pawn at sunrise.
                context.fill(Path(ellipseIn: CGRect(x: 9.5, y: 3.5, width: 7, height: 7)), with: shading)
                context.fill(Path { p in
                    p.move(to: CGPoint(x: 10, y: 12)); p.addLine(to: CGPoint(x: 16, y: 12))
                    p.addLine(to: CGPoint(x: 17.5, y: 20)); p.addLine(to: CGPoint(x: 8.5, y: 20)); p.closeSubpath()
                    p.addRect(CGRect(x: 7, y: 21, width: 12, height: 2.5))
                }, with: shading)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: 3, y: 7)); p.addLine(to: CGPoint(x: 6, y: 7))
                    p.move(to: CGPoint(x: 20, y: 7)); p.addLine(to: CGPoint(x: 23, y: 7))
                    p.move(to: CGPoint(x: 13, y: 1)); p.addLine(to: CGPoint(x: 13, y: 2.5))
                }, with: shading, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            case .learn:
                // A bishop, its mitre cut with the slit.
                context.drawLayer { layer in
                    layer.fill(Path { p in
                        p.move(to: CGPoint(x: 13, y: 2))
                        p.addCurve(to: CGPoint(x: 18, y: 11), control1: CGPoint(x: 16, y: 5), control2: CGPoint(x: 18, y: 8))
                        p.addCurve(to: CGPoint(x: 15.5, y: 15), control1: CGPoint(x: 18, y: 13), control2: CGPoint(x: 16.5, y: 14.5))
                        p.addLine(to: CGPoint(x: 17, y: 20)); p.addLine(to: CGPoint(x: 9, y: 20))
                        p.addLine(to: CGPoint(x: 10.5, y: 15))
                        p.addCurve(to: CGPoint(x: 8, y: 11), control1: CGPoint(x: 9.5, y: 14.5), control2: CGPoint(x: 8, y: 13))
                        p.addCurve(to: CGPoint(x: 13, y: 2), control1: CGPoint(x: 8, y: 8), control2: CGPoint(x: 10, y: 5))
                        p.closeSubpath()
                        p.addRect(CGRect(x: 7, y: 21, width: 12, height: 2.5))
                    }, with: shading)
                    layer.blendMode = .destinationOut
                    layer.stroke(Path { p in
                        p.move(to: CGPoint(x: 14.5, y: 6)); p.addLine(to: CGPoint(x: 11.5, y: 10))
                    }, with: .color(.black), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }
            case .you:
                // A crowned shield, engraved.
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: 5, y: 7)); p.addLine(to: CGPoint(x: 21, y: 7)); p.addLine(to: CGPoint(x: 21, y: 13))
                    p.addCurve(to: CGPoint(x: 13, y: 23), control1: CGPoint(x: 21, y: 18), control2: CGPoint(x: 17, y: 21))
                    p.addCurve(to: CGPoint(x: 5, y: 13), control1: CGPoint(x: 9, y: 21), control2: CGPoint(x: 5, y: 18))
                    p.closeSubpath()
                    p.move(to: CGPoint(x: 9, y: 11)); p.addLine(to: CGPoint(x: 11, y: 9)); p.addLine(to: CGPoint(x: 13, y: 11))
                    p.addLine(to: CGPoint(x: 15, y: 9)); p.addLine(to: CGPoint(x: 17, y: 11)); p.addLine(to: CGPoint(x: 17, y: 13))
                    p.addLine(to: CGPoint(x: 9, y: 13)); p.closeSubpath()
                }, with: shading, style: line)
            case .rooms:
                // A castle gate, engraved.
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: 4, y: 23))
                    for (x, y) in [(4, 9), (7, 9), (7, 6), (10, 6), (10, 9), (16, 9), (16, 6), (19, 6), (19, 9), (22, 9), (22, 23)] {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                    p.closeSubpath()
                    p.move(to: CGPoint(x: 10, y: 23)); p.addLine(to: CGPoint(x: 10, y: 17))
                    p.addArc(center: CGPoint(x: 13, y: 17), radius: 3, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                    p.addLine(to: CGPoint(x: 16, y: 23))
                }, with: shading, style: line)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: 12, y: 17)); p.addLine(to: CGPoint(x: 12, y: 23))
                    p.move(to: CGPoint(x: 14, y: 17)); p.addLine(to: CGPoint(x: 14, y: 23))
                }, with: .color(color.opacity(0.7)), style: line)
            }
        }
        .accessibilityHidden(true)
    }
}
