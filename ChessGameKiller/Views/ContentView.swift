import ChessKit
import SwiftUI
import UIKit

/// The game screen, the same on every look: the opponent above a board that runs edge to edge
/// and you below it, each on a line of glass, the moves under yours, and a floating glass dock
/// with a labeled row of controls around the coach orb. Neon keeps its colors and glows.
/// When the orb unfolds, the players fold into one line and the board makes room.
struct ContentView: View {
    @State private var match = MatchController.live()
    @State private var showingNewGame = true
    @State private var showingSettings = false
    @State private var showingAnalyze = false
    /// Analyze opens on the camera (the home's Scan a board shortcut).
    @State private var analyzeWithCamera = false
    @State private var coachExpanded = false
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .gilded
    @AppStorage("matchRival") private var matchRival = false
    @AppStorage("showBestMoves") private var showBestMoves = false
    @AppStorage("showSecondBest") private var showSecondBest = true
    @AppStorage("coachVerdicts") private var showVerdicts = true
    @AppStorage("haptics") private var hapticsOn = true
    @State private var training: TrainingStore
    /// The daily streak and Today's Move, for the whole app.
    @State private var daily: DailyStore
    @State private var showingDaily = false
    @State private var coach = GameCoach()
    @State private var showingTraining = false
    @State private var puzzles = PuzzleStore.live()
    @State private var showingPuzzles = false
    @State private var army = ArmyStore.live()
    @State private var showingArmy = false
    @State private var armyNews: ArmyNews?
    @State private var vault = GameVault.live()
    @State private var showingGames = false
    /// A game picked on the home screen, opened straight away in Rewind.
    @State private var rewindOpening: UUID?
    /// The home screen covers the game until a game is started or resumed.
    @State private var showingHome: Bool
    @AppStorage(HomeScreen.key) private var homeScreenOn = HomeScreen.defaultOn
    @Environment(\.scenePhase) private var scenePhase
    /// Challenge a friend, when the app provides it (tests that draw this screen don't).
    @Environment(ChallengeCenter.self) private var challenges: ChallengeCenter?
    /// Big Board: the board edge to edge with everything else tucked into a pull-up tray.
    @AppStorage("bigBoard") private var bigBoard = false
    @AppStorage("sculpted3D") private var sculpted3D = true
    /// Tilted or flat 3D board (Settings, Board view).
    @AppStorage(BoardTilt.storageKey) private var tilt = BoardTilt.auto
    @AppStorage(BoardTheme.coordinatesKey) private var showsCoordinates = true
    /// Hold the board to see the engine's line ahead (counts as help).
    @AppStorage(GhostVision.storageKey) private var ghostVisionOn = true
    @State private var vision = GhostVision()
    @State private var trayOpen = false
    /// The position being looked at while the player swipes back through the game; nil is live.
    @State private var browsePly: Int?
    @State private var scrubStart: Int?
    /// Talk it through, open over the game.
    @State private var talk: TalkSession?
    /// The move the player pressed Play on in Talk it through, made once the talk has slid away.
    @State private var talkMove: PendingTalkMove?
    /// The first-run welcome, over everything until the player starts or skips.
    @State private var showingWelcome: Bool
    @AppStorage(Welcome.key) private var welcomeSeen = false

    /// The app opens on the home screen when it is on, otherwise on the New Game sheet;
    /// tests and screenshots that picture the game screen skip both, and may open the coach.
    init(startsWithNewGame: Bool = true, trayOpen: Bool = false, startsAtHome: Bool? = nil,
         match: MatchController? = nil, coachOpen: Bool = false, vision: GhostVision? = nil) {
        let trainingStore = TrainingStore.live()
        _training = State(initialValue: trainingStore)
        // The training streak carries over into the daily one the first time.
        _daily = State(initialValue: DailyStore.live(trainingStreak: trainingStore.progress.streak))
        if let match { _match = State(initialValue: match) }
        if let vision { _vision = State(initialValue: vision) }
        let home = startsAtHome ?? (startsWithNewGame && HomeScreen.isOn())
        let welcome = startsWithNewGame && !Welcome.isUnderTest && Welcome.shouldShow()
        _showingHome = State(initialValue: home)
        _showingWelcome = State(initialValue: welcome)
        _showingNewGame = State(initialValue: startsWithNewGame && !home && !welcome)
        _trayOpen = State(initialValue: trayOpen)
        _coachExpanded = State(initialValue: coachOpen)
    }

    /// Against the computer, the board matches the rival's portrait unless the player turned that off.
    private var theme: BoardTheme {
        if matchRival, match.setup.opponent == .computer {
            return .named(match.setup.level.rival.boardTheme)
        }
        return .named(themeID)
    }

