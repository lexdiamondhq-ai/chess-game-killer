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
    /// Opens Analyze on the camera, to read a real board.
    var scan: () -> Void = {}
    var train: () -> Void = {}
    /// Starts today's session with Coach Leo.
    var trainToday: (SessionPlan) -> Void = { _ in }
    var puzzles: () -> Void = {}
    /// Opens Today's Move, the puzzle of the day.
    var dailyMove: () -> Void = {}
    var rewind: () -> Void = {}
    var openGame: (SavedGame) -> Void = { _ in }
    var army: () -> Void = {}
    var settings: () -> Void = {}
    /// The premium screen. Its rows show only once this is set.
    var premium: (() -> Void)? = nil
}

/// The home screen, as tiles that fit on about one screen (Alex's Bento, 2026-10-30).
///
/// Top to bottom: hello with your streak and level; the board window, the real 3D set with
/// the game under way (or the next one) and the way to play right on it; Play a person
/// (Online, or A friend by link); Today's Move and today's session with the coach side by
/// side; the games still going with people, as a strip of small boards; the ladder of rivals;
/// and your games. The glass dock holds the four doors and, in their middle, the gold knight:
/// a tap plays, a hold opens its shortcuts (the five rivals, Online, a friend, Today's Move,
/// a real board through the camera). Your pieces, your games and Settings are in the You
/// panel, from the dock or by pulling the page down.
struct HomeView: View {
    let match: MatchController
    let theme: BoardTheme
    let actions: HomeActions

    @Environment(GameVault.self) private var vault
    @Environment(ArmyStore.self) private var army
    @Environment(TrainingStore.self) private var training
    @Environment(PuzzleStore.self) private var puzzles
    /// The daily streak and Today's Move (pictures drawn in tests may leave it out).
    @Environment(DailyStore.self) private var daily: DailyStore?
    /// Challenge a friend, when the app provides it (pictures drawn in tests don't).
    @Environment(ChallengeCenter.self) private var challenges: ChallengeCenter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("setup.side") private var side: SideChoice = .white
    /// Nil until a rival has been picked: a first game is against Spark.
    @AppStorage("setup.level") private var storedLevel: Int?
    @AppStorage("setup.clock") private var timeControl: TimeControl = .unlimited
    @AppStorage("haptics") private var hapticsOn = true
    /// The name friends see, from the last challenge: the home says hello with it.
    @AppStorage(ChallengeName.key) private var playerName = ""

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
    /// The board window has scrolled out of sight; the dock carries its button instead.
    @State private var windowGone = false
    /// The jewel's shortcuts are open above it.
    @State private var shortcutsOpen = false
    /// The dock's bar, in the home's space: the jewel stands in its middle.
    @State private var dockBar: CGRect = .zero
    /// The one-time note that the jewel holds shortcuts.
    @State private var jewelTip = false
    /// The board home: the 3D board up top and one sheet over it (Settings can turn it off).
    @AppStorage(HomeLayout.key) private var boardSheet = HomeLayout.defaultOn
    /// Where the sheet rests, and how far a finger has it from there.
    @State private var sheetDetent: HomeSheetDetent = .half
    @State private var sheetDrag: CGFloat = 0
    @State private var sheetDragging = false
    /// The sheet's tab, and whether the last pick moved right (its page comes in from the right).
    @State private var sheetTab: HomeSheetTab = .today
    @State private var sheetForward = true

    enum YouOrigin { case top, bottom }

    /// How far the page must be pulled down to open the You panel.
    static let pullToOpen: CGFloat = 86
    private static let space = "home-scroll"
    /// The home's own space, where the dock says where its jewel is.
    static let root = "home-root"
    /// The gap between tiles, and between the tiles and the screen's edge.
    static let gap: CGFloat = 10

    init(match: MatchController, theme: BoardTheme, actions: HomeActions, showsYou: Bool = false,
         showsShortcuts: Bool = false, sheet: HomeSheetDetent = .half, tab: HomeSheetTab = .today) {
        self.match = match
        self.theme = theme
        self.actions = actions
        _you = State(initialValue: showsYou ? .bottom : nil)
        _shortcutsOpen = State(initialValue: showsShortcuts)
        _sheetDetent = State(initialValue: sheet)
        _sheetTab = State(initialValue: tab)
    }

    // MARK: Reading

