import ChessKit
import SwiftUI
import UIKit

/// The game screen. On Neon: the two players above the board, each side's
/// captures down its edge, and Undo and Hints beside the coach orb. On every
/// other theme, the quiet executive look: the opponent above a full-width
/// board and you below it, and a labeled row of controls around the orb.
/// When the orb unfolds, the players fold into one line and the board makes room.
struct ContentView: View {
    @State private var match = MatchController.live()
    @State private var showingNewGame = true
    @State private var showingSettings = false
    @State private var showingAnalyze = false
    @State private var coachExpanded = false
    @State private var coachPeeking = false
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .gilded
    @AppStorage("matchRival") private var matchRival = false
    @AppStorage("showBestMoves") private var showBestMoves = true
    @AppStorage("showSecondBest") private var showSecondBest = true
    @AppStorage("coachVerdicts") private var showVerdicts = true
    @State private var training = TrainingStore.live()
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
    /// Big Board: the board edge to edge with everything else tucked into a pull-up tray.
    @AppStorage("bigBoard") private var bigBoard = false
    @AppStorage("sculpted3D") private var sculpted3D = true
    @State private var trayOpen = false
    /// The position being looked at while the player swipes back through the game; nil is live.
    @State private var browsePly: Int?
    @State private var scrubStart: Int?

    /// The app opens on the home screen when it is on, otherwise on the New Game sheet;
    /// tests that picture the game screen skip both.
    init(startsWithNewGame: Bool = true, trayOpen: Bool = false, startsAtHome: Bool? = nil) {
        let home = startsAtHome ?? (startsWithNewGame && HomeScreen.isOn())
        _showingHome = State(initialValue: home)
        _showingNewGame = State(initialValue: startsWithNewGame && !home)
        _trayOpen = State(initialValue: trayOpen)
    }

    /// Against the computer, the board matches the rival's portrait unless the player turned that off.
    private var theme: BoardTheme {
        if matchRival, match.setup.opponent == .computer {
            return .named(match.setup.level.rival.boardTheme)
        }
        return .named(themeID)
    }
    /// The orb is stretched or unfolded, so nothing else fits beside it.
    private var coachIsWide: Bool { coachExpanded || coachPeeking }
    /// The board is out of sight: the app is in the background, or training covers the game.
    /// The clock waits while it is.
    private var boardHidden: Bool {
        scenePhase != .active || showingHome || showingTraining || showingArmy || showingPuzzles || showingGames
            || coach.presentedLesson != nil || coach.presentedSession != nil
    }

    private static let spacing: CGFloat = 12
    private static let platesHeight: CGFloat = 64
    /// One executive player line.
    private static let plateHeight: CGFloat = 50
    private static let stripHeight: CGFloat = 30
    private static let ribbonHeight: CGFloat = 24
    /// The captured-piece rails either side of the board.
    private static let railWidth: CGFloat = 26
    private static let railSpacing: CGFloat = 6
    /// The board stops growing here. On iPad the plates, ribbon and controls keep to
    /// the same column instead of stretching across the screen; no phone is this wide.
    private static let maxBoardSide: CGFloat = 680
    /// The board and its two rails, at their widest.
    private static let neonColumnWidth: CGFloat = maxBoardSide + (railWidth + railSpacing) * 2
    /// How much of the screen the unfolded coach may take, so the board stays usable under it.
    private static let coachShare: CGFloat = 0.45

