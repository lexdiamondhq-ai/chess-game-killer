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
    /// Opens Analyze on this position, ready to play through.
    var analyzePosition: (String) -> Void = { _ in }
    var train: () -> Void = {}
    /// Opens Learn on its Chess DNA page.
    var chessDNA: () -> Void = {}
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
/// a tap plays, a hold opens its shortcuts (the five rivals, then Online, a friend, Today's
/// Move, Puzzles, Analyze, the coach and your games). Your pieces, your games and Settings are
/// in the You panel, from the dock or by pulling the page down.
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
    /// The rivals' hall is open, on its rival and whether its film plays first. One value, so the
    /// hall always opens on the rival asked for: with the rival kept apart from the open switch,
    /// the hall could read the rival from before and open on the Cub (Alex, 2026-11-10: "When I
    /// hit play it goes to cub rather than the rival I selected").
    @State private var hall: HallVisit?
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
    /// Your finest move of the week for Today, read from your games once rather than on every redraw.
    @State private var finestMove: HomeFinestMove?
    /// Your Chess DNA for the Home card, read from your games once rather than on every redraw.
    @State private var dna: ChessDNA?
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
    /// The board home's room: Light, Middle or Dark (the tiles home stays dark).
    @AppStorage(HomeToneMode.key) private var toneMode = HomeToneMode.defaultMode
    /// The stage home: dark, the board on a lit stage, a deck of cards (Settings can turn it off).
    @AppStorage(HomeStageLayout.key) private var stageOn = HomeStageLayout.defaultOn
    /// Where the sheet rests, and how far a finger has it from there. The drag springs back by
    /// itself when a pull is cut short (an alert, a call), so the sheet never parks between rests.
    @State private var sheetDetent: HomeSheetDetent = .half
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.46, dampingFraction: 0.8)))
    private var sheetDrag: CGFloat = 0
    private var sheetDragging: Bool { sheetDrag != 0 }
    /// The sheet's tab, and whether the last pick moved right (its page comes in from the right).
    @State private var sheetTab: HomeSheetTab = .today
    @State private var sheetForward = true
    /// Back from a game, the sheet starts folded like the game's and rises to here.
    private let sheetRest: HomeSheetDetent
    private let rises: Bool
    /// The rise from the game has played (once per return).
    @State private var rose = false
    /// The game is starting or resuming: one start per visit, however many taps land.
    @State private var launched = false
    /// The sheet is folding down before the game opens; the home takes no more taps.
    @State private var pushing = false
    /// Tells the app which tab is showing, so a redraw of the home (a new look) keeps it.
    private let onTab: (HomeSheetTab) -> Void

    enum YouOrigin { case top, bottom }

    /// How far the page must be pulled down to open the You panel.
    static let pullToOpen: CGFloat = 86
    private static let space = "home-scroll"
    /// The home's own space, where the dock says where its jewel is.
    static let root = "home-root"
    /// The gap between tiles, and between the tiles and the screen's edge.
    static let gap: CGFloat = 10

    /// `rises`: the player is back from a game, so the sheet comes up out of the game's.
    init(match: MatchController, theme: BoardTheme, actions: HomeActions, showsYou: Bool = false,
         showsShortcuts: Bool = false, sheet: HomeSheetDetent = .half, tab: HomeSheetTab = .today,
         rises: Bool = false, onTab: @escaping (HomeSheetTab) -> Void = { _ in }) {
        self.match = match
        self.theme = theme
        self.actions = actions
        self.sheetRest = sheet
        self.rises = rises
        self.onTab = onTab
        _you = State(initialValue: showsYou ? .bottom : nil)
        _shortcutsOpen = State(initialValue: showsShortcuts)
        // CI's pictures open the home folded with `-showcaseHomeSheet board`; a normal launch never passes it.
        let shown: HomeSheetDetent? = UserDefaults.standard.string(forKey: "showcaseHomeSheet") == "board" ? .board : nil
        _sheetDetent = State(initialValue: shown ?? (rises ? .board : sheet))
        _sheetTab = State(initialValue: tab)
    }

    // MARK: Reading

    private var look: SculptedLook { theme.sculptedLook ?? .gilded }
    private var tone: HomeTone { .of(look, mode: (boardSheet || stageOn) ? toneMode : .dark) }
    /// The pieces on the small boards match the board in the window.
    private var pieceTheme: BoardTheme { theme.sculptedLook == nil ? .named(.gilded) : theme }

    /// The next game is always against a rival (Alex, 2026-11-09: "replace that card with the
    /// next Rival opponent").
    private var upNext: HomeUpNext {
        HomeUpNext.make(match: match, side: side, level: nextLevel,
                        timeControl: timeControl, hasPlayed: !vault.games.isEmpty)
    }

    /// The rival up next: the one you played last, while it's open to you; otherwise the first
    /// rival on the ladder you haven't beaten (Alex, 2026-11-08: each rival waits until the one
    /// before is beaten).
    private var nextLevel: MatchController.Level? {
        let ladder = RivalLadder()
        if let stored = storedLevel.flatMap(MatchController.Level.init(rawValue:)) {
            return ladder.isOpen(stored) ? stored : ladder.current
        }
        return vault.games.isEmpty ? nil : ladder.current
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

                if stageOn {
                    stageHome()
                        .blur(radius: veiled ? 12 : 0)
                        .accessibilityHidden(veiled)
                        .allowsHitTesting(!veiled)
                } else if boardSheet {
                    sheetHome(geo)
                } else {
                    page(safeTop: safeTop)

                    HomeTopEdge(scroll: scroll, tone: tone, start: 0, height: safeTop + 34)
                        .ignoresSafeArea(edges: .top)

                    HomePullCue(scroll: scroll, tone: tone, threshold: Self.pullToOpen, armed: pullArmed)
                        .padding(.top, 6)
                }

                if jewelTip, !stageOn, !shortcutsOpen, you == nil {
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
        // The window's own light (status bar, system sheets) is set by the app, which knows when
        // the welcome is up and waits for the fade from a game to finish.
        .environment(\.colorScheme, tone.scheme)
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
        .task(id: notesKey) { await readToday() }
    }

    /// Changes whenever today's plan would: a session done, a new day, a game saved.
    private var planKey: String {
        "\(training.progress.sessionsDone) \(training.progress.xp) \(training.trainedToday) \(Trainer.dayString(.now)) \(vault.games.count)"
    }

    /// Changes whenever the finest move could: a game saved or graded, a new day.
    private var notesKey: String {
        // The newest game's grades land after it ends: count them too.
        let graded: Int = vault.games.first?.moments.count ?? 0
        return "\(vault.games.count) \(graded) \(Trainer.dayString(.now))"
    }

    /// Reads the games off the main thread for the week's finest move and your Chess DNA.
    private func readToday() async {
        let games: [SavedGame] = vault.games
        finestMove = await Task.detached(priority: .utility) { HomeFinestMove.pick(games: games) }.value
        let stats = puzzles.themeStats
        let played = puzzles.progress.played
        dna = await Task.detached(priority: .utility) {
            ChessDNA.make(games: games, puzzleStats: stats, puzzlesPlayed: played)
        }.value
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
        state.restDayUsed = daily.restDayUsed
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
        // A double tap, or the strip's Play during the fold, must not start the game twice.
        guard !launched else { return }
        launched = true
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

    /// Rooms on the Aurora home: New game and Your games only (Alex, 2026-11-11). New game is the
    /// one door to every game: a rival, a friend or someone online. The rivals live on the Next
    /// game card. Elsewhere: Online and A friend (when the app has them), a new game, the rivals
    /// and your games.
    private var shortcutList: [HomeShortcut] {
        let waiting: Int = challenges?.onlineWaiting ?? 0
        let kinds: [HomeShortcutKind] = stageOn
            ? HomeShortcutKind.rooms
            : HomeShortcutKind.list(online: challenges != nil)
        return kinds.map { kind in
            HomeShortcut(kind: kind, live: kind == .online && waiting > 0) { open(kind) }
        }
    }

    /// Where a shortcut goes.
    private func open(_ kind: HomeShortcutKind) {
        switch kind {
        case .online: challenges?.playOnline()
        case .friend: challenges?.compose()
        case .newGame: secondary(upNext)
        case .rivals: hall = HallVisit(start: nil, intro: false)
        case .games: actions.rewind()
        }
    }

    /// Where the jewel stands, in the home's space: the middle of the dock's bar, a little
    /// above it at rest. Before the dock has been measured, where it would be.
    private func jewelCenter(in size: CGSize) -> CGPoint {
        let lift: CGFloat = (windowGone || boardSheet || stageOn) ? 0 : HomeDock.raise
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
                           playRival: { level in playRival(level) }, close: closeShortcuts, asRooms: stageOn)
            .padding(.horizontal, 16)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // Rooms on the Aurora home rise from the bottom bar; elsewhere out of the jewel.
            .padding(.bottom, stageOn ? 96 : lift)
            .transition(reduceMotion ? .opacity
                        : stageOn ? .move(edge: .bottom).combined(with: .opacity)
                        : .scale(scale: 0.2, anchor: anchor).combined(with: .opacity))
            .zIndex(2)
        if !stageOn {
            // The jewel wears a cross to close the panel. Rooms on the Aurora home close by a
            // tap outside or a drag down instead (Alex, 2026-11-07: no X).
            HomeJewel(tone: tone, upNext: upNext, face: .open, tap: closeShortcuts)
                .position(jewel)
                .transition(.opacity)
                .zIndex(3)
        }
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

    /// Friends in the You panel opens Play a friend, where the player's people are.
    private var openFriends: (() -> Void)? {
        guard let challenges else { return nil }
        return { challenges.compose() }
    }

    /// Under Friends in the You panel: the player's username and how many people they have.
    private var friendsLine: String {
        guard let friends = challenges?.friends else { return "" }
        let count = friends.people.count
        guard count > 0 else { return "Add people and challenge them" }
        let people = count == 1 ? "1 friend" : "\(count) friends"
        return friends.you.map { "@\($0.username) · \(people)" } ?? people
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
        HomeYouPanel(tone: tone, piecesLine: piecesLine, gamesLine: gamesLine, actions: actions, fromTop: fromTop, close: closeYou,
                     friends: openFriends, friendsLine: friendsLine)
            .padding(.horizontal, 16)
            .padding(.top, fromTop ? 6 : 0)
            .padding(.bottom, fromTop ? 0 : 10)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: fromTop ? .top : .bottom)
            .transition(reduceMotion ? .opacity : .move(edge: fromTop ? .top : .bottom).combined(with: .opacity))
            .zIndex(2)
    }
}

