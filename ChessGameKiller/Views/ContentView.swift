import SwiftUI

struct ContentView: View {
    @State private var match = MatchController.live()
    @State private var showingNewGame = true
    @State private var showingAnalyze = false
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .walnut
    @AppStorage("soundEffects") private var soundOn = true
    @AppStorage("showBestMoves") private var showBestMoves = true
    @State private var training = TrainingStore.live()
    @State private var coach = GameCoach()
    @State private var showingTraining = false

    private var theme: BoardTheme { .named(themeID) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                StatusBar(match: match, theme: theme)
                BoardView(match: match, theme: theme)
                Spacer(minLength: 0)
                CoachBar(match: match, theme: theme)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if theme.isDark {
                    NeonBackdrop()
                } else {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                }
            }
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
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsMenu(themeID: $themeID, soundOn: $soundOn, showBestMoves: $showBestMoves)
                }
                ToolbarItem(placement: .topBarLeading) {
                    TrainButton(theme: theme) { showingTraining = true }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        showingNewGame = true
                    } label: {
                        Label("New Game", systemImage: "plus.circle")
                    }
                    .labelStyle(.titleAndIcon)
                    Spacer()
                    Button {
                        showBestMoves.toggle()
                    } label: {
                        Label("Best Moves", systemImage: showBestMoves ? "lightbulb.fill" : "lightbulb.slash")
                    }
                    .labelStyle(.titleAndIcon)
                    .accessibilityValue(showBestMoves ? "On" : "Off")
                    Spacer()
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { match.undo() }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .labelStyle(.titleAndIcon)
                    .disabled(!match.canUndo)
                }
            }
            .toolbarBackground(theme.isDark ? .visible : .automatic, for: .bottomBar)
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .environment(training)
        .environment(coach)
        .onChange(of: match.review) { _, review in
            coach.observe(review, in: match, store: training)
        }
        .fullScreenCover(isPresented: $showingTraining) {
            TrainingHubView().environment(training)
        }
        .fullScreenCover(item: $coach.presentedLesson) { lesson in
            LessonScreen(lesson: lesson, theme: theme).environment(training)
        }
        .fullScreenCover(item: $coach.presentedSession) { plan in
            SessionView(plan: plan, theme: theme).environment(training)
        }
        .animation(.easeInOut(duration: 0.35), value: themeID)
        .sheet(isPresented: $showingNewGame, onDismiss: startIfNeeded) {
            NewGameSheet(theme: theme) { setup in
                withAnimation(.snappy) { match.start(setup) }
                showingNewGame = false
            }
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
        .onAppear { match.showBestMoves = showBestMoves }
        .onChange(of: showBestMoves) { _, show in match.showBestMoves = show }
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
private struct TrainButton: View {
    let theme: BoardTheme
    let action: () -> Void

    var body: some View {
        let accent = theme.trainingAccent
        Button(action: action) {
            Label("Train", systemImage: "graduationcap.fill")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(theme.isDark ? Color.black : Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(accent, in: Capsule())
                .shadow(color: theme.isDark ? accent.opacity(0.6) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Lessons, puzzles and your own mistakes to practice")
    }
}

/// Top-right menu: board look, sound and best-move arrows. Choices are remembered.
private struct SettingsMenu: View {
    @Binding var themeID: BoardTheme.ID
    @Binding var soundOn: Bool
    @Binding var showBestMoves: Bool

    var body: some View {
        Menu {
            Picker("Board", selection: $themeID) {
                ForEach(BoardTheme.all) { theme in
                    Label(theme.name, systemImage: theme.symbol).tag(theme.id)
                }
            }
            Section {
                Toggle(isOn: $soundOn) {
                    Label("Sound Effects", systemImage: "speaker.wave.2.fill")
                }
                Toggle(isOn: $showBestMoves) {
                    Label("Best-Move Arrows", systemImage: "arrow.up.right")
                }
            }
        } label: {
            Label("Settings", systemImage: "slider.horizontal.3")
        }
    }
}

/// Whose turn it is or how the game ended, and who the opponent is.
private struct StatusBar: View {
    let match: MatchController
    let theme: BoardTheme

    private var game: GameModel { match.game }

    var body: some View {
        let sideColor = theme.sideColor(game.sideToMove)
        let status = game.status(white: theme.whiteName, black: theme.blackName)
        HStack(spacing: 10) {
            Circle()
                .fill(sideColor)
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: theme.isDark ? 0 : 1))
                .frame(width: 14, height: 14)
                .shadow(color: theme.isDark ? sideColor : .clear, radius: 5)
            Text(status)
                .font(.headline)
                .foregroundStyle(game.isGameOver ? (theme.accent ?? .accentColor) : Color.primary)
                .contentTransition(.opacity)
            Spacer()
            Text(opponentText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(theme.isDark ? 0.18 : 0.12), in: Capsule())
        }
        .padding(.horizontal, 4)
        .animation(.snappy, value: status)
        .accessibilityElement(children: .combine)
    }

    private var opponentText: String {
        let setup = match.setup
        switch setup.opponent {
        case .computer: return "vs Computer · \(setup.level.name)"
        case .friend: return "vs Friend"
        }
    }
}

#Preview { ContentView() }
