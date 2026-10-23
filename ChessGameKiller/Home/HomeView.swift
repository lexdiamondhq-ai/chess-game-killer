import ChessKit
import SwiftUI

/// Everything the home screen can open. The game screen owns the sheets and covers;
/// the home only asks for them.
struct HomeActions {
    /// Opens the New Game sheet.
    var play: () -> Void = {}
    /// Starts this game straight away.
    var start: (MatchController.Setup) -> Void = { _ in }
    /// Opens the New Game sheet with this rival picked.
    var playRival: (MatchController.Level) -> Void = { _ in }
    var resume: () -> Void = {}
    var analyze: () -> Void = {}
    var train: () -> Void = {}
    /// Starts today's session with Coach Leo.
    var trainToday: (SessionPlan) -> Void = { _ in }
    var puzzles: () -> Void = {}
    var rewind: () -> Void = {}
    var openGame: (SavedGame) -> Void = { _ in }
    var army: () -> Void = {}
    var settings: () -> Void = {}
    /// The premium screen. Its rows show only once this is set.
    var premium: (() -> Void)? = nil
}

/// The home screen. The real 3D board is the world behind the whole page: at rest it fills
/// the top of the screen with nothing on it, and as the page scrolls the camera walks around
/// it and moves in on your king while the glass cards rise over it and it slips out of focus.
///
/// The page, top to bottom: a chess clock (resume your game, or start the next one), today's
/// puzzle and session, the ladder of rivals and the scoresheet of your games. Games with
/// friends come right under the clock while one is going; otherwise Challenge a friend
/// follows the ladder. The glass dock
/// holds the five doors. Your pieces and Settings are in the You panel, from the dock or by
/// pulling the board down. Each thing has one way in, so nothing is found twice.
struct HomeView: View {
    let match: MatchController
    let theme: BoardTheme
    let actions: HomeActions

    @Environment(GameVault.self) private var vault
    @Environment(ArmyStore.self) private var army
    @Environment(TrainingStore.self) private var training
    @Environment(PuzzleStore.self) private var puzzles
    /// Challenge a friend, when the app provides it (pictures drawn in tests don't).
    @Environment(ChallengeCenter.self) private var challenges: ChallengeCenter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("setup.side") private var side: SideChoice = .white
    /// Nil until a rival has been picked: a first game is against Spark.
    @AppStorage("setup.level") private var storedLevel: Int?
    @AppStorage("setup.clock") private var timeControl: TimeControl = .unlimited
    @AppStorage("haptics") private var hapticsOn = true

    @State private var scroll = HomeScroll()
    /// The You panel, and where it came from.
    @State private var you: YouOrigin?
    /// Pulled past the mark with the finger still down: it opens on release.
    @State private var pullArmed = false
    @State private var interacting = false
    /// Ready to open again once the page is back near the top (before iOS 18).
    @State private var pullReady = true
    /// Today's session, worked out once rather than on every redraw.
    @State private var plan: SessionPlan?
    /// The clock card has scrolled out of sight; the dock carries it instead.
    @State private var clockGone = false
    @State private var clockHeight: CGFloat = 236

    enum YouOrigin { case top, bottom }

    /// How far the board must be pulled down to open the You panel.
    static let pullToOpen: CGFloat = 86
    private static let space = "home-scroll"

    init(match: MatchController, theme: BoardTheme, actions: HomeActions, showsYou: Bool = false) {
        self.match = match
        self.theme = theme
        self.actions = actions
        _you = State(initialValue: showsYou ? .bottom : nil)
    }

    // MARK: Reading

    private var look: SculptedLook { theme.sculptedLook ?? .gilded }
    private var tone: HomeTone { .of(look) }
    /// The pieces on the clock and in diagrams match the board behind the page.
    private var pieceTheme: BoardTheme { theme.sculptedLook == nil ? .named(.gilded) : theme }

