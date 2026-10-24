import ChessKit
import SwiftUI

/// The Train screen: one thing to do today, picked by the coach from the player's own
/// games and progress, and six doors to everything else. It fits on one screen; each
/// door opens its own short page.
struct TrainingHubView: View {
    /// The game screen's board look, so training looks like the game.
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var store
    @Environment(PuzzleStore.self) private var puzzles
    @Environment(GameVault.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @AppStorage("coachVoiceMuted") private var voiceMuted = false
    @AppStorage(CoachReactions.storageKey) private var reactionsOn = true
    @State private var coachChoice = CoachChoice.shared
    @State private var repertoire = RepertoireStore.live()
    /// The endgame record the whole app shares, so a study finished anywhere shows here.
    private var endgames: EndgameProgress { .shared }
    @State private var think = ThinkStore.live()
    @State private var path: [TrainDoor] = []
    /// Today's session, made once so the card shows exactly what Start plays.
    @State private var today: SessionPlan?
    @State private var session: SessionPlan?
    @State private var greeting = ""
    @State private var confirmingReset = false
    @State private var showingLevelCheck = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                if store.library != nil {
                    VStack(alignment: .leading, spacing: 16) {
                        coachLine
                        TodayCard(plan: today, theme: theme, offersLevelCheck: offersLevelCheck) {
                            session = today ?? store.dailyPlan()
                        } levelCheck: {
                            showingLevelCheck = true
                        }
                        doors
                        RankStrip(theme: theme)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                } else {
                    missingContent
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background { TrainingBackdrop(theme: theme) }
            .navigationTitle("Train")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbar }
            .navigationDestination(for: TrainDoor.self) { door in
                destination(door)
            }
        }
        .tint(theme.trainingAccent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .environment(repertoire)
        .environment(endgames)
        .environment(think)
        .onAppear {
            if greeting.isEmpty {
                greeting = store.library?.course.lines.greeting.randomElement() ?? "Ready when you are."
            }
            // On the course, today's plan is ready at once; past it, it waits for the puzzles.
            if today == nil, !isPastTheCourse {
                today = store.dailyPlan()
            }
        }
        .task { await planToday() }
        .confirmationDialog("Start training over?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Erase training progress", role: .destructive) {
                store.reset()
                Task { await planToday() }
            }
        } message: {
            Text("Your XP, rank, streak and saved mistakes will be erased. Games and puzzles aren't affected.")
        }
        .fullScreenCover(item: $session, onDismiss: { Task { await planToday() } }) { plan in
            SessionView(plan: plan, theme: theme, startsAtOnce: true)
                .environment(store)
                .environment(puzzles)
        }
        .fullScreenCover(isPresented: $showingLevelCheck, onDismiss: { Task { await planToday() } }) {
            LevelCheckView(theme: theme) { rating in
                if let rating {
                    store.applyLevel(rating)
                    puzzles.calibrate(rating: rating)
                }
                showingLevelCheck = false
            }
            .environment(puzzles)
            .environment(think)
        }
    }

    // MARK: Today

    private var offersLevelCheck: Bool {
        store.offersLevelCheck && today?.headline == nil
    }

    private var isPastTheCourse: Bool {
        store.isPastTheCourse(puzzleRating: puzzles.progress.rating, puzzlesPlayed: puzzles.progress.played)
    }

    /// Builds today's session: the course while there's course left, then real puzzles at
    /// the player's level aimed at what their games say is weakest.
    private func planToday() async {
        today = await store.planToday(puzzles: puzzles, games: vault.games)
    }

    private var coachLine: some View {
        HStack(alignment: .center, spacing: 12) {
            coachMenu
            Text(greeting)
                .font(.system(.subheadline, design: .themed))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            StreakPill(streak: store.streak, theme: theme)
        }
        .padding(.top, 2)
    }

