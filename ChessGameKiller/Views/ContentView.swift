import ChessKit
import SwiftUI

/// The game screen: the two players, the board with each side's captures
/// counted down its edge, the moves so far, and the coach orb at the bottom
/// with Undo and Hints either side of it. When the orb unfolds, the player
/// plates fold into one line and the board makes room.
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
    private static let stripHeight: CGFloat = 30
    private static let ribbonHeight: CGFloat = 24
    /// The captured-piece rails either side of the board.
    private static let railWidth: CGFloat = 26
    private static let railSpacing: CGFloat = 6

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let platesHeight = coachExpanded ? Self.stripHeight : Self.platesHeight
                let spare = geo.size.height - platesHeight - Self.ribbonHeight - Self.spacing * 2
                let railsWidth = (Self.railWidth + Self.railSpacing) * 2
                let side = max(0, min(geo.size.width - railsWidth, spare))
                let topColor: Piece.Color = match.isBoardFlipped ? .white : .black
                VStack(spacing: Self.spacing) {
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
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .safeAreaInset(edge: .bottom, spacing: 0) { dock }
            .background { SheetBackdrop(theme: theme) }
            .navigationTitle("Chess Game Killer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .environment(training)
        .environment(coach)
        .onChange(of: match.review) { _, review in
            coach.observe(review, in: match, store: training)
        }
        .fullScreenCover(isPresented: $showingTraining) {
            TrainingHubView(theme: theme).environment(training)
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
            // Let the last move land and the sound play, then open the summary.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.4))
                guard match.isOver, !showingNewGame else { return }
                setCoach(expanded: true)
            }
        }
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
                .shadow(color: theme.isDark ? accent.opacity(0.6) : .clear, radius: 8)
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
                    .shadow(color: theme.isDark ? (isOn ? accent.opacity(0.3) : .clear) : .black.opacity(0.1),
                            radius: theme.isDark ? 10 : 6, y: theme.isDark ? 0 : 2)
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