// MARK: - The stage home

extension HomeView {
    /// The stage home: the same game, cards and doors as the other homes, laid out on a dark stage.
    func stageHome() -> some View {
        let upNext = self.upNext
        let puzzle: HomePuzzle? = dailyPuzzle
        let info = HomeStageInfo(upNext: upNext, day: dailyState, rating: HomeLadder(games: vault.games).yourRating,
                                 rankNumber: training.rankNumber, plan: plan, trainedToday: training.trainedToday,
                                 masterpiece: HomeMasterpiece.of(), name: playerName,
                                 gameFEN: match.game.fen, todayFEN: puzzle?.fen, todaySolver: puzzle?.solver,
                                 pieceTheme: pieceTheme)
        let stageActions = HomeStageActions(
            play: { playNext(upNext) },
            change: { secondary(upNext) },
            dailyMove: actions.dailyMove,
            coach: {
                if let plan { actions.trainToday(plan) } else { actions.train() }
            },
            learn: actions.train,
            analyze: actions.analyze,
            analyzePosition: actions.analyzePosition,
            you: { openYou(.bottom) },
            rooms: openShortcuts)
        let auroraInfo = HomeAuroraInfo(stage: info, games: currentGameList(upNext), look: look,
                                        pieces: match.game.pieces.map(\.piece), finest: finestMove, dna: dna)
        let auroraActions = HomeAuroraActions(stage: stageActions, open: { game in
            if let friend = game.friendGame {
                challenges?.play(friend)
            } else {
                actions.resume()
            }
        }, playRival: { level in playOtherRival(level) }, options: { level in actions.playRival(level) }, rivals: { level in
            hall = HallVisit(start: level, intro: false)
        }, chessDNA: actions.chessDNA, puzzles: actions.puzzles, replay: { id in
            if let game = vault.game(id) { actions.openGame(game) }
        }, army: actions.army, armyQuest: { level in playOtherRival(level) })
        return HomeAuroraView(tone: tone, info: auroraInfo, actions: auroraActions)
            .task {
                // Keeps whose move it is in games with people, and how many wait online, up to
                // date while Home is showing. The earlier homes did this from their Play tile;
                // this home has no such tile, so its "Your move" cards went stale (audit, 2026-11-11).
                guard let challenges else { return }
                while !Task.isCancelled {
                    await challenges.refreshGames()
                    await challenges.refreshOnlineCount()
                    try? await Task.sleep(for: .seconds(ChallengeCenter.refreshInterval))
                }
            }
            // A link from outside (a friend's challenge, Today's Move) brings its own screen
            // forward: the hall steps aside for it.
            .onReceive(NotificationCenter.default.publisher(for: ScreenCovers.closeAll)) { _ in hall = nil }
            .fullScreenCover(item: $hall) { visit in
                RivalsHall(start: visit.start, intro: visit.intro, begin: { level in
                    // The film's last frame gives way to the game: the hall closes at once.
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { hall = nil }
                    playRival(level)
                }, close: { hall = nil })
            }
    }

