import ChessKit
import SwiftUI

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
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .neon
    @AppStorage("matchRival") private var matchRival = true
    @AppStorage("showBestMoves") private var showBestMoves = true
    @AppStorage("showSecondBest") private var showSecondBest = true
    @AppStorage("coachVerdicts") private var showVerdicts = true
    @State private var training = TrainingStore.live()
    @State private var coach = GameCoach()
    @State private var showingTraining = false
    @State private var army = ArmyStore.live()
    @State private var showingArmy = false
    @State private var armyNews: ArmyNews?

    /// Against the computer, the board matches the rival's portrait unless the player turned that off.
    private var theme: BoardTheme {
        if matchRival, match.setup.opponent == .computer {
            return .named(match.setup.level.rival.boardTheme)
        }
        return .named(themeID)
    }
    /// The orb is stretched or unfolded, so nothing else fits beside it.
    private var coachIsWide: Bool { coachExpanded || coachPeeking }

    private static let spacing: CGFloat = 12
    private static let platesHeight: CGFloat = 64
    /// One executive player line.
    private static let plateHeight: CGFloat = 50
    private static let stripHeight: CGFloat = 30
    private static let ribbonHeight: CGFloat = 24
    /// The captured-piece rails either side of the board.
    private static let railWidth: CGFloat = 26
    private static let railSpacing: CGFloat = 6

    var body: some View {
        // Fonts read the look from here: rounded on Neon, plain SF Pro on the rest.
        let _ = ThemeFont.use(theme)
        NavigationStack {
            GeometryReader { geo in
                if theme.glows {
                    neonLayout(in: geo.size)
                } else {
                    executiveLayout(in: geo.size)
                }
            }
            .padding(.horizontal, theme.glows ? 8 : 12)
            .padding(.top, 8)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if theme.glows { dock } else { executiveDock }
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
        }
        // Switching between Neon and the executive look redraws everything in the new type.
        .id(theme.glows)
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .environment(training)
        .environment(coach)
        .environment(army)
        .onChange(of: match.review) { _, review in
            coach.observe(review, in: match, store: training)
        }
        .fullScreenCover(isPresented: $showingTraining) {
            TrainingHubView(theme: theme).environment(training)
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
        .onAppear { syncCoachSettings() }
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
        .onChange(of: match.isOver) { _, over in
            guard over else { return }
            recordArmy()
            // Let the last move land and the sound play, then open the summary.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.4))
                guard match.isOver, !showingNewGame else { return }
                setCoach(expanded: true)
            }
        }
    }

    /// Neon: both plates above the board, captures down its sides.
    private func neonLayout(in size: CGSize) -> some View {
        let platesHeight = coachExpanded ? Self.stripHeight : Self.platesHeight
        let spare = size.height - platesHeight - Self.ribbonHeight - Self.spacing * 2
        let railsWidth = (Self.railWidth + Self.railSpacing) * 2
        let side = max(0, min(size.width - railsWidth, spare))
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
        .frame(maxWidth: .infinity)
    }

    /// Executive: the opponent above a full-width board and you below it, like a real match.
    /// While the coach is open the two players fold into one line.
    private func executiveLayout(in size: CGSize) -> some View {
        let compact = coachExpanded
        let platesHeight = compact ? Self.stripHeight : Self.plateHeight * 2
        let gaps: CGFloat = compact ? 4 : 5
        let spare = size.height - platesHeight - Self.ribbonHeight - Self.spacing * gaps
        let side = max(0, min(size.width, spare))
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
                .frame(width: side, height: side)
            if !compact {
                ExecutivePlate(match: match, theme: theme, color: topColor.opposite)
                    .frame(height: Self.plateHeight)
            }
            MoveRibbon(moves: match.game.moves, theme: theme)
                .frame(height: Self.ribbonHeight)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if theme.glows {
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
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingNewGame = true
                } label: {
                    Label("New Game", systemImage: "plus")
                }
                .tint(.primary)
            }
            ToolbarItem(placement: .principal) {
                ExecutiveMatchTitle(match: match)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .tint(.primary)
            }
        }
    }

    /// Executive: every control named, three either side of the orb. They step aside while the orb is wide.
    private var executiveDock: some View {
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
                        DockButton(title: "Undo", symbol: "arrow.uturn.backward", theme: theme) {
                            withAnimation(.snappy(duration: 0.22)) { match.undo() }
                        }
                        .disabled(!match.canUndo)
                    }
                    .frame(maxWidth: .infinity)
                    Color.clear.frame(width: CoachOrb.orbSize + 12)
                    HStack(spacing: 0) {
                        DockButton(title: "Hint", symbol: showBestMoves ? "lightbulb.fill" : "lightbulb",
                                   isOn: showBestMoves, theme: theme) {
                            showBestMoves.toggle()
                        }
                        DockButton(title: "Army", symbol: "shield.lefthalf.filled", theme: theme) {
                            showingArmy = true
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
                CoachOrb(match: match, theme: theme, isExpanded: $coachExpanded, isPeeking: $coachPeeking) {
                    showingNewGame = true
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: coachIsWide)
    }

    /// Undo and Hints either side of the orb. They step aside while the orb is wide.
    private var dock: some View {
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
            CoachOrb(match: match, theme: theme, isExpanded: $coachExpanded, isPeeking: $coachPeeking) {
                showingNewGame = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
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
        guard let news = army.record(ledger, playerColor: match.setup.playerColor, won: won).first else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { armyNews = news }
            try? await Task.sleep(for: .seconds(6))
            if armyNews == news {
                withAnimation(.easeOut(duration: 0.3)) { armyNews = nil }
            }
        }
    }

    /// Starts a game from an analyzed position, with the player moving first.
    private func play(from draft: PositionDraft) {
        guard let position = draft.position else { return }
        var setup = NewGameSheet.savedSetup()
        setup.playerColor = draft.sideToMove
        withAnimation(.snappy) { match.start(setup, from: position) }
    }

    /// Closing the sheet without starting still begins a game, with last time's choices.
    private func startIfNeeded() {
        if !match.hasStarted {
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
    var isOn = false
    let theme: BoardTheme
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private var accent: Color { theme.accent ?? .accentColor }

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
                        Circle().strokeBorder(isOn ? accent.opacity(0.6) : Color.primary.opacity(theme.isDark ? 0.12 : 0.08), lineWidth: 1)
                    }
                    .shadow(color: theme.glows ? (isOn ? accent.opacity(0.3) : .clear) : .black.opacity(0.1),
                            radius: theme.glows ? 10 : 6, y: theme.glows ? 0 : 2)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isOn ? accent : Color.primary.opacity(0.85))
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "")
    }
}

#Preview { ContentView() }