    /// The coach's portrait; tap it to switch between Leo and Vera.
    private var coachMenu: some View {
        Menu {
            Picker("Your coach", selection: coachBinding) {
                ForEach(Coach.allCases) { coach in
                    Text(coach.title).tag(coach)
                }
            }
        } label: {
            CoachAvatar(theme: theme, size: 34)
        }
        .accessibilityLabel("Your coach: \(coachChoice.coach.title)")
        .accessibilityHint("Switch between Coach Leo and Coach Vera.")
    }

    private var coachBinding: Binding<Coach> {
        Binding {
            coachChoice.coach
        } set: { coach in
            coachChoice.coach = coach
            CoachReactions.shared.preview(coach)
        }
    }

    // MARK: Doors

    private var doors: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(TrainDoor.allCases) { door in
                NavigationLink(value: door) {
                    DoorTile(door: door, status: status(of: door), badge: badge(of: door), theme: theme)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func status(of door: TrainDoor) -> String {
        switch door {
        case .puzzles:
            return "Rating \(puzzles.progress.rating)"
        case .lessons:
            let total = store.library?.lessons.count ?? 0
            return "\(store.lessonsDoneCount) of \(total) watched"
        case .openings:
            if !repertoire.due.isEmpty { return "\(repertoire.due.count) to review" }
            return repertoire.entries.isEmpty ? "Build your repertoire" : "\(repertoire.entries.count) lines learned"
        case .endgames:
            if endgames.allDone { return "All \(endgames.total) learned" }
            return endgames.doneCount == 0 ? "\(endgames.total) must-know endings" : "\(endgames.doneCount) of \(endgames.total) learned"
        case .calculation:
            if think.progress.rounds > 0 { return "Candidates best \(think.progress.bestRound)" }
            let vision = VisionStore.live()
            if let scan = vision.bestScanPercent { return "Board scan best \(scan)%" }
            if vision.bestSquares > 0 { return "Coordinates best \(vision.bestSquares)" }
            return "See it before you play it"
        case .games:
            let open = store.openMistakes.count
            if open > 0 { return open == 1 ? "1 position to fix" : "\(open) positions to fix" }
            return vault.games.isEmpty ? "Play a game first" : "Your Chess DNA and what to fix"
        }
    }

    /// Things due today get a count, so the player knows where to look.
    private func badge(of door: TrainDoor) -> Int {
        switch door {
        case .puzzles: return puzzles.reviewsDue
        case .openings: return repertoire.due.count
        case .games: return store.dueMistakeCount
        case .endgames: return endgames.dueForReview().count
        default: return 0
        }
    }

    @ViewBuilder
    private func destination(_ door: TrainDoor) -> some View {
        switch door {
        case .puzzles: PuzzlesDoorView(theme: theme)
        case .lessons: LessonsDoorView(theme: theme)
        case .openings: OpeningsView(theme: theme)
        case .endgames: EndgamesDoorView(theme: theme)
        case .calculation: CalculationDoorView(theme: theme)
        case .games: GamesDoorView(theme: theme)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: Binding(get: { !voiceMuted }, set: { voiceMuted = !$0 })) {
                    Label("Coach's voice", systemImage: "speaker.wave.2.fill")
                }
                Toggle(isOn: $reactionsOn) {
                    Label("Voice reactions", systemImage: "bubble.left.and.text.bubble.right.fill")
                }
                .disabled(voiceMuted)
                Button {
                    showingLevelCheck = true
                } label: {
                    Label {
                        Text("Find my level")
                        if let level = think.levelStatus {
                            Text(level)
                        }
                    } icon: {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                    }
                }
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Label("Start training over", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Label("Training settings", systemImage: "ellipsis.circle")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
        }
    }

    private var missingContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Training content is missing from this build.")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

/// Today's session at a glance: what it works on and why, what's in it, a peek at the
/// first position, and one big Start.
struct TodayCard: View {
    let plan: SessionPlan?
    let theme: BoardTheme
    var offersLevelCheck = false
    let start: () -> Void
    var levelCheck: () -> Void = {}
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let done = store.trainedToday
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow(done: done))
                        .font(.system(.caption, design: .themed).weight(.bold))
                        .tracking(1)
                        .foregroundStyle(theme.trainingAccent)
                    Text(title)
                        .font(.system(.title2, design: .themed).weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(reason)
                        .font(.system(.subheadline, design: .themed))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let fen = previewFEN {
                    BoardThumbnail(fen: fen, theme: theme)
                        .frame(width: 92, height: 92)
                        .id(fen)
                }
            }
            if let plan {
                steps(plan)
            }
            Button(action: start) {
                Label(done ? "Train more" : "Start", systemImage: "play.fill")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: !done))
            .disabled(plan == nil)
            if offersLevelCheck {
                Button(action: levelCheck) {
                    Text("Already a strong player? Find your level in 2 minutes")
                        .font(.system(.footnote, design: .themed).weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.trainingAccent)
            }
        }
        .padding(18)
        .trainingCard(theme, tint: theme.trainingAccent)
    }