    /// The look picked in Settings. Training, puzzles, lessons and the other screens away from the
    /// game always use it: a rival's board belongs to the game against that rival.
    private var chosenTheme: BoardTheme { .named(themeID) }
    /// The orb is unfolded, so nothing else fits beside it.
    private var coachIsWide: Bool { coachExpanded }
    /// The board is out of sight: the app is in the background, or another screen covers the game.
    /// The clock and the rival wait while it is.
    private var boardHidden: Bool {
        scenePhase != .active || showingHome || showingTraining || showingArmy || showingPuzzles || showingGames || showingDaily
            || showingNewGame || showingSettings || showingAnalyze
            || coach.presentedLesson != nil || coach.presentedSession != nil
            || challenges?.isPresenting == true || talk != nil || showingWelcome
    }
    /// Starting a game now would cost the one in progress: the rival it is against, so the
    /// screens that start games can ask first.
    private var forfeits: String? {
        match.newGameForfeits ? match.opponentName : nil
    }
    /// Who "Play from here" plays: the rival and clock of the game under way, or of the last one picked.
    private var fromHereSetup: MatchController.Setup {
        match.hasStarted ? match.setup : NewGameSheet.savedSetup()
    }
    /// While a game is under way, looking at the engine's lines for it is help, like Undo.
    private var analyzeGame: (() -> Void)? {
        guard match.canResign else { return nil }
        return { [match] in match.markAssisted() }
    }

    /// The players' lines, the moves and the dock keep this far from the screen's edges.
    private static let inset: CGFloat = 16
    /// Between a player's line and the board, and between your line and the moves.
    private static let gap: CGFloat = 6
    /// The least room kept above and below the players and the board.
    private static let edgeRoom: CGFloat = 6
    /// The dock: the orb and a little air around it.
    private static let dockHeight: CGFloat = CoachOrb.orbSize + 12
    /// On iPad the dock stays about a phone's width.
    private static let dockMaxWidth: CGFloat = 560
    /// The players' lines stay at least a phone's width when a short screen makes the board
    /// narrower; on iPad they match the board.
    private static let phoneWidth: CGFloat = 440
    /// How much of the screen the unfolded coach may take, so the board stays usable under it.
    private static let coachShare: CGFloat = 0.45

    // The rows grow with the reader's text size, up to a point, and the board makes room.
    @ScaledMetric(relativeTo: .body) private var scaledPlateHeight: CGFloat = 58
    @ScaledMetric(relativeTo: .footnote) private var scaledStripHeight: CGFloat = 32
    @ScaledMetric(relativeTo: .footnote) private var scaledRibbonHeight: CGFloat = 24
    /// One player's line.
    private var plateHeight: CGFloat { min(scaledPlateHeight, 66) }
    /// Both players on one line, while the coach is open.
    private var stripHeight: CGFloat { min(scaledStripHeight, 40) }
    private var ribbonHeight: CGFloat { min(scaledRibbonHeight, 30) }

    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The board stops growing here: larger across an iPad, and no phone is this wide.
    private var maxBoardSide: CGFloat { sizeClass == .regular ? 900 : 680 }