    /// Play on the next game. Every time you face a rival, its welcome film plays first and its
    /// Begin starts the game (Alex, 2026-11-09: "when I hit play on this rival, I should see the
    /// intro video"). A swipe down on the film goes back.
    private func playNext(_ upNext: HomeUpNext) {
        guard !upNext.inProgress else {
            primary(upNext)
            return
        }
        showFilm(upNext.level)
    }

    /// Play on another rival's page of the Up next card: its film first too. During a game the
    /// New Game sheet opens on that rival instead, as before.
    private func playOtherRival(_ level: MatchController.Level) {
        guard !upNext.inProgress else {
            playRival(level)
            return
        }
        showFilm(level)
    }

    private func showFilm(_ level: MatchController.Level) {
        hall = HallVisit(start: level, intro: true)
    }
}

/// One visit to the rivals' hall: the rival it opens on (nil: the one up next) and whether that
/// rival's welcome film plays first.
private struct HallVisit: Identifiable {
    let id = UUID()
    let start: MatchController.Level?
    let intro: Bool
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
            if tone.scheme == .light {
                greetingBacking(height: safeTop + 110, lift: lift)
            }
            sheetGreeting(lift: lift)
                .padding(.top, safeTop + 4)
                .padding(.horizontal, 16)
            pullRow(upNext, metrics: metrics, height: height, lift: lift)
            sheetPanel(upNext, metrics: metrics, height: height, lift: lift)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(edges: .top)
        // With the shortcuts open the home steps back, out of focus.
        .blur(radius: veiled ? 12 : 0)
        .accessibilityHidden(veiled)
        .allowsHitTesting(!veiled && !pushing)
        .onAppear(perform: riseFromGame)
    }

    /// Pulled down by its grabber, the sheet leaves the board with a row of quick ways in just
    /// above the strip. They fade as soon as the sheet starts back up.
    private func pullRow(_ upNext: HomeUpNext, metrics: HomeSheetMetrics, height: CGFloat, lift: CGFloat) -> some View {
        let shown: Double = Double(1 - min(max(lift * 4, 0), 1))
        var items: [HomePullRow.Item] = [
            .init(id: "new", glyph: Glyphs.play, title: "New game") { secondary(upNext) },
        ]
        if let challenges {
            items.append(.init(id: "friend", glyph: Glyphs.challenge, title: "A friend") { challenges.compose() })
        }
        items.append(.init(id: "today", glyph: Glyphs.today, title: "Today's Move") { actions.dailyMove() })
        items.append(.init(id: "analyze", glyph: Glyphs.analyze, title: "Analyze") { actions.analyze() })
        return HomePullRow(items: items, tone: tone)
            .padding(.bottom, height + 24)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .opacity(shown)
            .offset(y: (1 - CGFloat(shown)) * 12)
            .allowsHitTesting(shown > 0.6)
            .accessibilityHidden(shown < 0.6)
    }

    /// Back from a game: the folded sheet, where the game's was, rises to its rest.
    private func riseFromGame() {
        guard rises, !rose, sheetDetent == .board, sheetRest != .board else { return }
        rose = true
        let rise: Animation = reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.8).delay(0.12)
        withAnimation(rise) { sheetDetent = sheetRest }
    }

    /// Push down to play: the sheet folds into its strip, then the game opens.
    private func pushDownToPlay(_ upNext: HomeUpNext) {
        guard sheetDetent != .board, !reduceMotion else {
            primary(upNext)
            return
        }
        pushing = true
        withAnimation(sheetSpring) { sheetDetent = .board }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            primary(upNext)
        }
    }

    /// A tap on the grabber: folded or halfway goes a step up; all the way up comes back halfway.
    private func stepSheet() {
        let next: HomeSheetDetent
        switch sheetDetent {
        case .board: next = .half
        case .half: next = .full
        case .full: next = .half
        }
        withAnimation(sheetSpring) { sheetDetent = next }
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
            .onTapGesture { pushDownToPlay(upNext) }
            .gesture(sheetPull(on: .board, metrics: metrics))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(upNext.inProgress ? "Your game against \(upNext.rival.name)" : "Next game: \(upNext.rival.name)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.magicTap) { primary(upNext) }
    }

    /// In Light and Middle the greeting's dark ink needs the room behind it once the board
    /// rises under it (the board's own top fade rises with the board). Folded, the board's
    /// fade is enough, so this comes in with the sheet.
    private func greetingBacking(height: CGFloat, lift: CGFloat) -> some View {
        let shown: Double = Double(min(lift * 2, 1))
        // Firm behind the greeting's line, then fading out under it.
        return LinearGradient(stops: [.init(color: tone.canvas.opacity(0.92), location: 0),
                                      .init(color: tone.canvas.opacity(0.82), location: 0.6),
                                      .init(color: tone.canvas.opacity(0), location: 1)],
                              startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .opacity(shown)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Hello, the streak and the level, over the board. It fades as the sheet rises over it.
    private func sheetGreeting(lift: CGFloat) -> some View {
        let day = dailyState
        let ladder = HomeLadder(games: vault.games)
        return HomeGreeting(name: playerName, streak: day.streak, doneToday: day.doneToday,
                            streakDetail: day.detail, level: ladder.yourRating, tone: tone,
                            openStreak: actions.dailyMove, openLevel: { pickTab(.today) })
            // Stays readable over the pieces; the sheet itself covers it when it comes all the way up.
            .opacity(Double(1 - lift * 0.15))
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
                .gesture(sheetPull(on: .sheet, metrics: metrics))
                .onTapGesture { stepSheet() }
            ZStack(alignment: .top) {
                sheetOpen(upNext, metrics: metrics)
                    .opacity(pageShown)
                    // A pull that started here keeps its grip while the page fades.
                    .allowsHitTesting(pageShown > 0.5 || sheetDragging)
                HomeSheetStrip(upNext: upNext, tone: tone) { primary(upNext) }
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                    .contentShape(Rectangle())
                    .gesture(sheetPull(on: .sheet, metrics: metrics))
                    .opacity(stripShown)
                    .offset(y: (1 - CGFloat(stripShown)) * 16)
                    .allowsHitTesting(stripShown > 0.5 || sheetDragging)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.bottom, overhang)
        .frame(height: height + overhang)
        .frame(maxWidth: .infinity)
        .homePane(shape, tone: tone)
        .shadow(color: .black.opacity(tone.shadow), radius: 24, y: -6)
        .offset(y: overhang)
    }

    /// The open sheet: the tab's name, its page, and the tabs with the gold knight. The sheet
    /// moves by its grabber and its header; the page under them scrolls.
    private func sheetOpen(_ upNext: HomeUpNext, metrics: HomeSheetMetrics) -> some View {
        VStack(spacing: 0) {
            sheetHeader
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .gesture(sheetPull(on: .sheet, metrics: metrics))
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id(Self.sheetTop)
                        // The page going and the page coming share one place while they cross.
                        ZStack(alignment: .top) {
                            sheetPage(upNext)
                                .id(sheetTab)
                                .transition(.homePage(forward: sheetForward, reduceMotion: reduceMotion))
                        }
                    }
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
                // Every tab opens at its top, wherever the last one was scrolled to.
                .onChange(of: sheetTab) { _, _ in
                    reader.scrollTo(Self.sheetTop, anchor: .top)
                }
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
            .padding(.bottom, max(metrics.safeBottom, 12))
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
        case .you: sheetYou
        }
    }

    /// Today: your games going, a person to play, Analyze, Today's Move and the coach, the
    /// day's masterpiece, your army and the rivals.
    private func sheetToday(_ upNext: HomeUpNext) -> some View {
        let day = dailyState
        let ladder = HomeLadder(games: vault.games)
        return VStack(alignment: .leading, spacing: Self.gap) {
            currentGames(upNext)
                .homeRise(0)
            playPerson()
                .homeRise(1)
            HomeAnalyzeTile(tone: tone, analyze: actions.analyze)
                .homeRise(2)
            HStack(alignment: .top, spacing: Self.gap) {
                HomeDailyTile(puzzle: dailyPuzzle, daily: day, tone: tone, pieceTheme: pieceTheme,
                              solve: actions.dailyMove)
                HomeCoachTile(plan: plan, trainedToday: training.trainedToday, progress: training.rankProgress,
                              tone: tone, start: actions.trainToday, train: actions.train)
            }
            .fixedSize(horizontal: false, vertical: true)
            .homeRise(3)
            if HomeNoticeCard.shows(day) {
                HomeNoticeCard(daily: day, tone: tone, remind: answerReminder)
                    .transition(.opacity)
                    .homeRise(4)
            }
            if let masterpiece = HomeMasterpiece.of() {
                HomeMasterpieceTile(masterpiece: masterpiece, tone: tone, pieceTheme: pieceTheme,
                                    open: actions.analyzePosition)
                    .homeRise(5)
            }
            HomeArmyTile(army: army, color: upNext.playerColor, pieceTheme: pieceTheme, tone: tone, open: actions.army)
                .homeRise(6)
            HomeLadderTile(ladder: ladder, tone: tone, play: { level in actions.playRival(level) })
                .padding(.top, 4)
                .homeRise(7)
        }
    }

    /// Learn: every way to get better, in one card, and your games to look back on.
    private var sheetLearn: some View {
        let played = vault.games
        return VStack(alignment: .leading, spacing: Self.gap) {
            sheetCard {
                HomeLinkRow(glyph: Glyphs.coach, title: "Train with Coach Leo", detail: "Lessons, drills and today's session", tone: tone, action: actions.train)
                    .homeZoomSource(.coach)
                    .homeRise(0)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.today, title: "Today's Move", detail: "The puzzle of the day", tone: tone, action: actions.dailyMove)
                    .homeZoomSource(.daily)
                    .homeRise(1)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.puzzles, title: "Puzzles", detail: "Rated puzzles at your level", tone: tone, action: actions.puzzles)
                    .homeZoomSource(.puzzles)
                    .homeRise(2)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.games, title: "Rewind", detail: gamesLine, tone: tone, action: actions.rewind)
                    .homeZoomSource(.games)
                    .homeRise(3)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.analyze, title: "Analyze", detail: HomeAnalyzeTile.line, tone: tone, action: actions.analyze)
                    .homeRise(4)
            }
            if !played.isEmpty {
                HomeGamesTile(rows: HomeGameRow.rows(played), total: played.count,
                              week: HomeGameRow.thisWeek(played), tone: tone, openAll: actions.rewind)
                    .homeRise(5)
            }
        }
    }

    /// You: the home's colors, your games, Settings and Premium.
    private var sheetYou: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            sheetCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Colors")
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(tone.ink)
                    HomeToneSwitch(mode: $toneMode, tone: tone)
                }
                .padding(.vertical, 14)
            }
            .homeRise(0)
            sheetCard {
                HomeLinkRow(glyph: Glyphs.games, title: "Your games", detail: gamesLine, tone: tone, action: actions.rewind)
                    .homeZoomSource(.games)
                    .homeRise(0)
                HomeHairline(tone: tone)
                HomeLinkRow(glyph: Glyphs.settings, title: "Settings", detail: "Board look, sound, hints", tone: tone, action: actions.settings)
                    .homeRise(1)
                if let premium = actions.premium {
                    HomeHairline(tone: tone)
                    HomeLinkRow(glyph: Glyphs.king, title: "Premium", detail: "Everything, with no limits", tone: tone, action: premium)
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
        onTab(tab)
    }

    /// Where a drag starts: on the board above the sheet, or on the sheet.
    private enum SheetGrip { case board, sheet }

    /// The top of the sheet's page, where a new tab opens.
    private static var sheetTop: String { "sheet-top" }

    /// Dragging the sheet (or the board above it) moves the sheet with the finger; on release
    /// it springs to the rest nearest where the flick was heading.
    private func sheetPull(on grip: SheetGrip, metrics: HomeSheetMetrics) -> some Gesture {
        DragGesture(minimumDistance: grip == .board ? 14 : 6, coordinateSpace: .global)
            .updating($sheetDrag) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let start: CGFloat = metrics.height(of: sheetDetent)
                let landing: CGFloat = start - value.predictedEndTranslation.height
                let next: HomeSheetDetent = Self.detent(from: sheetDetent, landing: landing, start: start, metrics: metrics)
                withAnimation(sheetSpring) { sheetDetent = next }
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