    private func eyebrow(done: Bool) -> String {
        if done { return "TODAY · DONE" }
        return "TODAY · \(plan?.minutes ?? store.todaysMinutes) MIN"
    }

    private var title: String {
        if store.trainedToday, plan == nil { return "Nice work today" }
        if let lesson = plan?.lesson, lesson.id == store.library?.lessons.first?.id { return "Welcome to training" }
        return plan?.headline ?? plan?.focus?.title ?? store.todaysFocus?.title ?? "Today's training"
    }

    private var reason: String {
        if store.trainedToday {
            return "You've trained today and your streak is safe. Another round is always welcome."
        }
        if let reason = plan?.reason { return reason }
        switch store.todaysFocusReason {
        case .firstDay?:
            return "Meet \(Coach.current.title) and the one habit that wins more games than any opening."
        case .fromGames(let count)?:
            return "You missed this \(count == 2 ? "twice" : "\(count) times") in your games lately. Let's make it automatic."
        case .struggling?:
            return "This one's been tricky. A few friendlier positions to lock it in."
        case .nextOnPath?:
            if let lesson = plan?.lesson { return "New lesson: \(lesson.title), then practice at your level." }
            return plan?.focus?.blurb ?? "The next step on your path."
        case .polish?, nil:
            return plan?.focus?.blurb ?? "A short session at your level."
        }
    }

    private func steps(_ plan: SessionPlan) -> some View {
        let mistakes = plan.items.filter {
            if case .mistake = $0.content { return true } else { return false }
        }.count
        let drills = plan.items.count - mistakes
        return HStack(spacing: 6) {
            if plan.lesson != nil {
                TrainingChip(text: "Lesson", symbol: "play.rectangle.fill", color: theme.trainingAccent)
            }
            if drills > 0 {
                TrainingChip(text: drills == 1 ? "1 puzzle" : "\(drills) puzzles", symbol: "puzzlepiece.fill",
                             color: theme.trainingAccent)
            }
            if mistakes > 0 {
                TrainingChip(text: mistakes == 1 ? "1 from your games" : "\(mistakes) from your games",
                             symbol: "arrow.uturn.backward", color: theme.trainingAccent)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    /// The first position the session shows, from the side that will play it.
    private var previewFEN: String? {
        guard let plan else { return nil }
        if let lesson = plan.lesson {
            return lesson.steps.first { $0.fen != nil }?.fen
        }
        switch plan.items.first?.content {
        case .drill(let drill)?:
            return drill.setup.flatMap { TrainingChess.fen(after: [$0], from: drill.fen) } ?? drill.fen
        case .mistake(let mistake)?:
            return mistake.fen
        case nil:
            return nil
        }
    }
}

/// A small, still picture of a position on the player's board, from the side to move.
struct BoardThumbnail: View {
    let theme: BoardTheme
    @State private var game: GameModel
    private let flipped: Bool

    init(fen: String, theme: BoardTheme) {
        self.theme = theme
        let position = Position(fen: fen) ?? .standard
        let model = GameModel(position: position)
        model.humanColors = []
        _game = State(initialValue: model)
        flipped = position.sideToMove == .black
    }

    var body: some View {
        TrainingBoardView(game: game, theme: theme, flipped: flipped)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