    private var upNext: HomeUpNext {
        HomeUpNext.make(match: match, side: side,
                        level: storedLevel.flatMap(MatchController.Level.init(rawValue:)),
                        timeControl: timeControl, hasPlayed: !vault.games.isEmpty)
    }

    private var piecesLine: String {
        army.gamesPlayed == 0 ? "Every piece remembers its games" : "\(army.gamesPlayed) games together"
    }

    /// How far above the dock the page starts to fade away.
    private static let dockFade: CGFloat = 52

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let layout = HomeLayout(size: geo.size, insets: geo.safeAreaInsets, cardHeight: clockHeight)
            let upNext = self.upNext
            ZStack(alignment: .top) {
                HomeWorld(scroll: scroll, look: look, tone: tone, pieces: match.game.pieces.map(\.piece),
                          black: upNext.playerColor == .black, pool: layout.boardCenter,
                          restLook: layout.restLook, endLook: layout.crownLook,
                          walk: layout.walk, foot: layout.cardTop)

                page(layout, upNext: upNext)

                HomeTopEdge(scroll: scroll, tone: tone, start: layout.cardTop - layout.safeTop - 24,
                            height: layout.safeTop + 40)
                    .ignoresSafeArea(edges: .top)

                HomePullCue(scroll: scroll, tone: tone, threshold: Self.pullToOpen, armed: pullArmed)
                    .padding(.top, 6)

                if let origin = you {
                    youPanel(origin, layout: layout)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .tint(tone.metal)
        .sensoryFeedback(.impact(weight: .light), trigger: pullArmed) { _, armed in armed && hapticsOn }
        .sensoryFeedback(.impact(weight: .medium), trigger: you != nil) { _, open in open && hapticsOn }
        .task {
            await puzzles.load()
            puzzles.prepareUpNext()
        }
        .onChange(of: puzzles.upNext == nil) { _, gone in
            // Puzzles took the one shown here: pick the next, so the home always shows the puzzle Solve opens.
            if gone { puzzles.prepareUpNext() }
        }
        .task(id: planKey) {
            plan = training.dailyPlan()
        }
    }

    /// Changes whenever today's plan would: a session done, a new day.
    private var planKey: String {
        "\(training.progress.sessionsDone) \(training.progress.xp) \(training.trainedToday) \(Trainer.dayString(.now))"
    }

    // MARK: The page

    private func page(_ layout: HomeLayout, upNext: HomeUpNext) -> some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .named(Self.space)).minY
                        } action: { minY in
                            scrolled(to: -minY)
                        }
                    // The board shows through here. Nothing is drawn on it.
                    Color.clear
                        .frame(height: layout.cardTop)
                        .accessibilityHidden(true)
                    HomeClockCard(upNext: upNext, tone: tone, pieceTheme: pieceTheme,
                                  primary: { primary(upNext) }, secondary: { secondary(upNext) })
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { clockHeight = $0 }
                        .onGeometryChange(for: Bool.self) { proxy in
                            proxy.frame(in: .named(Self.space)).maxY < layout.safeTop + 20
                        } action: { gone in
                            clockGone = gone
                        }
                    sections(upNext: upNext)
                }
                .padding(.horizontal, 16)
                // The last card ends clear of the fade above the dock.
                .padding(.bottom, Self.dockFade + 16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: Self.space)
            .modifier(HomeScrollPhase { isInteracting, released in
                interacting = isInteracting
                if released, pullArmed {
                    pullArmed = false
                    openYou(.top)
                }
            })
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeDock(tone: tone, upNext: upNext, compact: clockGone, actions: actions,
                         openYou: { openYou(.bottom) }, primary: { primary(upNext) })
                    .background(alignment: .top) {
                        // The page fades away just above the dock and stays hidden under it.
                        HomeBottomEdge(tone: tone, fade: Self.dockFade)
                            .padding(.top, -Self.dockFade)
                            .ignoresSafeArea(edges: .bottom)
                    }
            }
            // With the You panel open the page steps back, out of focus.
            .blur(radius: you == nil ? 0 : 12)
            .accessibilityHidden(you != nil)
            .allowsHitTesting(you == nil)
            .task { await showcaseScroll(reader) }
        }
    }

    /// CI's pictures on the simulator open the page at a section with `-showcaseHomeAt today`
    /// (or ladder, games, friends), as Showcase in ChessGameKillerApp.swift does for a game.
    /// A normal launch never passes it.
    private func showcaseScroll(_ reader: ScrollViewProxy) async {
        guard let section = UserDefaults.standard.string(forKey: "showcaseHomeAt") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        reader.scrollTo(section, anchor: UnitPoint(x: 0.5, y: 0.2))
    }

    @ViewBuilder
    private func sections(upNext: HomeUpNext) -> some View {
        let friendGames = challenges?.store.sorted.filter { !$0.isOver } ?? []
        // A friend's game still going comes first, under the clock.
        if !friendGames.isEmpty {
            friends(friendGames)
        }

        // Dated like a newspaper's chess column; it turns over at midnight with the page open.
        TimelineView(.everyMinute) { context in
            HomeSectionHeader(title: "Today", tone: tone, note: HomeView.dateline(context.date), dateline: true)
        }
        .id("today")
        HomeTodayCard(puzzle: puzzles.upNext.flatMap(HomePuzzle.init), rating: puzzles.progress.rating,
                      plan: plan, trainedToday: training.trainedToday,
                      tone: tone, pieceTheme: pieceTheme, solve: actions.puzzles,
                      startSession: actions.trainToday, train: actions.train)

        let ladder = HomeLadder(games: vault.games)
        HomeSectionHeader(title: "The ladder", tone: tone,
                          note: ladder.nextToBeat == nil ? "You lead every rival" : nil)
            .id("ladder")
        HomeLadderCard(ladder: ladder, tone: tone, pieceTheme: pieceTheme, youColor: upNext.playerColor,
                       play: { level in actions.playRival(level) })

        // With none going, the way to start one follows the rivals.
        if friendGames.isEmpty {
            friends([])
        }

        // The game under way is on the clock card. (A long one is also kept in Your games
        // while the app is away, in case iOS closes it.)
        let played = upNext.inProgress ? vault.games.filter { $0.id != match.gameID } : vault.games
        let rows = HomeGameRow.rows(played)
        if !rows.isEmpty {
            let week = HomeGameRow.thisWeek(played)
            HomeSectionHeader(title: "Your games", tone: tone, note: week > 0 ? "\(week) this week" : nil)
                .id("games")
            // "All N games" opens Rewind, which lists every saved game.
            HomeScoresheet(rows: rows, total: vault.games.count, tone: tone,
                           open: actions.openGame, openAll: actions.rewind)
        }
    }

    /// Your games with friends and the way to start one: Challenge a friend opens the composer,
    /// which lists every friend game too.
    @ViewBuilder
    private func friends(_ games: [FriendGame]) -> some View {
        if let challenges {
            HomeSectionHeader(title: "With friends", tone: tone)
                .id("friends")
            HomeFriendsCard(games: games, tone: tone, open: { challenges.play($0) }, challenge: { challenges.compose() })
                .task { await challenges.refreshGames() }
        }
    }

    /// "Thursday, October 23", in the reader's own way of writing a date.
    static func dateline(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    // MARK: The clock's buttons

    /// Resume the game under way, or start the next one as set up, against the rival named.
    private func primary(_ upNext: HomeUpNext) {
        if upNext.inProgress {
            actions.resume()
            return
        }
        // Remember the rival, so the next visit offers the same one.
        storedLevel = upNext.level.rawValue
        actions.start(upNext.setup(side: side))
    }

    /// New game during a game, or Change before one, which opens the New Game sheet on the
    /// rival the card shows. The sheet asks before a new game ends the one under way.
    private func secondary(_ upNext: HomeUpNext) {
        if upNext.inProgress {
            actions.play()
        } else {
            actions.playRival(upNext.level)
        }
    }

    // MARK: You

    private func scrolled(to y: CGFloat) {
        scroll.y = y
        guard you == nil else { return }
        if #available(iOS 18.0, *) {
            // Armed while the finger holds the board past the mark; it opens on release.
            let past = y < -Self.pullToOpen
            if interacting, past != pullArmed { pullArmed = past }
            if !interacting, !past, pullArmed { pullArmed = false }
        } else {
            if y > -12 { pullReady = true }
            if pullReady, y < -Self.pullToOpen {
                pullReady = false
                openYou(.top)
            }
        }
    }

    private func openYou(_ origin: YouOrigin) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.84)) {
            you = origin
        }
    }

    private func closeYou() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.36, dampingFraction: 0.9)) {
            you = nil
        }
    }

    @ViewBuilder
    private func youPanel(_ origin: YouOrigin, layout: HomeLayout) -> some View {
        let fromTop = origin == .top
        tone.canvas.opacity(0.7)
            .ignoresSafeArea()
            .onTapGesture { closeYou() }
            .transition(.opacity)
            .accessibilityHidden(true)
        HomeYouPanel(tone: tone, piecesLine: piecesLine, actions: actions, fromTop: fromTop, close: closeYou)
            .padding(.horizontal, 16)
            .padding(.top, fromTop ? 6 : 0)
            .padding(.bottom, fromTop ? 0 : 10)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: fromTop ? .top : .bottom)
            .transition(reduceMotion ? .opacity : .move(edge: fromTop ? .top : .bottom).combined(with: .opacity))
            .zIndex(2)
    }
}