    private var look: SculptedLook { theme.sculptedLook ?? .gilded }
    private var tone: HomeTone { .of(look) }
    /// The pieces on the small boards match the board in the window.
    private var pieceTheme: BoardTheme { theme.sculptedLook == nil ? .named(.gilded) : theme }

    private var upNext: HomeUpNext {
        HomeUpNext.make(match: match, side: side,
                        level: storedLevel.flatMap(MatchController.Level.init(rawValue:)),
                        timeControl: timeControl, hasPlayed: !vault.games.isEmpty)
    }

    private var piecesLine: String {
        army.gamesPlayed == 0 ? "Every piece remembers its games" : "\(army.gamesPlayed) games together"
    }

    private var gamesLine: String {
        switch vault.games.count {
        case 0: return "Replay and rewrite your games"
        case 1: return "1 game to replay and rewrite"
        default: return "\(vault.games.count) games to replay and rewrite"
        }
    }

    /// How far above the dock the page starts to fade away.
    private static let dockFade: CGFloat = 52

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            ZStack(alignment: .top) {
                HomeBackdrop(tone: tone)

                if boardSheet {
                    sheetHome(geo)
                } else {
                    page(safeTop: safeTop)

                    HomeTopEdge(scroll: scroll, tone: tone, start: 0, height: safeTop + 34)
                        .ignoresSafeArea(edges: .top)

                    HomePullCue(scroll: scroll, tone: tone, threshold: Self.pullToOpen, armed: pullArmed)
                        .padding(.top, 6)
                }

                if jewelTip, !shortcutsOpen, you == nil {
                    jewelNote(in: geo.size)
                }

                if shortcutsOpen {
                    shortcuts(in: geo.size)
                }

                if let origin = you {
                    youPanel(origin)
                }
            }
            .coordinateSpace(.named(Self.root))
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .tint(tone.metal)
        .sensoryFeedback(.impact(weight: .light), trigger: pullArmed) { _, armed in armed && hapticsOn }
        .sensoryFeedback(.impact(weight: .medium), trigger: you != nil) { _, open in open && hapticsOn }
        .sensoryFeedback(.impact(weight: .medium), trigger: shortcutsOpen) { _, open in open && hapticsOn }
        .sensoryFeedback(.impact(weight: .light), trigger: sheetDetent) { _, _ in hapticsOn }
        .sensoryFeedback(.selection, trigger: sheetTab) { _, _ in hapticsOn }
        .task {
            await puzzles.load()
            puzzles.prepareUpNext()
        }
        .task { await introduceJewel() }
        .onChange(of: puzzles.upNext == nil) { _, gone in
            // Puzzles took the one ready: pick the next, so Puzzles always opens on one.
            if gone { puzzles.prepareUpNext() }
        }
        .task(id: planKey) {
            // The same plan as the Train page's Today card: Coach Leo's course while there is
            // course left, then real puzzles at the player's level aimed at what their games show.
            plan = await training.planToday(puzzles: puzzles, games: vault.games)
        }
    }

    /// Changes whenever today's plan would: a session done, a new day, a game saved.
    private var planKey: String {
        "\(training.progress.sessionsDone) \(training.progress.xp) \(training.trainedToday) \(Trainer.dayString(.now)) \(vault.games.count)"
    }

    // MARK: The page

    private func page(safeTop: CGFloat) -> some View {
        let upNext = self.upNext
        let ladder = HomeLadder(games: vault.games)
        let day = dailyState
        return ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // The very top of the page, at the screen's top at rest: how far it has scrolled.
                    Color.clear.frame(height: 0)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.frame(in: .named(Self.space)).minY
                        } action: { minY in
                            scrolled(to: -minY)
                        }
                    VStack(alignment: .leading, spacing: Self.gap) {
                        HomeGreeting(name: playerName, streak: day.streak, doneToday: day.doneToday,
                                     streakDetail: day.detail, level: ladder.yourRating, tone: tone,
                                     openStreak: actions.dailyMove, openLevel: { show("ladder", in: reader) })
                        window(upNext, safeTop: safeTop)
                        tiles(upNext: upNext, ladder: ladder, day: day)
                    }
                    .padding(.top, safeTop + 4)
                    .padding(.horizontal, 16)
                    // The last tile ends clear of the fade above the dock.
                    .padding(.bottom, Self.dockFade + 16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
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
            // The page runs under the status bar, so its top is measured from the screen's.
            .ignoresSafeArea(edges: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HomeDock(tone: tone, upNext: upNext, compact: windowGone, open: shortcutsOpen, actions: actions,
                         openYou: { openYou(.bottom) }, primary: { primary(upNext) }, hold: openShortcuts,
                         placed: { bar in dockBar = bar })
                    .background(alignment: .top) {
                        // The page fades away just above the dock and stays hidden under it.
                        HomeBottomEdge(tone: tone, fade: Self.dockFade)
                            .padding(.top, -Self.dockFade)
                            .ignoresSafeArea(edges: .bottom)
                    }
            }
            // With the You panel or the shortcuts open the page steps back, out of focus.
            .blur(radius: veiled ? 12 : 0)
            .accessibilityHidden(veiled)
            .allowsHitTesting(!veiled)
            .task { await showcaseScroll(reader) }
        }
    }

    private func window(_ upNext: HomeUpNext, safeTop: CGFloat) -> some View {
        HomeBoardWindow(upNext: upNext, tone: tone, look: look, pieces: match.game.pieces.map(\.piece),
                        scroll: scroll, primary: { primary(upNext) }, secondary: { secondary(upNext) })
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.frame(in: .named(Self.space)).maxY < safeTop + 20
            } action: { gone in
                windowGone = gone
            }
            .id("play")
    }

    @ViewBuilder
    private func tiles(upNext: HomeUpNext, ladder: HomeLadder, day: HomeDailyState) -> some View {
        // Whose move it is in every game going, right under the board, where it's seen first.
        currentGames(upNext)

        playPerson()

        HStack(alignment: .top, spacing: Self.gap) {
            HomeDailyTile(puzzle: dailyPuzzle, daily: day, tone: tone, pieceTheme: pieceTheme,
                          solve: actions.dailyMove)
            HomeCoachTile(plan: plan, trainedToday: training.trainedToday, progress: training.rankProgress,
                          tone: tone, start: actions.trainToday, train: actions.train)
        }
        .fixedSize(horizontal: false, vertical: true)
        .id("today")

        if HomeNoticeCard.shows(day) {
            HomeNoticeCard(daily: day, tone: tone, remind: answerReminder)
                .transition(.opacity)
        }

        HomeLadderTile(ladder: ladder, tone: tone, play: { level in actions.playRival(level) })
            .padding(.top, 4)
            .id("ladder")

        // The game under way is in the window. (A long one is also kept in Your games while
        // the app is away, in case iOS closes it.)
        let played = upNext.inProgress ? vault.games.filter { $0.id != match.gameID } : vault.games
        if !played.isEmpty {
            HomeGamesTile(rows: HomeGameRow.rows(played), total: vault.games.count,
                          week: HomeGameRow.thisWeek(played), tone: tone, openAll: actions.rewind)
                .id("games")
        }
    }

    /// Scrolls the page to a tile, as the level chip does for the ladder.
    private func show(_ id: String, in reader: ScrollViewProxy) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.88)) {
            reader.scrollTo(id, anchor: .center)
        }
    }

    /// CI's pictures on the simulator open the page at a tile with `-showcaseHomeAt today`
    /// (or ladder, games, friends, current), as Showcase in ChessGameKillerApp.swift does for
    /// a game. A normal launch never passes it.
    private func showcaseScroll(_ reader: ScrollViewProxy) async {
        guard let section = UserDefaults.standard.string(forKey: "showcaseHomeAt") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        reader.scrollTo(section, anchor: UnitPoint(x: 0.5, y: 0.2))
    }

    /// The way to start a game with a person: online, or a friend by link.
    @ViewBuilder
    private func playPerson() -> some View {
        if let challenges {
            HomePlayTile(tone: tone, waiting: challenges.onlineWaiting,
                         online: { challenges.playOnline() }, friend: { challenges.compose() })
                .id("friends")
                .task {
                    // Keeps whose move it is up to date while the home is showing.
                    while !Task.isCancelled {
                        await challenges.refreshGames()
                        await challenges.refreshOnlineCount()
                        try? await Task.sleep(for: .seconds(ChallengeCenter.refreshInterval))
                    }
                }
        }
    }

    /// Every game still going, your move first. The game against the computer is listed
    /// too, though the board window shows it: this is the one place for all your games.
    private func currentGameList(_ upNext: HomeUpNext) -> [HomeCurrentGame] {
        let friends: [FriendGame] = challenges?.store.sorted ?? []
        return HomeCurrentGame.list(upNext, fen: match.game.fen, friends: friends)
    }

    @ViewBuilder
    private func currentGames(_ upNext: HomeUpNext) -> some View {
        let games = currentGameList(upNext)
        if !games.isEmpty {
            HomeCurrentStrip(games: games, tone: tone, pieceTheme: pieceTheme) { game in
                if let friend = game.friendGame {
                    challenges?.play(friend)
                } else {
                    actions.resume()
                }
            }
            .padding(.top, 6)
            .id("current")
        }
    }

    // MARK: The day

    /// Today's Move as a small board, the same puzzle for every player.
    private var dailyPuzzle: HomePuzzle? {
        guard let today = daily?.puzzle() ?? DailyMoves.puzzle(for: .now) else { return nil }
        return HomePuzzle(LichessPuzzle(id: today.id, fen: today.fen, moves: today.moves, rating: today.rating,
                                        themes: today.themes))
    }

    private var dailyState: HomeDailyState {
        guard let daily else { return HomeDailyState() }
        let today = daily.puzzle()
        var state = HomeDailyState()
        state.streak = daily.streak
        state.doneToday = daily.doneToday
        state.number = today?.number ?? 0
        state.difficulty = today?.difficulty ?? ""
        state.played = daily.playedTodaysMove
        state.found = daily.playedTodaysMove && daily.state.moveFound
        state.puzzlesToday = daily.puzzlesToday
        if let mark = daily.markToday {
            state.mark = "\(mark.piece) now carries your \(mark.days)-day mark, for good."
        }
        if let next = daily.nextMilestone {
            state.nextMark = next.toGo == 1 ? "Tomorrow a piece earns your \(next.days)-day mark."
                : "\(next.toGo) more days and a piece earns your \(next.days)-day mark."
        }
        state.asksReminder = daily.doneToday && !daily.state.reminderAsked
        return state
    }

    /// The reminder question, answered: asks iOS for permission on a yes.
    private func answerReminder(_ yes: Bool) {
        withAnimation(.snappy(duration: 0.3)) {
            daily?.markReminderAsked()
        }
        guard yes else { return }
        UserDefaults.standard.set(true, forKey: DailyReminders.enabledKey)
        Task { @MainActor in
            _ = await DailyReminders.requestPermission()
            // Plans the reminders now that they may be sent.
            daily?.onChange?()
        }
    }

    // MARK: The window's buttons

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
    /// rival the window shows. The sheet asks before a new game ends the one under way.
    private func secondary(_ upNext: HomeUpNext) {
        if upNext.inProgress {
            actions.play()
        } else {
            actions.playRival(upNext.level)
        }
    }

    // MARK: The jewel's shortcuts

    /// Something stands over the page: the You panel or the shortcuts.
    private var veiled: Bool { you != nil || shortcutsOpen }

    private func openShortcuts() {
        TipBook.markSeen(.jewelShortcuts)
        jewelTip = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.8)) {
            shortcutsOpen = true
        }
    }

    private func closeShortcuts() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.9)) {
            shortcutsOpen = false
        }
    }

    /// A rival picked from the jewel: the game starts at once, on the side and clock picked
    /// last time. During a game the New Game sheet opens on that rival instead, and asks
    /// before the game under way ends.
    private func playRival(_ level: MatchController.Level) {
        if upNext.inProgress {
            actions.playRival(level)
            return
        }
        storedLevel = level.rawValue
        actions.start(MatchController.Setup(playerColor: side.color, level: level, timeControl: timeControl))
    }

    /// The jewel's other ways to a game: a person online or a friend (when the app has them),
    /// Today's Move, and a real board through the camera.
    private var shortcutList: [HomeShortcut] {
        var list: [HomeShortcut] = []
        if let challenges {
            let waiting: Int = challenges.onlineWaiting ?? 0
            list.append(HomeShortcut(title: "Online", glyph: Glyphs.online, hint: "Play someone at your level now",
                                     live: waiting > 0) { challenges.playOnline() })
            list.append(HomeShortcut(title: "A friend", glyph: Glyphs.challenge, hint: "Send a friend a game by link") {
                challenges.compose()
            })
        }
        list.append(HomeShortcut(title: "Today's Move", glyph: Glyphs.today, hint: "The puzzle of the day",
                                 action: actions.dailyMove))
        list.append(HomeShortcut(title: "Scan a board", glyph: Glyphs.scan, hint: "Read a real board with the camera",
                                 action: actions.scan))
        return list
    }

    /// Where the jewel stands, in the home's space: the middle of the dock's bar, a little
    /// above it at rest. Before the dock has been measured, where it would be.
    private func jewelCenter(in size: CGSize) -> CGPoint {
        let lift: CGFloat = (windowGone || boardSheet) ? 0 : HomeDock.raise
        guard dockBar != .zero else {
            return CGPoint(x: size.width / 2, y: size.height - 38 - lift)
        }
        return CGPoint(x: dockBar.midX, y: dockBar.midY - lift)
    }

    /// The shortcuts over the veiled page: the panel rises out of the jewel, which wears a cross
    /// to close it.
    @ViewBuilder
    private func shortcuts(in size: CGSize) -> some View {
        let jewel = jewelCenter(in: size)
        let top: CGFloat = jewel.y - HomeJewel.size / 2
        let lift: CGFloat = max(size.height - top + 14, 0)
        let anchor = UnitPoint(x: jewel.x / max(size.width, 1), y: jewel.y / max(size.height, 1))
        tone.canvas.opacity(0.55)
            .ignoresSafeArea()
            .onTapGesture { closeShortcuts() }
            .transition(.opacity)
            .accessibilityHidden(true)
        HomeShortcutsPanel(tone: tone, next: upNext.level, underWay: upNext.inProgress, shortcuts: shortcutList,
                           playRival: { level in playRival(level) }, close: closeShortcuts)
            .padding(.horizontal, 16)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, lift)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.2, anchor: anchor).combined(with: .opacity))
            .zIndex(2)
        HomeJewel(tone: tone, upNext: upNext, face: .open, tap: closeShortcuts)
            .position(jewel)
            .transition(.opacity)
            .zIndex(3)
    }

    /// The jewel's note, just above it.
    private func jewelNote(in size: CGSize) -> some View {
        let top: CGFloat = jewelCenter(in: size).y - HomeJewel.size / 2
        let lift: CGFloat = max(size.height - top + 12, 0)
        return HomeJewelTip(tone: tone) {
            withAnimation(.easeOut(duration: 0.25)) { jewelTip = false }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, lift)
        .transition(.offset(y: 10).combined(with: .opacity))
        .zIndex(1)
    }

    /// CI's pictures open the shortcuts with `-showcaseShortcuts YES`. Otherwise, once a game
    /// has been played, a note says once that the jewel holds them.
    private func introduceJewel() async {
        if UserDefaults.standard.bool(forKey: "showcaseShortcuts") {
            try? await Task.sleep(for: .seconds(1.6))
            openShortcuts()
            return
        }
        guard !Welcome.isUnderTest, !vault.games.isEmpty, TipBook.canShow(.jewelShortcuts) else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled, !veiled, TipBook.canShow(.jewelShortcuts) else { return }
        TipBook.markSeen(.jewelShortcuts)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { jewelTip = true }
        try? await Task.sleep(for: .seconds(7))
        withAnimation(.easeOut(duration: 0.3)) { jewelTip = false }
    }

    // MARK: You

    private func scrolled(to y: CGFloat) {
        scroll.y = y
        guard you == nil else { return }
        if #available(iOS 18.0, *) {
            // Armed while the finger holds the page past the mark; it opens on release.
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
    private func youPanel(_ origin: YouOrigin) -> some View {
        let fromTop = origin == .top
        tone.canvas.opacity(0.7)
            .ignoresSafeArea()
            .onTapGesture { closeYou() }
            .transition(.opacity)
            .accessibilityHidden(true)
        HomeYouPanel(tone: tone, piecesLine: piecesLine, gamesLine: gamesLine, actions: actions, fromTop: fromTop, close: closeYou)
            .padding(.horizontal, 16)
            .padding(.top, fromTop ? 6 : 0)
            .padding(.bottom, fromTop ? 0 : 10)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: fromTop ? .top : .bottom)
            .transition(reduceMotion ? .opacity : .move(edge: fromTop ? .top : .bottom).combined(with: .opacity))
            .zIndex(2)
    }
}