    var body: some View {
        // Fonts read the look from here: rounded on Neon, plain SF Pro on the rest.
        let _ = ThemeFont.use(theme)
        presented
            .onAppear {
                syncCoachSettings()
                // A game left unfinished when a new one starts is still kept.
                match.onArchive = { [vault] game in vault.record(game) }
                match.onAbandon = { [army] ledger, setup, assisted in
                    // Walking away from a game counts as a loss.
                    army.record(ledger, playerColor: setup.playerColor, won: false,
                                stakes: GameStakes(level: setup.level, assisted: assisted))
                }
            }
            .task { await StockfishEngine.shared.warmUp() }
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
                if bigBoard { trayOpen = true }
                // Let the last move land and the sound play, then open the summary.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.4))
                    guard match.isOver, !showingNewGame else { return }
                    setCoach(expanded: true)
                }
            }
    }

    /// The game screen with its sheets and full-screen covers.
    private var presented: some View {
        observed
            .fullScreenCover(isPresented: $showingTraining) {
                TrainingHubView(theme: theme).environment(training).environment(puzzles)
            }
            .fullScreenCover(isPresented: $showingPuzzles) {
                PuzzlesView(theme: theme).environment(puzzles).environment(training)
            }
            .onChange(of: showingGames) { _, showing in
                if !showing { rewindOpening = nil }
            }
            .fullScreenCover(isPresented: $showingGames) {
                RewindGamesView(theme: theme, opening: rewindOpening) { game in playAgain(game) }
                    .environment(vault).environment(training)
            }
            .fullScreenCover(isPresented: $showingArmy) {
                ArmyView(theme: theme, color: match.setup.playerColor).environment(army)
            }
            .fullScreenCover(item: $coach.presentedLesson) { lesson in
                LessonScreen(lesson: lesson, theme: theme).environment(training)
            }
            .fullScreenCover(item: $coach.presentedSession) { plan in
                SessionView(plan: plan, theme: theme).environment(training)
            }
            .animation(.easeInOut(duration: 0.35), value: theme.id)
            .sheet(isPresented: $showingNewGame, onDismiss: startIfNeeded) {
                NewGameSheet(theme: theme) { setup in
                    withAnimation(.snappy) { match.start(setup) }
                    showingNewGame = false
                    leaveHome()
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet()
            }
            .sheet(isPresented: $showingAnalyze) {
                AnalyzeSheet(
                    theme: theme,
                    currentFEN: match.game.fen,
                    engine: StockfishEngine.shared,
                    reader: CloudBoardReader.live
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
            .onChange(of: match.reelLog.count) { _, _ in
                // The last grades can land just after the game ends.
                if match.isOver { recordGame() }
            }
            .onChange(of: match.review) { _, review in
                coach.observe(review, in: match, store: training)
            }
            .onChange(of: match.gameNumber) { _, _ in
                coach.gameStarted()
                announceGrudge()
            }
            .onChange(of: match.game.moveCount) { _, _ in
                // A new move brings the board back to the live position.
                browsePly = nil
                scrubStart = nil
                // Once the learner moves on, the tip about the move before is over.
                if let played = match.game.lastPlayed, match.game.humanColors.contains(played.color) {
                    coach.dismiss()
                }
            }
            .onChange(of: boardHidden) { _, hidden in
                if hidden { match.suspendClock() } else { match.resumeClock() }
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
            HomeView(match: match, theme: theme, actions: homeActions)
                .transition(.opacity)
        } else {
            gameScreen
                .transition(.opacity)
        }
    }

    private var homeActions: HomeActions {
        HomeActions(
            play: { showingNewGame = true },
            resume: { leaveHome() },
            analyze: { showingAnalyze = true },
            train: { showingTraining = true },
            puzzles: { showingPuzzles = true },
            rewind: { showingGames = true },
            openGame: { game in
                rewindOpening = game.id
                showingGames = true
            },
            army: { showingArmy = true },
            settings: { showingSettings = true }
        )
    }

    private func leaveHome() {
        guard showingHome else { return }
        withAnimation(.easeInOut(duration: 0.35)) { showingHome = false }
    }

    private func goHome() {
        setCoach(expanded: false)
        withAnimation(.easeInOut(duration: 0.35)) { showingHome = true }
    }

    /// Back to the home screen, in the top bar while the home screen is on.
    private var homeButton: some View {
        Button {
            goHome()
        } label: {
            Label("Home", systemImage: "house")
        }
    }

    /// The board, plates and dock inside the navigation bar, sized to the screen.
    private var gameScreen: some View {
        GeometryReader { screen in
            NavigationStack {
                GeometryReader { geo in
                    if bigBoard {
                        bigLayout(in: geo.size)
                    } else if theme.glows {
                        neonLayout(in: geo.size)
                    } else {
                        executiveLayout(in: geo.size)
                    }
                }
                .padding(.horizontal, bigBoard ? 0 : (theme.glows ? 8 : 12))
                .padding(.top, bigBoard ? 0 : 8)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    let coachHeight = screen.size.height * Self.coachShare
                    if bigBoard {
                        bigTray(coachHeight: coachHeight)
                    } else if theme.glows {
                        dock(coachHeight: coachHeight)
                    } else {
                        executiveDock(coachHeight: coachHeight)
                    }
                }
                .background { SheetBackdrop(theme: theme) }
                .overlay(alignment: .top) {
                    if let news = armyNews {
                        ArmyNewsBanner(news: news, color: match.setup.playerColor, theme: theme) {
                            armyNews = nil
                            showingArmy = true
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .navigationTitle("Chess Game Killer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .toolbar(bigBoard ? .hidden : .visible, for: .navigationBar)
            }
        }
    }

    /// Neon: both plates above the board, captures down its sides.
    private func neonLayout(in size: CGSize) -> some View {
        let platesHeight = coachExpanded ? Self.stripHeight : Self.platesHeight
        let spare = size.height - platesHeight - Self.ribbonHeight - Self.spacing * 2
        let railsWidth = (Self.railWidth + Self.railSpacing) * 2
        let side = max(0, min(size.width - railsWidth, spare, Self.maxBoardSide))
        let topColor: Piece.Color = match.isBoardFlipped ? .white : .black
        return VStack(spacing: Self.spacing) {
            PlayerPlates(match: match, theme: theme, compact: coachExpanded)
                .frame(height: platesHeight)
            HStack(spacing: Self.railSpacing) {
                CaptureRail(match: match, theme: theme, by: topColor, width: Self.railWidth)
                BoardView(match: match, theme: theme)
                    .frame(width: side, height: side)
                CaptureRail(match: match, theme: theme, by: topColor.opposite, width: Self.railWidth)
            }
            .frame(height: side)
            MoveRibbon(moves: match.game.moves, theme: theme)
                .frame(height: Self.ribbonHeight)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: Self.neonColumnWidth)
        .frame(maxWidth: .infinity)
    }

    /// Executive: the opponent above a full-width board and you below it, like a real match.
    /// While the coach is open the two players fold into one line.
    private func executiveLayout(in size: CGSize) -> some View {
        let compact = coachExpanded
        let platesHeight = compact ? Self.stripHeight : Self.plateHeight * 2
        let gaps: CGFloat = compact ? 4 : 5
        let spare = size.height - platesHeight - Self.ribbonHeight - Self.spacing * gaps
        let aspect = boardAspect
        let width = max(0, min(size.width, spare * aspect, Self.maxBoardSide))
        let topColor: Piece.Color = match.isBoardFlipped ? .white : .black
        return VStack(spacing: Self.spacing) {
            Spacer(minLength: 0)
            if compact {
                PlayerPlates(match: match, theme: theme, compact: true)
                    .frame(height: Self.stripHeight)
            } else {
                ExecutivePlate(match: match, theme: theme, color: topColor)
                    .frame(height: Self.plateHeight)
            }
            BoardView(match: match, theme: theme)
                .frame(width: width, height: width / aspect)
            if !compact {
                ExecutivePlate(match: match, theme: theme, color: topColor.opposite)
                    .frame(height: Self.plateHeight)
            }
            MoveRibbon(moves: match.game.moves, theme: theme)
                .frame(height: Self.ribbonHeight)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: Self.maxBoardSide)
        .frame(maxWidth: .infinity)
    }

    /// Big Board: no top bar, the board as wide as the screen (and as tall as it may be on iPad),
    /// the players hugging it above and below. Swipe sideways on the board to look back through the game.
    private func bigLayout(in size: CGSize) -> some View {
        let compact = coachExpanded
        let platesHeight = compact ? Self.stripHeight : Self.plateHeight * 2
        let gaps: CGFloat = compact ? 3 : 4
        let spare = size.height - platesHeight - Self.ribbonHeight - Self.spacing * gaps
        let aspect = boardAspect
        let side = max(0, min(size.width, spare * aspect))
        let topColor: Piece.Color = match.isBoardFlipped ? .white : .black
        return VStack(spacing: Self.spacing) {
            Spacer(minLength: 0)
            Group {
                if compact {
                    PlayerPlates(match: match, theme: theme, compact: true)
                        .frame(height: Self.stripHeight)
                } else {
                    ExecutivePlate(match: match, theme: theme, color: topColor)
                        .frame(height: Self.plateHeight)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: max(side, Self.maxBoardSide))
            browsableBoard
                .frame(width: side, height: side / aspect)
            if !compact {
                ExecutivePlate(match: match, theme: theme, color: topColor.opposite)
                    .frame(height: Self.plateHeight)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: max(side, Self.maxBoardSide))
            }
            Group {
                if let ply = browsePly {
                    let fens = match.game.positionFENs
                    BrowsePill(ply: ply, total: fens.count - 1,
                               san: ply > 0 && ply <= match.game.moves.count ? match.game.moves[ply - 1] : nil,
                               theme: theme) {
                        withAnimation(.snappy) { browsePly = nil }
                    }
                } else {
                    MoveRibbon(moves: match.game.moves, theme: theme)
                        .padding(.horizontal, 12)
                }
            }
            .frame(height: Self.ribbonHeight)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// The live board, showing an earlier position while the player looks back.
    /// Dragging sideways scrubs through the game: right goes back, left comes forward.
    private var browsableBoard: some View {
        ZStack {
            // The 3D board walks its own pieces back through the game; the flat board has
            // the earlier position laid over it.
            BoardView(match: match, theme: theme, browsing: browsedPosition) {
                withAnimation(.snappy) { browsePly = nil }
            }
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
        .sensoryFeedback(.selection, trigger: browsePly) { _, _ in true }
        .accessibilityAction(named: "Previous move") { step(by: -1) }
        .accessibilityAction(named: "Next move") { step(by: 1) }
    }

    /// The position the player is looking back at, if any.
    private var browsedPosition: Position? {
        browsePly.flatMap { match.game.positionFENs[safe: $0] }.flatMap { Position(fen: $0) }
    }

    /// Width over height of the board in play: 1 for the flat looks, wider for the 3D board.
    private var boardAspect: CGFloat {
        BoardView.aspect(theme, setting: sculpted3D)
    }

    /// One position for every ~34 points of sideways drag.
    private func scrub(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) * 1.5,
              match.game.pendingPromotion == nil else { return }
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

    /// The tray at the bottom of Big Board, holding the same controls as the normal screen.
    private func bigTray(coachHeight: CGFloat) -> some View {
        BigBoardTray(match: match, theme: theme, isOpen: $trayOpen,
                     onNewGame: { showingNewGame = true },
                     onSettings: { showingSettings = true },
                     onExit: { withAnimation(.snappy) { bigBoard = false } },
                     onArmy: theme.glows ? nil : { showingArmy = true },
                     onGames: { showingGames = true },
                     onHome: homeScreenOn ? { goHome() } : nil) {
            if theme.glows {
                VStack(spacing: 6) {
                    neonToolRow
                    dock(coachHeight: coachHeight)
                }
            } else {
                executiveDock(coachHeight: coachHeight)
            }
        }
        .onChange(of: trayOpen) { _, open in
            if !open { setCoach(expanded: false) }
        }
    }

    /// Neon keeps Analyze, Train and Army in its top bar; Big Board has none, so they come into the tray.
    private var neonToolRow: some View {
        HStack(spacing: 0) {
            DockButton(title: "Analyze", symbol: "camera.viewfinder", theme: theme) { showingAnalyze = true }
            DockButton(title: "Train", symbol: "graduationcap", theme: theme) { showingTraining = true }
            DockButton(title: "Puzzles", symbol: "puzzlepiece.extension", theme: theme) { showingPuzzles = true }
            DockButton(title: "Army", symbol: "shield.lefthalf.filled", theme: theme) { showingArmy = true }
            DockButton(title: "Flip", symbol: "arrow.up.arrow.down", theme: theme) {
                withAnimation(.snappy) { match.flipBoard() }
            }
        }
        .padding(.horizontal, 8)
        .opacity(coachIsWide ? 0 : 1)
        .allowsHitTesting(!coachIsWide)
    }

    /// Switches Big Board on.
    private var bigBoardButton: some View {
        Button {
            withAnimation(.snappy) {
                trayOpen = false
                bigBoard = true
            }
        } label: {
            Label("Big Board", systemImage: "arrow.up.left.and.arrow.down.right")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if theme.glows {
            if homeScreenOn {
                ToolbarItem(placement: .topBarLeading) { homeButton }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingAnalyze = true
                } label: {
                    Label("Analyze a Position", systemImage: "camera.viewfinder")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                TrainButton(theme: theme) { showingTraining = true }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingPuzzles = true
                } label: {
                    Label("Puzzles", systemImage: "puzzlepiece.extension")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingArmy = true
                } label: {
                    Label("Your Army", systemImage: "shield.lefthalf.filled")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Button {
                        showingNewGame = true
                    } label: {
                        Label("New Game", systemImage: "plus")
                    }
                    bigBoardButton
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 4) {
                    if homeScreenOn { homeButton }
                    Button {
                        showingNewGame = true
                    } label: {
                        Label("New Game", systemImage: "plus")
                    }
                    Button {
                        showingArmy = true
                    } label: {
                        Label("Your Army", systemImage: "shield.lefthalf.filled")
                    }
                    gamesButton
                }
                .tint(.primary)
            }
            ToolbarItem(placement: .principal) {
                ExecutiveMatchTitle(match: match)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    bigBoardButton
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                .tint(.primary)
            }
        }
    }

    /// Your saved games, to rewind.
    private var gamesButton: some View {
        Button {
            showingGames = true
        } label: {
            Label("Your Games", systemImage: "backward.circle")
        }
    }

    /// Executive: every control named, three either side of the orb. They step aside while the orb is wide.
    private func executiveDock(coachHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 4)
                .opacity(coachExpanded ? 0 : 1)
            ZStack {
                HStack(spacing: 0) {
                    HStack(spacing: 0) {
                        DockButton(title: "Analyze", symbol: "camera.viewfinder", theme: theme) {
                            showingAnalyze = true
                        }
                        DockButton(title: "Train", symbol: "graduationcap", theme: theme) {
                            showingTraining = true
                        }
                        DockButton(title: "Puzzles", symbol: "puzzlepiece.extension", theme: theme) {
                            showingPuzzles = true
                        }
                    }
                    .frame(maxWidth: .infinity)
                    // The orb's place. Only a width: a bare Color.clear takes every bit of
                    // height it is offered, which pushed the dock up and squeezed the board to nothing.
                    Color.clear.frame(width: CoachOrb.orbSize + 12, height: 1)
                    HStack(spacing: 0) {
                        DockButton(title: "Undo", symbol: "arrow.uturn.backward", theme: theme) {
                            withAnimation(.snappy(duration: 0.22)) { match.undo() }
                        }
                        .disabled(!match.canUndo)
                        DockButton(title: "Hint", symbol: showBestMoves ? "lightbulb.fill" : "lightbulb",
                                   isOn: showBestMoves, theme: theme) {
                            showBestMoves.toggle()
                        }
                        DockButton(title: "Flip", symbol: "arrow.up.arrow.down", theme: theme) {
                            withAnimation(.snappy) { match.flipBoard() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .opacity(coachIsWide ? 0 : 1)
                .scaleEffect(coachIsWide ? 0.92 : 1)
                .allowsHitTesting(!coachIsWide)
                CoachOrb(match: match, theme: theme, isExpanded: $coachExpanded, isPeeking: $coachPeeking,
                         expandedMaxHeight: coachHeight) {
                    showingNewGame = true
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: Self.maxBoardSide + 8)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: coachIsWide)
    }

    /// Undo and Hints either side of the orb. They step aside while the orb is wide.
    private func dock(coachHeight: CGFloat) -> some View {
        ZStack {
            HStack {
                RoundButton(title: "Undo", symbol: "arrow.uturn.backward", theme: theme) {
                    withAnimation(.snappy(duration: 0.22)) { match.undo() }
                }
                .disabled(!match.canUndo)
                Spacer()
                RoundButton(title: "Hints", symbol: showBestMoves ? "lightbulb.fill" : "lightbulb.slash",
                            isOn: showBestMoves, theme: theme) {
                    showBestMoves.toggle()
                }
            }
            .opacity(coachIsWide ? 0 : 1)
            .scaleEffect(coachIsWide ? 0.85 : 1)
            .allowsHitTesting(!coachIsWide)
            CoachOrb(match: match, theme: theme, isExpanded: $coachExpanded, isPeeking: $coachPeeking,
                     expandedMaxHeight: coachHeight) {
                showingNewGame = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: Self.neonColumnWidth + 16)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: coachIsWide)
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
        show(news, after: 1.2)
    }

    /// As a game against a rival starts: the piece that rival keeps taking.
    private func announceGrudge() {
        guard match.setup.opponent == .computer, match.game.ledger != nil,
              let news = army.grudge(against: match.setup.level) else { return }
        show(news, after: 0.6)
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

    /// The same rival again, from a rewound game.
    private func playAgain(_ game: SavedGame) {
        var setup = NewGameSheet.savedSetup()
        if let raw = game.level, let level = MatchController.Level(rawValue: raw) {
            setup.opponent = .computer
            setup.level = level
            setup.playerColor = game.playerColor
        }
        withAnimation(.snappy) { match.start(setup) }
        showingNewGame = false
        leaveHome()
    }

    /// Starts a game from an analyzed position, with the player moving first.
    private func play(from draft: PositionDraft) {
        guard let position = draft.position else { return }
        var setup = NewGameSheet.savedSetup()
        setup.playerColor = draft.sideToMove
        withAnimation(.snappy) { match.start(setup, from: position) }
        leaveHome()
    }

    /// Closing the sheet without starting still begins a game, with last time's choices.
    private func startIfNeeded() {
        // From the home screen, closing the sheet just goes back home.
        if !match.hasStarted, !showingHome {
            match.start(NewGameSheet.savedSetup(), playSound: false)
        }
    }
}

/// Opens Coach Leo's training: lessons, puzzles and your own mistakes to fix.
/// A filled circle in the theme's accent, so it stands out from the plain toolbar icons.
private struct TrainButton: View {
    let theme: BoardTheme
    let action: () -> Void

    var body: some View {
        let accent = theme.trainingAccent
        Button(action: action) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.isDark ? Color.black : Color.white)
                .frame(width: 32, height: 32)
                .background(accent, in: Circle())
                .shadow(color: theme.glows ? accent.opacity(0.6) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Train with Coach Leo")
        .accessibilityHint("Lessons, puzzles and your own mistakes to practice")
    }
}

/// A round button with a caption under it, for either side of the orb.
private struct RoundButton: View {
    let title: String
    let symbol: String
    /// Set for a toggle, so VoiceOver can say which way it is.
    var isOn: Bool? = nil
    let theme: BoardTheme
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private var accent: Color { theme.accent ?? .accentColor }
    private var lit: Bool { isOn == true }
    /// What VoiceOver says after the name: the state of a toggle, nothing for a plain button.
    private var spokenState: String { isOn.map { $0 ? "On" : "Off" } ?? "" }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(
                        theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                        in: Circle()
                    )
                    .overlay {
                        Circle().strokeBorder(lit ? accent.opacity(0.6) : Color.primary.opacity(theme.isDark ? 0.12 : 0.08), lineWidth: 1)
                    }
                    .shadow(color: theme.glows ? (lit ? accent.opacity(0.3) : .clear) : .black.opacity(0.1),
                            radius: theme.glows ? 10 : 6, y: theme.glows ? 0 : 2)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(lit ? accent : Color.primary.opacity(0.85))
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(spokenState)
        .accessibilityAddTraits(isOn == nil ? [] : .isToggle)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

#Preview { ContentView() }