    var body: some View {
        // Fonts read the look from here: rounded on Neon, plain SF Pro on the rest.
        let _ = ThemeFont.use(theme)
        presented
            .overlay {
                if showingWelcome {
                    WelcomeFlow(canStartGame: !match.newGameForfeits, page: Welcome.showcasePage()) { play, choice in
                        finishWelcome(play: play, choice: choice)
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: welcomeSeen) { _, seen in
                // Settings › How it works › Replay the welcome.
                if !seen { withAnimation(.easeInOut(duration: 0.35)) { showingWelcome = true } }
            }
            .onAppear {
                syncCoachSettings()
                // A game left unfinished when a new one starts is still kept.
                match.onArchive = { [vault] game in vault.record(game) }
                // So is a finished friend game, and it counts for the day.
                challenges?.onGameFinished = { [vault, daily] game in
                    vault.record(game)
                    daily.record(.game)
                }
                hookUpDaily()
                match.onAbandon = { [army] ledger, setup, assisted in
                    // Walking away from a game counts as a loss.
                    army.record(ledger, playerColor: setup.playerColor, won: false,
                                stakes: GameStakes(level: setup.level, assisted: assisted, staked: setup.stake))
                }
                // Every grade reaches the coach, shown or not, so real mistakes are saved to practice.
                match.onReview = { [weak match, coach, training] review, latest in
                    guard let match else { return }
                    coach.observe(review, in: match, store: training, quietly: !latest || !match.showVerdicts)
                }
            }
            .task {
                // The welcome chime as the app opens, once per launch.
                SoundPlayer.shared.playWelcome()
                await StockfishEngine.shared.warmUp()
            }
            .onChange(of: showBestMoves) { _, _ in syncCoachSettings() }
            .onChange(of: showSecondBest) { _, _ in syncCoachSettings() }
            .onChange(of: showVerdicts) { _, _ in syncCoachSettings() }
            .onChange(of: showingNewGame) { _, showing in
                if showing { setCoach(expanded: false) }
            }
            .onChange(of: showingAnalyze) { _, showing in
                if showing { setCoach(expanded: false) }
            }
            .onChange(of: showingTraining) { _, showing in
                if showing { setCoach(expanded: false) }
            }
            .onChange(of: showingPuzzles) { _, showing in
                if showing { setCoach(expanded: false) }
            }
            .onChange(of: match.isOver) { _, over in
                guard over else { return }
                recordArmy()
                recordGame()
                // A game played to its end makes the day.
                daily.record(.game)
                if bigBoard { trayOpen = true }
                // Let the last move land and the king fall, then open the summary.
                let number = match.gameNumber
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.6))
                    guard match.isOver, match.gameNumber == number, !showingNewGame else { return }
                    setCoach(expanded: true)
                }
            }
    }

    /// The game screen with its sheets and full-screen covers.
    private var presented: some View {
        observed
            .fullScreenCover(isPresented: $showingTraining) {
                TrainingHubView(theme: chosenTheme).environment(training).environment(puzzles).environment(vault)
                    .environment(daily)
            }
            .fullScreenCover(isPresented: $showingDaily) {
                DailyMoveView(theme: chosenTheme, morePuzzles: {
                    // Once Today's Move has slid away.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        showingPuzzles = true
                    }
                })
                .environment(daily).environment(puzzles).environment(training)
            }
            .fullScreenCover(isPresented: $showingPuzzles) {
                PuzzlesView(theme: chosenTheme).environment(puzzles).environment(training)
            }
            .onChange(of: showingGames) { _, showing in
                if !showing { rewindOpening = nil }
            }
            .fullScreenCover(isPresented: $showingGames) {
                RewindGamesView(theme: chosenTheme, opening: rewindOpening, forfeits: forfeits) { game in playAgain(game) }
                    .environment(vault).environment(training)
            }
            .fullScreenCover(isPresented: $showingArmy) {
                ArmyView(theme: chosenTheme, color: match.setup.playerColor).environment(army)
            }
            .fullScreenCover(item: $coach.presentedLesson) { lesson in
                LessonScreen(lesson: lesson, theme: chosenTheme).environment(training).environment(daily)
            }
            .fullScreenCover(item: $coach.presentedSession) { plan in
                // Asked for with one tap, so it starts at once. The puzzle store lets a missed
                // puzzle in the session come back for review.
                SessionView(plan: plan, theme: chosenTheme, startsAtOnce: true)
                    .environment(training)
                    .environment(puzzles)
                    .environment(daily)
            }
            .fullScreenCover(item: $talk, onDismiss: playTalkMove) { (session: TalkSession) in
                TalkPanel(session: session, theme: theme, play: { (uci: String) in
                    talkMove = PendingTalkMove(fen: session.fen, uci: uci)
                    talk = nil
                }, close: { talk = nil })
            }
            .animation(.easeInOut(duration: 0.35), value: theme.id)
            .sheet(isPresented: $showingNewGame, onDismiss: startIfNeeded) {
                NewGameSheet(theme: theme, forfeits: forfeits) { setup in
                    withAnimation(.snappy) { match.start(setup) }
                    showingNewGame = false
                    leaveHome()
                } challenge: {
                    showingNewGame = false
                    challenges?.compose()
                }
                .environment(army)
            }
            .sheet(isPresented: $showingSettings, onDismiss: refreshDaily) {
                SettingsSheet()
            }
            .sheet(isPresented: $showingAnalyze, onDismiss: { analyzeWithCamera = false }) {
                AnalyzeSheet(
                    theme: theme,
                    currentFEN: match.hasStarted ? match.game.fen : nil,
                    engine: StockfishEngine.shared,
                    reader: CloudBoardReader.live,
                    rival: fromHereSetup.level.rival.name,
                    clock: fromHereSetup.timeControl,
                    forfeits: forfeits,
                    onAnalyzeGame: analyzeGame,
                    startsWithCamera: analyzeWithCamera
                ) { draft in
                    play(from: draft)
                }
            }
    }

    /// The game screen, watching the match for the coach and the clock.
    private var observed: some View {
        screens
            // Switching between Neon and the executive look redraws everything in the new type.
            .id(theme.glows)
            .tint(theme.accent)
            .preferredColorScheme(theme.isDark ? .dark : nil)
            .environment(training)
            .environment(coach)
            .environment(army)
            .environment(vault)
            .environment(puzzles)
            .environment(daily)
            .onReceive(NotificationCenter.default.publisher(for: DailyLink.notification)) { _ in openDaily() }
            .onReceive(NotificationCenter.default.publisher(for: LiveGameLink.notification)) { _ in openLiveGame() }
            // The game under way on the Lock Screen and in the Dynamic Island.
            .modifier(LiveGameFollow(match: match))
            .onChange(of: match.reelLog.count) { _, _ in
                // The last grades can land just after the game ends.
                if match.isOver { recordGame() }
            }
            .onChange(of: match.gameNumber) { _, _ in
                coach.gameStarted()
                announceGrudge()
                // Nothing on screen carries over from the last game.
                browsePly = nil
                scrubStart = nil
                trayOpen = false
                setCoach(expanded: false)
            }
            .onChange(of: match.game.plyCount) { _, _ in
                // A move or an undo brings the board back to the live position.
                browsePly = nil
                scrubStart = nil
            }
            .onChange(of: match.game.moveCount) { _, _ in
                // Once the learner moves on, the tip about the move before is over.
                if let played = match.game.lastPlayed, match.game.humanColors.contains(played.color) {
                    coach.dismiss()
                }
            }
            .onChange(of: boardHidden) { _, hidden in
                if hidden { match.suspend() } else { match.resume() }
            }
            .onChange(of: scenePhase) { _, phase in
                // A new day may have started while away; the reminders and the widget follow.
                if phase == .active || phase == .background { refreshDaily() }
                // iOS may end the app while it is away: a game long enough to keep is kept in
                // Your games, on disk before the app is put to sleep.
                if phase == .background, match.hasStarted, !match.isOver,
                   match.game.plyCount >= MatchController.pliesWorthKeeping {
                    recordGame()
                    vault.waitUntilSaved()
                }
            }
            .onChange(of: BoardView.playsIn3D(theme, setting: sculpted3D), initial: true) { _, threeD in
                timeSounds(threeD: threeD)
            }
            .onChange(of: challenges?.isPresenting == true) { _, presenting in
                // Challenge a friend takes the New Game sheet's place; with no game under way, the sheet comes back after.
                if presenting {
                    showingNewGame = false
                } else if !match.hasStarted, !showingHome {
                    showingNewGame = true
                }
            }
            .onChange(of: match.clock?.running, initial: true) { _, running in
                // The screen stays awake while a clock runs.
                UIApplication.shared.isIdleTimerDisabled = running != nil
            }
    }

    /// The home screen, or the game once one is under way.
    @ViewBuilder
    private var screens: some View {
        if showingHome {
            // The home is dressed in the player's own look, not a rival's board.
            HomeView(match: match, theme: .named(themeID), actions: homeActions)
                .transition(.opacity)
        } else {
            gameScreen
                .transition(.opacity)
        }
    }

    private var homeActions: HomeActions {
        HomeActions(
            play: { showingNewGame = true },
            start: { setup in
                withAnimation(.snappy) { match.start(setup) }
                leaveHome()
            },
            playRival: { level in
                // The New Game sheet opens on this rival.
                UserDefaults.standard.set(level.rawValue, forKey: "setup.level")
                showingNewGame = true
            },
            resume: { leaveHome() },
            analyze: { showingAnalyze = true },
            scan: {
                analyzeWithCamera = true
                showingAnalyze = true
            },
            train: { showingTraining = true },
            trainToday: { plan in coach.presentedSession = plan },
            puzzles: { showingPuzzles = true },
            dailyMove: { openDaily() },
            rewind: { showingGames = true },
            openGame: { game in
                rewindOpening = game.id
                showingGames = true
            },
            army: { showingArmy = true },
            settings: { showingSettings = true }
        )
    }

    // MARK: The daily habit

    /// Everything that counts for the day reports to the daily store; a milestone marks a piece;
    /// every change reaches the widget and the reminders.
    private func hookUpDaily() {
        puzzles.onRated = { [daily] outcome in daily.record(.ratedPuzzle(solved: outcome != .missed)) }
        training.onFinished = { [daily] in daily.record(.training) }
        daily.onMilestone = { [army] days in
            guard let news = army.markStreak(days: days) else { return nil }
            // On the game screen the banner says so; the home's Today card says it too.
            if !showingHome { show(news, after: 3.0) }
            return news.name
        }
        daily.onChange = { refreshDaily() }
        refreshDaily()
        // CI's pictures open Today's Move with `-showcaseDaily YES`; a normal launch never passes it.
        if UserDefaults.standard.bool(forKey: "showcaseDaily") { DailyLink.pending = true }
        if DailyLink.pending { openDaily() }
    }

    private func refreshDaily() {
        DailyUpkeep.refresh(daily: daily, army: army, lastGame: vault.games.map(\.date).max())
    }

    /// The game on the Lock Screen was tapped: the game comes forward, over the home and any
    /// screen opened over it. (After a cold start there is no game, and the home stays.)
    private func openLiveGame() {
        guard !showingWelcome, match.hasStarted else { return }
        showingTraining = false
        showingPuzzles = false
        showingGames = false
        showingArmy = false
        showingDaily = false
        showingNewGame = false
        showingSettings = false
        showingAnalyze = false
        leaveHome()
    }

    /// Opens Today's Move over whatever is showing (from Home, the widget or a reminder).
    private func openDaily() {
        DailyLink.pending = false
        guard !showingWelcome else { return }
        let covered = showingTraining || showingPuzzles || showingGames || showingArmy || showingNewGame
            || showingSettings || showingAnalyze
        showingTraining = false
        showingPuzzles = false
        showingGames = false
        showingArmy = false
        showingNewGame = false
        showingSettings = false
        showingAnalyze = false
        if !covered {
            showingDaily = true
            return
        }
        // Once the screen that was up has slid away.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            showingDaily = true
        }
    }

    /// Tips keep out of the way of the army's news, the unfolded coach and a held board.
    private var tipsBlocked: Bool {
        armyNews != nil || coachExpanded || vision.isHolding || showingWelcome
    }

    /// The welcome is done: start the first game, or leave the player on the home (or the New Game sheet).
    private func finishWelcome(play: Bool, choice: WelcomeChoice) {
        withAnimation(.easeInOut(duration: 0.35)) { showingWelcome = false }
        syncCoachSettings()
        if play {
            withAnimation(.snappy) { match.start(choice.setup()) }
            leaveHome()
        } else if !showingHome, !match.hasStarted {
            showingNewGame = true
        }
    }

    private func leaveHome() {
        guard showingHome else { return }
        withAnimation(.easeInOut(duration: 0.35)) { showingHome = false }
    }

    private func goHome() {
        setCoach(expanded: false)
        // A victory theme still playing fades as the game leaves the screen.
        SoundPlayer.shared.stopAll(fade: 0.4)
        withAnimation(.easeInOut(duration: 0.35)) { showingHome = true }
    }

    /// The board, the players and the dock inside the navigation bar, sized to the screen.
    private var gameScreen: some View {
        GeometryReader { screen in
            NavigationStack {
                GeometryReader { geo in
                    boardLayout(in: geo.size)
                }
                // The army's news floats just above the dock, clear of both players' lines.
                .overlay(alignment: .bottom) {
                    if let news = armyNews {
                        ArmyNewsBanner(news: news, color: match.setup.playerColor, theme: theme) {
                            armyNews = nil
                            showingArmy = true
                        }
                        .padding(.horizontal, Self.inset)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                // A one-line tip the first time a hidden gesture or a rule would help.
                .overlay(alignment: .bottom) {
                    GameTips(match: match, theme: theme, bigBoard: bigBoard, ghostVisionOn: ghostVisionOn,
                             blocked: tipsBlocked)
                        .frame(maxWidth: Self.dockMaxWidth)
                        .padding(.horizontal, Self.inset)
                        .padding(.bottom, 8)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    let coachHeight = screen.size.height * Self.coachShare
                    Group {
                        if bigBoard {
                            bigTray(coachHeight: coachHeight)
                        } else {
                            dock(coachHeight: coachHeight)
                        }
                    }
                    .frame(maxWidth: Self.dockMaxWidth)
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 8)
                    // Above the home indicator; on a phone without one, a little off the edge.
                    .padding(.bottom, screen.safeAreaInsets.bottom > 0 ? 0 : 8)
                }
                .background { SheetBackdrop(theme: theme) }
                .navigationTitle("Chess Game Killer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .toolbar(bigBoard ? .hidden : .visible, for: .navigationBar)
            }
        }
    }

    /// The opponent's line above the board and yours below it, hugging it, with the moves under
    /// yours; the whole block sits in the middle of the space. The board runs edge to edge on a
    /// phone. While the coach is open the two players fold into one line. Big Board uses the same
    /// layout without the top bar, and the board there can be swiped to look back through the game.
    private func boardLayout(in size: CGSize) -> some View {
        let compact = coachExpanded
        let aspect = boardAspect
        let lines = compact ? stripHeight : plateHeight * 2
        let gaps = Self.gap * (compact ? 2 : 3)
        let fixed = lines + gaps + ribbonHeight + Self.edgeRoom * 2
        // The headroom over a flat board grows with the board, so it is solved for with it.
        let byHeight = max(0, size.height - fixed) * aspect / (1 + headroom * aspect)
        let side = max(0, min(size.width, maxBoardSide, byHeight))
        let lineWidth = max(0, max(side, min(size.width, Self.phoneWidth)) - Self.inset * 2)
        let topColor: Piece.Color = match.isBoardFlipped ? .white : .black
        return VStack(spacing: 0) {
            Spacer(minLength: Self.edgeRoom)
            Group {
                if compact {
                    PlayersStrip(match: match, theme: theme)
                        .frame(width: lineWidth, height: stripHeight)
                } else {
                    ExecutivePlate(match: match, theme: theme, color: topColor)
                        .frame(width: lineWidth, height: plateHeight)
                }
            }
            Color.clear.frame(height: Self.gap + side * headroom)
            board
                .frame(width: side, height: side / aspect)
            Color.clear.frame(height: Self.gap)
            if !compact {
                ExecutivePlate(match: match, theme: theme, color: topColor.opposite)
                    .frame(width: lineWidth, height: plateHeight)
                Color.clear.frame(height: Self.gap)
            }
            ribbonRow
                // In line with the avatars on the players' lines.
                .frame(width: max(0, lineWidth - 18), height: ribbonHeight)
            Spacer(minLength: Self.edgeRoom)
        }
        .frame(maxWidth: .infinity)
    }

    /// Room kept over a flat board of standing pieces, as a share of the board's width (the board
    /// with its frame is 9 squares wide, a little over 8 with coordinates off): the far rank's kings rise a little above its frame.
    /// The 3D board and Neon's flat pieces stay within the board.
    private var headroom: CGFloat {
        theme.spritePieces && !BoardView.playsIn3D(theme, setting: sculpted3D) ? SpriteFrame.sideOn.boardRise / theme.squaresAcross(coordinates: showsCoordinates) : 0
    }

    /// The live board; in Big Board it can be swiped to look back through the game.
    @ViewBuilder
    private var board: some View {
        if bigBoard {
            browsableBoard
        } else {
            BoardView(match: match, theme: theme, vision: ghostVisionOn ? vision : nil, framing: framing)
        }
    }

    /// The moves, or in Big Board while looking back, where the game was and the way back;
    /// beside them the Tilted / Flat switch.
    @ViewBuilder
    private var ribbonRow: some View {
        if ghostVisionOn, vision.isHolding {
            // Ghost Vision's line takes the whole row while the board is held.
            GhostStrip(line: match.ghostLine, focus: vision.focus, theme: theme)
                .transition(.opacity)
        } else {
            HStack(spacing: 10) {
                movesOrBrowsing
                BoardViewSwitch(theme: theme, bigBoard: bigBoard)
            }
        }
    }

    @ViewBuilder
    private var movesOrBrowsing: some View {
        if bigBoard, let ply = browsePly {
            BrowsePill(ply: ply,
                       san: ply > 0 && ply <= match.game.moves.count ? match.game.moves[ply - 1] : nil,
                       theme: theme) {
                withAnimation(.snappy) { browsePly = nil }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            MoveRibbon(moves: match.game.moves, theme: theme)
        }
    }

    /// The live board, showing an earlier position while the player looks back.
    /// Dragging sideways scrubs through the game: right goes back, left comes forward.
    private var browsableBoard: some View {
        ZStack {
            // The 3D board walks its own pieces back through the game; the flat board has
            // the earlier position laid over it.
            BoardView(match: match, theme: theme, browsing: browsedPosition, endBrowsing: {
                withAnimation(.snappy) { browsePly = nil }
            }, vision: ghostVisionOn ? vision : nil, framing: framing)
            if !BoardView.playsIn3D(theme, setting: sculpted3D), let ply = browsePly,
               let fen = match.game.positionFENs[safe: ply], let draft = PositionDraft(fen: fen) {
                PositionBoard(draft: draft, theme: theme, flipped: match.isBoardFlipped) { _ in
                    withAnimation(.snappy) { browsePly = nil }
                }
                .transition(.opacity)
                .accessibilityLabel("An earlier position. Tap to go back to the game.")
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged(scrub)
                .onEnded { _ in scrubStart = nil }
        )
        .sensoryFeedback(.selection, trigger: browsePly) { _, _ in hapticsOn }
        .accessibilityAction(named: "Previous move") { step(by: -1) }
        .accessibilityAction(named: "Next move") { step(by: 1) }
    }

    /// The position the player is looking back at, if any.
    private var browsedPosition: Position? {
        browsePly.flatMap { match.game.positionFENs[safe: $0] }.flatMap { Position(fen: $0) }
    }

    /// Width over height of the board in play: 1 for the flat looks, wider for the 3D board.
    private var boardAspect: CGFloat {
        BoardView.aspect(theme, setting: sculpted3D, framing: framing)
    }

    /// How the 3D board is seen: the Board view setting, with Auto laying Big Board flat.
    private var framing: SculptedCamera.Framing {
        tilt.framing(bigBoard: bigBoard)
    }

    /// One position for every ~34 points of sideways drag.
    private func scrub(_ value: DragGesture.Value) {
        // While Ghost Vision is up, sliding sideways steps through its line instead.
        guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
              match.game.pendingPromotion == nil, !vision.isHolding else { return }
        let live = match.game.positionFENs.count - 1
        let start = scrubStart ?? (browsePly ?? live)
        scrubStart = start
        let steps = Int((value.translation.width / 34).rounded(.towardZero))
        let ply = min(live, max(0, start - steps))
        let next: Int? = ply == live ? nil : ply
        if next != browsePly { browsePly = next }
    }

    private func step(by delta: Int) {
        let live = match.game.positionFENs.count - 1
        let ply = min(live, max(0, (browsePly ?? live) + delta))
        browsePly = ply == live ? nil : ply
    }

    /// The tray at the bottom of Big Board, holding the dock's controls and what the top bar would.
    private func bigTray(coachHeight: CGFloat) -> some View {
        BigBoardTray(match: match, theme: theme, isOpen: $trayOpen, coachIsWide: coachIsWide,
                     onNewGame: { showingNewGame = true },
                     onSettings: { showingSettings = true },
                     onExit: { withAnimation(.snappy) { bigBoard = false } },
                     onArmy: { showingArmy = true },
                     onGames: { showingGames = true },
                     onHome: homeScreenOn ? { goHome() } : nil) {
            dockRow(coachHeight: coachHeight)
        }
        .onChange(of: trayOpen) { _, open in
            if !open { setCoach(expanded: false) }
        }
    }

    /// Switches Big Board on.
    private func enterBigBoard() {
        withAnimation(.snappy) {
            trayOpen = false
            bigBoard = true
        }
    }

    /// Home, the game in the middle, then New game and everything else in one menu, so the
    /// title always has room. On iOS 26 each side sits on the system's own glass.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if homeScreenOn {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    goHome()
                } label: {
                    Label("Home", image: Glyphs.home)
                }
                .tint(.primary)
            }
        }
        ToolbarItem(placement: .principal) {
            ExecutiveMatchTitle(match: match)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingNewGame = true
            } label: {
                Label("New game", systemImage: "plus")
            }
            .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
            moreMenu
                .tint(.primary)
        }
    }

    /// Everything that leaves the board for a moment, one tap away.
    private var moreMenu: some View {
        Menu {
            Button {
                enterBigBoard()
            } label: {
                Label("Big Board", image: Glyphs.bigBoard)
            }
            Button {
                withAnimation(.snappy) { match.flipBoard() }
            } label: {
                Label("Flip board", image: Glyphs.flip)
            }
            Section {
                Button {
                    showingGames = true
                } label: {
                    Label("Your games", image: Glyphs.games)
                }
                Button {
                    showingArmy = true
                } label: {
                    Label("Your pieces", image: Glyphs.army)
                }
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", image: Glyphs.settings)
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    /// The dock: the row of controls around the orb on one floating pane of glass. When the orb
    /// unfolds, the same glass grows to hold the coach.
    private func dock(coachHeight: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: coachExpanded ? 30 : Self.dockHeight / 2, style: .continuous)
        return dockRow(coachHeight: coachHeight)
            .glassPane(shape)
            .background {
                if theme.glows {
                    // Neon's dock glows in its accent, behind the glass.
                    shape.fill((theme.accent ?? .accentColor).opacity(0.16))
                        .blur(radius: 18)
                }
            }
    }

    /// Every control named, three either side of the orb. They step aside while the orb is wide.
    /// No glass of its own: it sits on the dock's, or on Big Board's tray.
    private func dockRow(coachHeight: CGFloat) -> some View {
        ZStack {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    DockButton(title: "Analyze", symbol: Glyphs.analyze, theme: theme) {
                        showingAnalyze = true
                    }
                    DockButton(title: "Train", symbol: Glyphs.train, theme: theme) {
                        showingTraining = true
                    }
                    DockButton(title: "Puzzles", symbol: Glyphs.puzzles, theme: theme) {
                        showingPuzzles = true
                    }
                }
                .frame(maxWidth: .infinity)
                // The orb's place. Only a width: a bare Color.clear takes every bit of
                // height it is offered, which pushed the dock up and squeezed the board to nothing.
                Color.clear.frame(width: CoachOrb.orbSize + 12, height: 1)
                HStack(spacing: 0) {
                    DockButton(title: "Undo", symbol: Glyphs.undo, theme: theme) {
                        withAnimation(.snappy(duration: 0.22)) { match.undo() }
                    }
                    .disabled(!match.canUndo)
                    DockButton(title: "Hints", symbol: showBestMoves ? Glyphs.hints : Glyphs.hintsOff,
                               isOn: showBestMoves, theme: theme) {
                        showBestMoves.toggle()
                    }
                    DockButton(title: "Flip", symbol: Glyphs.flip, theme: theme) {
                        withAnimation(.snappy) { match.flipBoard() }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 6)
            // The dock keeps its height, so its type stops growing a little sooner.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .opacity(coachIsWide ? 0 : 1)
            .scaleEffect(coachIsWide ? 0.92 : 1)
            .allowsHitTesting(!coachIsWide)
            CoachOrb(match: match, theme: theme, isExpanded: $coachExpanded, expandedMaxHeight: coachHeight,
                     newGame: { showingNewGame = true }, showGames: { showingGames = true },
                     talk: { openTalk() })
                .padding(.horizontal, coachExpanded ? 0 : 6)
        }
        .frame(minHeight: Self.dockHeight)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: coachIsWide)
    }

    /// Talk it through for the position on the board, over the game, which waits under it.
    private func openTalk() {
        guard talk == nil, let session = match.talkSession() else { return }
        setCoach(expanded: false)
        talk = session
    }

    /// The move the player pressed Play on in Talk it through, made as their own now that the
    /// board is back in sight, so they see it land. Only on the position they talked about.
    private func playTalkMove() {
        guard let pending = talkMove else { return }
        talkMove = nil
        guard match.game.fen == pending.fen else { return }
        withAnimation(.snappy) { _ = match.playOwnMove(pending.uci) }
    }

    private func setCoach(expanded: Bool) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            coachExpanded = expanded
        }
    }

    private func syncCoachSettings() {
        match.showBestMoves = showBestMoves
        match.showSecondBest = showSecondBest
        match.showVerdicts = showVerdicts
    }

    /// Adds a finished game against the computer to the army, and announces
    /// the best thing a piece earned.
    private func recordArmy() {
        guard match.setup.opponent == .computer, let ledger = match.game.ledger else { return }
        let won = match.winner.map { $0 == match.setup.playerColor }
        guard let news = army.record(ledger, playerColor: match.setup.playerColor, won: won,
                                       stakes: match.armyStakes).first else { return }
        // After the finale and the summary, so the end of the game has the stage first.
        show(news, after: 3.4)
    }

    /// As a game against a rival starts: the piece that rival keeps taking. It waits until the
    /// rival's greeting has had its moment, and comes once a day per rival: before every game it
    /// would be a nag.
    private func announceGrudge() {
        guard match.setup.opponent == .computer, match.game.ledger != nil else { return }
        // On the line: what this game decides comes first, every game.
        let level = match.setup.level
        if let slot = match.setup.stake, army.canStake(slot, against: level) {
            show(army.stakeNews(slot, against: level), after: 4.0)
            return
        }
        if let rescue = army.rescueNews(against: level) {
            show(rescue, after: 4.0)
            return
        }
        guard let news = army.grudge(against: match.setup.level) else { return }
        let key = "grudge.told.\(match.setup.level.rawValue)"
        if let told = UserDefaults.standard.object(forKey: key) as? Date, Calendar.current.isDateInToday(told) { return }
        UserDefaults.standard.set(Date(), forKey: key)
        show(news, after: 4.0)
    }

    /// Slides the army banner in, then away again unless something newer replaced it.
    private func show(_ news: ArmyNews, after delay: Double) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { armyNews = news }
            try? await Task.sleep(for: .seconds(6))
            if armyNews == news {
                withAnimation(.easeOut(duration: 0.3)) { armyNews = nil }
            }
        }
    }

    /// Keeps the game for Rewind. Called again as late grades arrive; the vault updates it in place.
    private func recordGame() {
        guard let game = match.savedGame() else { return }
        vault.record(game)
    }

    /// The same game again, from a rewound one: the same rival, side and clock.
    private func playAgain(_ game: SavedGame) {
        var setup = NewGameSheet.savedSetup()
        if let raw = game.level, let level = MatchController.Level(rawValue: raw) {
            setup.level = level
            setup.playerColor = game.playerColor
        }
        if let clock = game.clock.flatMap({ TimeControl(rawValue: $0) }) {
            setup.timeControl = clock
        }
        withAnimation(.snappy) { match.start(setup) }
        showingNewGame = false
        leaveHome()
    }

    /// Starts a game from an analyzed position, with the player moving first, against the
    /// rival and on the clock the Analyze screen named.
    private func play(from draft: PositionDraft) {
        guard let position = draft.position else { return }
        var setup = fromHereSetup
        setup.playerColor = draft.sideToMove
        withAnimation(.snappy) { match.start(setup, from: position) }
        leaveHome()
    }

    /// The move's sound and the end of a game are heard when they are seen: on the 3D board
    /// when the piece touches down and when the mated king has settled.
    private func timeSounds(threeD: Bool) {
        if threeD {
            let game = match.game
            match.landingDelay = { move in SculptedBoardScene.landingDelay(for: move, in: game) }
            match.finaleDelay = { move in SculptedBoardScene.finaleDelay(for: move, in: game) }
        } else {
            match.landingDelay = { _ in 0 }
            match.finaleDelay = { _ in 0.4 }
        }
    }

    /// Closing the sheet without starting still begins a game, with last time's choices.
    private func startIfNeeded() {
        // Closed for Challenge a friend: no game starts behind it.
        if challenges?.isPresenting == true { return }
        // From the home screen, closing the sheet just goes back home.
        if !match.hasStarted, !showingHome {
            match.start(NewGameSheet.savedSetup())
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// A move picked in Talk it through, and the position it was picked in.
private struct PendingTalkMove: Equatable {
    let fen: String
    let uci: String
}

#Preview { ContentView() }