// MARK: - The board home

extension HomeView {
    /// How the sheet moves between its rests: a soft spring, or a fade for reduced motion.
    private var sheetSpring: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.46, dampingFraction: 0.8)
    }

    /// The board home: the 3D board fills the top, the greeting floats over it, and the sheet
    /// rises from the foot. The board turns and steps back as the sheet comes up, and steps in
    /// when it folds down to play.
    @ViewBuilder
    func sheetHome(_ geo: GeometryProxy) -> some View {
        let safeTop: CGFloat = geo.safeAreaInsets.top
        let safeBottom: CGFloat = geo.safeAreaInsets.bottom
        let total: CGFloat = geo.size.height + safeTop + safeBottom
        let metrics = HomeSheetMetrics(total: total, safeTop: safeTop, safeBottom: safeBottom)
        let height: CGFloat = metrics.height(sheetDetent, drag: sheetDrag)
        let lift: CGFloat = metrics.progress(height)
        let upNext = self.upNext
        ZStack(alignment: .top) {
            sheetBoard(upNext, width: geo.size.width, metrics: metrics, lift: lift)
            sheetGreeting(lift: lift)
                .padding(.top, safeTop + 4)
                .padding(.horizontal, 16)
            sheetPanel(upNext, metrics: metrics, height: height, lift: lift)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(edges: .top)
        // With the shortcuts open the home steps back, out of focus.
        .blur(radius: veiled ? 12 : 0)
        .accessibilityHidden(veiled)
        .allowsHitTesting(!veiled)
    }

    /// The board, as tall as two thirds of the screen. It rises with the sheet so it stays in
    /// sight, steps back and dims a little as the sheet covers it, and leans in when folded.
    private func sheetBoard(_ upNext: HomeUpNext, width: CGFloat, metrics: HomeSheetMetrics, lift: CGFloat) -> some View {
        let total: CGFloat = metrics.total
        let boardHeight: CGFloat = total * 0.68
        let rise: CGFloat = -lift * total * 0.17
        let scale: CGFloat = 1.06 - 0.08 * lift
        let dim: Double = Double(lift) * 0.45
        let leaning: Bool = upNext.inProgress && upNext.yourMove
        return HomeSheetScene(look: look, tone: tone, pieces: match.game.pieces.map(\.piece),
                              black: upNext.playerColor == .black, rival: upNext.rival, leaning: leaning, lift: lift)
            .overlay { HomeSheetShade(tone: tone) }
            .overlay { HomeRivalPresence(rival: upNext.rival, leaning: leaning, scroll: scroll) }
            .overlay { tone.canvas.opacity(dim).allowsHitTesting(false) }
            .frame(width: width, height: boardHeight)
            .scaleEffect(scale, anchor: .top)
            .offset(y: rise)
            .contentShape(Rectangle())
            .onTapGesture { primary(upNext) }
            .gesture(sheetPull(on: .board, metrics: metrics))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(upNext.inProgress ? "Your game against \(upNext.rival.name)" : "Next game: \(upNext.rival.name)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.magicTap) { primary(upNext) }
    }

    /// Hello, the streak and the level, over the board. It fades as the sheet rises over it.
    private func sheetGreeting(lift: CGFloat) -> some View {
        let day = dailyState
        let ladder = HomeLadder(games: vault.games)
        return HomeGreeting(name: playerName, streak: day.streak, doneToday: day.doneToday,
                            streakDetail: day.detail, level: ladder.yourRating, tone: tone,
                            openStreak: actions.dailyMove, openLevel: { pickTab(.today) })
            .opacity(Double(1 - lift * 0.7))
            .offset(y: -lift * 10)
    }

    /// The glass sheet. Folded, it is one strip with the game; open, it holds the tab's page
    /// and the tabs at its foot. It runs past the screen's foot, so only its top corners show.
    private func sheetPanel(_ upNext: HomeUpNext, metrics: HomeSheetMetrics, height: CGFloat, lift: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        let opened: CGFloat = height - metrics.lowest
        let stripShown: Double = Double(1 - min(max(opened / 70, 0), 1))
        let pageShown: Double = Double(min(max((opened - 30) / 90, 0), 1))
        let overhang: CGFloat = 40
        return VStack(spacing: 0) {
            HomeSheetGrabber(tone: tone, dragging: sheetDragging)
            ZStack(alignment: .top) {
                sheetOpen(upNext, bottom: metrics.safeBottom)
                    .opacity(pageShown)
                    .allowsHitTesting(pageShown > 0.5)
                HomeSheetStrip(upNext: upNext, tone: tone) { primary(upNext) }
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                    .opacity(stripShown)
                    .offset(y: (1 - CGFloat(stripShown)) * 16)
                    .allowsHitTesting(stripShown > 0.5)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.bottom, overhang)
        .frame(height: height + overhang)
        .frame(maxWidth: .infinity)
        .homePane(shape, tone: tone)
        .shadow(color: .black.opacity(0.35), radius: 24, y: -6)
        .offset(y: overhang)
        .gesture(sheetPull(on: .sheet, metrics: metrics))
    }

    /// The open sheet: the tab's name, its page, and the tabs with the gold knight.
    private func sheetOpen(_ upNext: HomeUpNext, bottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            sheetHeader
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            ScrollView(.vertical) {
                sheetPage(upNext)
                    .id(sheetTab)
                    .transition(.homePage(forward: sheetForward, reduceMotion: reduceMotion))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                       .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            HomeSheetTabBar(tone: tone, selection: sheetTab, pick: pickTab) {
                HomeJewel(tone: tone, upNext: upNext, face: .rest, tap: { primary(upNext) }, hold: openShortcuts)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.root))
                    } action: { frame in
                        dockBar = frame
                    }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, max(bottom, 12))
        }
    }

    /// The tab's name, rolling over to the next as the tab changes.
    private var sheetHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(sheetTab.title)
                .font(.app(.title, weight: .semibold))
                .foregroundStyle(tone.ink)
                .tracking(-0.6)
                .id(sheetTab)
                .transition(.homePage(forward: sheetForward, reduceMotion: reduceMotion))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                withAnimation(sheetSpring) {
                    sheetDetent = sheetDetent == .full ? .half : .full
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.app(.footnote, weight: .bold))
                    .foregroundStyle(tone.ink2)
                    .rotationEffect(.degrees(sheetDetent == .full ? 180 : 0))
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HomePressStyle())
            .accessibilityLabel(sheetDetent == .full ? "Show more board" : "Show more")
        }
        .frame(minHeight: 40)
    }

    @ViewBuilder
    private func sheetPage(_ upNext: HomeUpNext) -> some View {
        switch sheetTab {
        case .today: sheetToday(upNext)
        case .learn: sheetLearn
        case .army: sheetArmy
        case .you: sheetYou
        }
    }

    /// Today: your games going, a person to play, Today's Move and the coach, the rivals.
    private func sheetToday(_ upNext: HomeUpNext) -> some View {
        let day = dailyState
        let ladder = HomeLadder(games: vault.games)
        return VStack(alignment: .leading, spacing: Self.gap) {
            currentGames(upNext)
                .homeRise(0)
            playPerson()
                .homeRise(1)
            HStack(alignment: .top, spacing: Self.gap) {
                HomeDailyTile(puzzle: dailyPuzzle, daily: day, tone: tone, pieceTheme: pieceTheme,
                              solve: actions.dailyMove)
                HomeCoachTile(plan: plan, trainedToday: training.trainedToday, progress: training.rankProgress,
                              tone: tone, start: actions.trainToday, train: actions.train)
            }
            .fixedSize(horizontal: false, vertical: true)
            .homeRise(2)
            if HomeNoticeCard.shows(day) {
                HomeNoticeCard(daily: day, tone: tone, remind: answerReminder)
                    .transition(.opacity)
                    .homeRise(3)
            }
            HomeLadderTile(ladder: ladder, tone: tone, play: { level in actions.playRival(level) })
                .padding(.top, 4)
                .homeRise(4)
        }
    }

    /// Learn: every way to get better, in one card.
    private var sheetLearn: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            sheetCard {
                HomeLinkRow(glyph: Glyphs.coach, title: "Train with Coach Leo", detail: "Lessons, drills and today's session", tone: tone, action: actions.train)
                    .homeRise(0)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.today, title: "Today's Move", detail: "The puzzle of the day", tone: tone, action: actions.dailyMove)
                    .homeRise(1)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.puzzles, title: "Puzzles", detail: "Rated puzzles at your level", tone: tone, action: actions.puzzles)
                    .homeRise(2)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.games, title: "Rewind", detail: gamesLine, tone: tone, action: actions.rewind)
                    .homeRise(3)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.analyze, title: "Analyze", detail: "Study any position with the engine", tone: tone, action: actions.analyze)
                    .homeRise(4)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.scan, title: "Scan a board", detail: "Read a real board with the camera", tone: tone, action: actions.scan)
                    .homeRise(5)
            }
        }
    }

    /// Army: your pieces with memory, and the games they played.
    private var sheetArmy: some View {
        let played = vault.games
        return VStack(alignment: .leading, spacing: Self.gap) {
            sheetCard {
                HomeLinkRow(glyph: Glyphs.army, title: "Your pieces", detail: piecesLine, tone: tone, action: actions.army)
                    .homeRise(0)
            }
            if !played.isEmpty {
                HomeGamesTile(rows: HomeGameRow.rows(played), total: played.count,
                              week: HomeGameRow.thisWeek(played), tone: tone, openAll: actions.rewind)
                    .homeRise(1)
            }
        }
    }

    /// You: your games, Settings and Pro.
    private var sheetYou: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            sheetCard {
                HomeLinkRow(glyph: Glyphs.games, title: "Your games", detail: gamesLine, tone: tone, action: actions.rewind)
                    .homeRise(0)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.settings, title: "Settings", detail: "Board look, sound, hints", tone: tone, action: actions.settings)
                    .homeRise(1)
                if let premium = actions.premium {
                    HomeHairline(tone: tone)
                    HomeLinkRow(glyph: Glyphs.king, title: "Chess Game Killer Pro", detail: "Everything, with no limits", tone: tone, action: premium)
                        .homeRise(2)
                }
            }
        }
    }

    /// A card of rows on the sheet.
    private func sheetCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.horizontal, HomeMetrics.inset)
        .padding(.vertical, 2)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous), tone: tone)
    }

    /// A tab picked: its page slides in from that side. From the folded strip, the sheet rises.
    private func pickTab(_ tab: HomeSheetTab) {
        let forward: Bool = tab.rawValue >= sheetTab.rawValue
        sheetForward = forward
        let spring: Animation = reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82)
        withAnimation(spring) {
            sheetTab = tab
            if sheetDetent == .board { sheetDetent = .half }
        }
    }

    /// Where a drag starts: on the board above the sheet, or on the sheet.
    private enum SheetGrip { case board, sheet }

    /// Dragging the sheet (or the board above it) moves the sheet with the finger; on release
    /// it springs to the rest nearest where the flick was heading.
    private func sheetPull(on grip: SheetGrip, metrics: HomeSheetMetrics) -> some Gesture {
        DragGesture(minimumDistance: grip == .board ? 14 : 6, coordinateSpace: .global)
            .onChanged { value in
                if !sheetDragging { sheetDragging = true }
                sheetDrag = value.translation.height
            }
            .onEnded { value in
                let start: CGFloat = metrics.height(of: sheetDetent)
                let landing: CGFloat = start - value.predictedEndTranslation.height
                let next: HomeSheetDetent = Self.detent(from: sheetDetent, landing: landing, start: start, metrics: metrics)
                withAnimation(sheetSpring) {
                    sheetDetent = next
                    sheetDrag = 0
                    sheetDragging = false
                }
            }
    }

    /// The rest a flick lands on: the nearest to where it was heading, one step at least
    /// when it was a real flick.
    private static func detent(from current: HomeSheetDetent, landing: CGFloat, start: CGFloat,
                               metrics: HomeSheetMetrics) -> HomeSheetDetent {
        let nearest: HomeSheetDetent = metrics.nearest(to: landing)
        if nearest != current { return nearest }
        let moved: CGFloat = landing - start
        if moved > 120, let up = HomeSheetDetent(rawValue: current.rawValue + 1) { return up }
        if moved < -120, let down = HomeSheetDetent(rawValue: current.rawValue - 1) { return down }
        return current
    }
}

/// The room behind the home: its own dark, a pool of warm light where the board window
/// sits, and a breath of the pieces' gold lower down, so the glass tiles have light to catch.
struct HomeBackdrop: View {
    let tone: HomeTone

    var body: some View {
        ZStack {
            tone.canvas
            RadialGradient(colors: [tone.pool.opacity(0.5), tone.canvas.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.16), startRadius: 0, endRadius: 440)
            RadialGradient(colors: [tone.metal.opacity(0.08), tone.canvas.opacity(0)],
                           center: UnitPoint(x: 0.92, y: 0.62), startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
