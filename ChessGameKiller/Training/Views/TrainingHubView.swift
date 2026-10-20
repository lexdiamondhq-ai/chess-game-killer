import ChessKit
import SwiftUI

/// The Training screen: Coach Leo, today's session, the learner's own
/// mistakes to fix, the Traffic Light habit, and the whole journey.
struct TrainingHubView: View {
    /// The game screen's board look, so training looks like the game.
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var store
    @Environment(PuzzleStore.self) private var puzzles
    @State private var showingPuzzles = false
    @State private var showingRoom = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("coachVoiceMuted") private var voiceMuted = false
    @State private var lesson: Lesson?
    @State private var session: SessionPlan?
    @State private var greeting = ""
    @State private var confirmingReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let library = store.library {
                    VStack(spacing: 18) {
                        coachHeader(library)
                        rankCard
                        todayCard
                        puzzlesCard
                        roomCard
                        if !store.openMistakes.isEmpty {
                            mistakesCard
                        }
                        habitCard(library)
                        ForEach(library.course.units) { unit in
                            UnitCard(unit: unit, library: library, theme: theme) { lesson in
                                self.lesson = lesson
                            } practice: { skill in
                                session = store.practicePlan(for: skill)
                            }
                        }
                        Text("Every puzzle here was checked by Stockfish.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else {
                    missingContent
                }
            }
            .background { TrainingBackdrop(theme: theme) }
            .navigationTitle("Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: Binding(get: { !voiceMuted }, set: { voiceMuted = !$0 })) {
                            Label("Coach's Voice", systemImage: "speaker.wave.2.fill")
                        }
                        Button(role: .destructive) {
                            confirmingReset = true
                        } label: {
                            Label("Start Training Over", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Label("Training Settings", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Start training over?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Erase Training Progress", role: .destructive) { store.reset() }
            } message: {
                Text("Your XP, rank, streak and saved mistakes will be erased. Games aren't affected.")
            }
        }
        .tint(theme.trainingAccent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .onAppear {
            if greeting.isEmpty {
                greeting = store.library?.course.lines.greeting.randomElement() ?? "Ready when you are."
            }
        }
        .fullScreenCover(item: $lesson) { lesson in
            LessonScreen(lesson: lesson, theme: theme)
                .environment(store)
        }
        .fullScreenCover(isPresented: $showingRoom) {
            GrandmasterRoomView(theme: theme)
                .environment(puzzles)
        }
        .fullScreenCover(isPresented: $showingPuzzles) {
            PuzzlesView(theme: theme)
                .environment(puzzles)
                .environment(store)
        }
        .fullScreenCover(item: $session) { plan in
            SessionView(plan: plan, theme: theme)
                .environment(store)
        }
    }

    // MARK: Coach

    private func coachHeader(_ library: TrainingLibrary) -> some View {
        HStack(alignment: .center, spacing: 14) {
            CoachAvatar(theme: theme, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(library.coach.name)
                        .font(.system(.title3, design: .themed).weight(.bold))
                    Text(library.coach.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(greeting)
                    .font(.system(.subheadline, design: .themed))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            streakBadge
        }
        .padding(.top, 4)
    }

    private var streakBadge: some View {
        let streak = store.streak
        let color = TrainingColor.orange.color(on: theme)
        return VStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(streak > 0 ? color : Color.secondary.opacity(0.5))
                .shadow(color: theme.glows && streak > 0 ? color : .clear, radius: 8)
                .symbolEffect(.bounce, value: streak)
            Text("\(streak)")
                .font(.system(.headline, design: .themed).monospacedDigit())
            Text(streak == 1 ? "day" : "days")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak: \(streak) \(streak == 1 ? "day" : "days")")
    }

    @ViewBuilder
    private var rankCard: some View {
        if let rank = store.rank {
            HStack(spacing: 14) {
                PieceImage(piece: Piece(rank.pieceKind, color: .white, square: .a1), theme: theme, size: 48)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(rank.title)
                            .font(.system(.headline, design: .themed))
                        Text("\(store.progress.xp) XP")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let next = store.nextRank {
                            Text("Next: \(next.title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: store.rankProgress)
                        .tint(theme.trainingAccent)
                }
            }
            .padding(16)
            .trainingCard(theme)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Today

    /// Real-game puzzles from Lichess, at the learner's level.
    private var puzzlesCard: some View {
        Button {
            showingPuzzles = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.trainingAccent)
                    .frame(width: 52, height: 52)
                    .background(theme.trainingAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Puzzles")
                        .font(.system(.title3, design: .themed).weight(.bold))
                    Text("Real games, every theme, rated to your level. Plus Puzzle Rush.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text("\(puzzles.progress.rating)")
                        .font(.system(.headline, design: .themed).monospacedDigit())
                    Text("rating")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .trainingCard(theme)
        }
        .buttonStyle(.plain)
    }

    /// Training for strong players.
    private var roomCard: some View {
        Button {
            showingRoom = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.trainingAccent)
                    .frame(width: 52, height: 52)
                    .background(theme.trainingAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Grandmaster Room")
                        .font(.system(.title3, design: .themed).weight(.bold))
                    Text("Guess the Move, blindfold calculation, perfect endgames, your opening repertoire.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .trainingCard(theme)
        }
        .buttonStyle(.plain)
    }

    private var todayCard: some View {
        let focus = store.todaysFocus
        let newLesson = store.todaysLesson
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TrainingChip(text: store.trainedToday ? "Done today. More?" : "Today's training",
                             symbol: store.trainedToday ? "checkmark" : "sun.max.fill",
                             color: theme.trainingAccent)
                Spacer()
                Text("About \(store.todaysMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let focus {
                HStack(spacing: 14) {
                    Image(systemName: focus.symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(theme.trainingAccent)
                        .frame(width: 52, height: 52)
                        .background(theme.trainingAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(focus.title)
                            .font(.system(.title3, design: .themed).weight(.bold))
                        Text(newLesson.map { "New lesson: \($0.title), then practice" } ?? focus.blurb)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button {
                session = store.dailyPlan()
            } label: {
                Label("Start training", systemImage: "play.fill")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
        }
        .padding(18)
        .trainingCard(theme, tint: theme.trainingAccent)
    }

    private var mistakesCard: some View {
        let count = store.openMistakes.count
        let pink = TrainingColor.pink.color(on: theme)
        return HStack(spacing: 14) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(pink)
                .shadow(color: theme.glows ? pink : .clear, radius: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your mistakes, your puzzles")
                    .font(.system(.headline, design: .themed))
                Text(count == 1 ? "1 position saved from your games" : "\(count) positions saved from your games")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Fix") {
                session = store.mistakesPlan()
            }
            .font(.system(.subheadline, design: .themed).weight(.bold))
            .buttonStyle(.borderedProminent)
            .tint(pink)
            .foregroundStyle(theme.isDark ? Color.black : Color.white)
            .buttonBorderShape(.capsule)
        }
        .padding(16)
        .trainingCard(theme, tint: pink)
    }

    // MARK: The habit

    private func habitCard(_ library: TrainingLibrary) -> some View {
        let colors: [TrainingColor] = [.red, .yellow, .green]
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("The Traffic Light")
                    .font(.system(.headline, design: .themed))
                Spacer()
                TrafficLightDots(theme: theme, size: 9)
            }
            Text("Three questions before every move. This one habit wins more games than any opening.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(library.course.habit.enumerated()), id: \.offset) { index, light in
                let color = colors[index % colors.count].color(on: theme)
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(color)
                        .frame(width: 14, height: 14)
                        .shadow(color: theme.glows ? color : .clear, radius: 5)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(light.question)
                            .font(.system(.subheadline, design: .themed).weight(.semibold))
                        Text(light.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let first = library.lessons.first {
                Button {
                    lesson = first
                } label: {
                    Label("Watch: \(first.title)", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
            }
        }
        .padding(18)
        .trainingCard(theme)
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
        .padding(40)
    }
}

/// One unit of the journey: its lessons to watch and skills to practice.
struct UnitCard: View {
    let unit: CourseUnit
    let library: TrainingLibrary
    let theme: BoardTheme
    let watch: (Lesson) -> Void
    let practice: (Skill) -> Void
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let color = unit.color.color(on: theme)
        let lessons = unit.lessons.compactMap { library.lesson($0) }
        let skills = unit.skills.compactMap { library.skill($0) }
        let done = lessons.filter { store.isDone($0.id) }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: unit.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.isDark ? Color.black : Color.white)
                    .frame(width: 40, height: 40)
                    .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: theme.glows ? color.opacity(0.7) : .clear, radius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.title)
                        .font(.system(.headline, design: .themed))
                    Text(unit.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if !lessons.isEmpty {
                    Text("\(done)/\(lessons.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(done == lessons.count ? color : Color.secondary)
                }
            }

            ForEach(lessons) { lesson in
                Button {
                    watch(lesson)
                } label: {
                    lessonRow(lesson, color: color)
                }
                .buttonStyle(.plain)
            }
            ForEach(skills) { skill in
                skillRow(skill, color: color)
            }
        }
        .padding(16)
        .trainingCard(theme, tint: theme.isDark ? color : nil)
    }

    private func lessonRow(_ lesson: Lesson, color: Color) -> some View {
        let isDone = store.isDone(lesson.id)
        return HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "play.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(isDone ? TrainingColor.green.color(on: theme) : color)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(lesson.title)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                Text(lesson.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lesson.title), lesson\(isDone ? ", done" : "")")
    }

    private func skillRow(_ skill: Skill, color: Color) -> some View {
        let level = store.level(of: skill)
        let mastery = store.mastery(of: skill)
        let hasDrills = !library.drills(for: skill.id).isEmpty
        return HStack(spacing: 12) {
            ZStack {
                ProgressRing(progress: mastery, color: color, lineWidth: 3.5)
                Image(systemName: skill.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(skill.title)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                Text(TrainingStore.levelName(level))
                    .font(.caption)
                    .foregroundStyle(level >= 2 ? color : Color.secondary)
            }
            Spacer(minLength: 4)
            if hasDrills {
                Button("Practice") { practice(skill) }
                    .font(.system(.caption, design: .themed).weight(.bold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