/// Where things sit on the home, from the screen's size.
struct HomeLayout {
    let width: CGFloat
    /// The whole screen, under the status bar and the home indicator too.
    let height: CGFloat
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let cardHeight: CGFloat

    init(size: CGSize, insets: EdgeInsets, cardHeight: CGFloat) {
        width = size.width
        height = size.height + insets.top + insets.bottom
        safeTop = insets.top
        safeBottom = insets.bottom
        self.cardHeight = cardHeight
    }

    /// The frame the board is composed in: the top of the screen, as tall as a phone is wide and a bit.
    var heroFrame: CGFloat { min(max(width * 1.2, 440), 620) + safeTop * 0.3 }
    /// Where the board's middle sits at rest, from the top of the screen.
    var boardCenter: CGFloat { heroFrame / 2 }
    /// Where the camera's look point (the near half of the board) sits at rest: high, so the
    /// pieces rising from it fill the top of the screen.
    var restLook: CGFloat { heroFrame * 0.323 }
    /// How far the page scrolls while the camera walks in and the board goes soft.
    var walk: CGFloat { heroFrame * 0.62 }
    /// Where the king's head sits once the camera has come in: halfway between the status
    /// bar and the top of the clock card at that moment, so the cross and crown both show.
    var crownLook: CGFloat {
        max((safeTop + cardTop - HomeWorld.arrival * walk) / 2, safeTop + 40)
    }
    /// The dock and the space around it.
    static let dockZone: CGFloat = 76

    /// The top of the clock card: over the foot of the board, and always wholly above the dock.
    var cardTop: CGFloat {
        let natural = heroFrame - 112
        let fits = height - safeBottom - Self.dockZone - cardHeight - 10
        return max(min(natural, fits), height * 0.28)
    }
}

/// Tells the home when a finger is on the page and when it lets go (iOS 18 and later).
private struct HomeScrollPhase: ViewModifier {
    let changed: (_ interacting: Bool, _ released: Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { old, new in
                changed(new == .interacting, old == .interacting && new != .interacting)
            }
        } else {
            content
        }
    }
}
