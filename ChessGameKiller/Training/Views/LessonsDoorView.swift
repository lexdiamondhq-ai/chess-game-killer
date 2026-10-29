import ChessKit
import SwiftUI

/// Coach Leo's course, behind the Lessons door: the Traffic Light habit, then the units
/// of the journey. Only the unit the learner is on is open; the rest fold away.
struct LessonsDoorView: View {
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var store
    @State private var lesson: Lesson?
    @State private var session: SessionPlan?
    @State private var open: Set<String> = []
    @State private var offer: PremiumFeature?

    var body: some View {
        TrainScreen(theme: theme, title: "Lessons",
                    intro: "\(Coach.current.title)'s course, from your first moves to winning endgames. Watch a lesson, then practice it at your level.") {
            if let library = store.library {
                HabitCard(library: library, theme: theme) { lesson = $0 }
                TrainSectionTitle(text: "The course")
                ForEach(library.course.units) { unit in
                    UnitCard(unit: unit, library: library, theme: theme, isOpen: open.contains(unit.id)) {
                        withAnimation(.snappy) {
                            if open.contains(unit.id) { open.remove(unit.id) } else { open.insert(unit.id) }
                        }
                    } watch: { lesson in
                        // The first five lessons are free; Premium opens the rest.
                        if Premium.shared.opens(.lessons) || library.isFreeLesson(lesson.id) {
                            self.lesson = lesson
                        } else {
                            offer = .lessons
                        }
                    } practice: { skill in
                        session = store.practicePlan(for: skill)
                    }
                }
                Text("Every drill was checked by Stockfish.")
                    .font(.app(.footnote))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
        }
        .onAppear {
            if open.isEmpty, let current = currentUnit {
                open = [current.id]
            }
        }
        .fullScreenCover(item: $lesson) { lesson in
            LessonScreen(lesson: lesson, theme: theme)
                .environment(store)
        }
        .premiumOffer($offer)
        .fullScreenCover(item: $session) { plan in
            SessionView(plan: plan, theme: theme, startsAtOnce: true)
                .environment(store)
        }
    }

    /// The first unit with a lesson still to watch or a skill not yet learned.
    private var currentUnit: CourseUnit? {
        guard let library = store.library else { return nil }
        return library.course.units.first { unit in
            unit.lessons.contains { !store.isDone($0) }
                || unit.skills.compactMap { library.skill($0) }.contains { store.level(of: $0) < 1 }
        } ?? library.course.units.first
    }
}

/// The Traffic Light: three questions before every move.
struct HabitCard: View {
    let library: TrainingLibrary
    let theme: BoardTheme
    let watch: (Lesson) -> Void
    @State private var expanded = false

    var body: some View {
        let colors: [TrainingColor] = [.red, .yellow, .green]
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    TrafficLightDots(theme: theme, size: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Traffic Light")
                            .font(.app(.headline))
                        Text("Three questions before every move")
                            .font(.app(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Hides the three questions" : "Shows the three questions")

            if expanded {
                ForEach(Array(library.course.habit.enumerated()), id: \.offset) { index, light in
                    let color = colors[index % colors.count].color(on: theme)
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(color)
                            .frame(width: 12, height: 12)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(light.question)
                                .font(.app(.subheadline, weight: .semibold))
                            Text(light.detail)
                                .font(.app(.footnote))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.opacity)
                }
                if let first = library.lessons.first {
                    Button {
                        watch(first)
                    } label: {
                        Label("Watch: \(first.title)", systemImage: "play.rectangle.fill")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                }
            }
        }
        .padding(16)
        .trainingCard(theme)
    }
}

/// One unit of the journey: its title and progress, and when open, its lessons to
/// watch and skills to practice.
struct UnitCard: View {
    let unit: CourseUnit
    let library: TrainingLibrary
    let theme: BoardTheme
    let isOpen: Bool
    let toggle: () -> Void
    let watch: (Lesson) -> Void
    let practice: (Skill) -> Void
    @Environment(TrainingStore.self) private var store

    var body: some View {
        let color = theme.glows ? unit.color.color(on: theme) : theme.trainingAccent
        let lessons = unit.lessons.compactMap { library.lesson($0) }
        let skills = unit.skills.compactMap { library.skill($0) }
        let done = lessons.filter { store.isDone($0.id) }.count
        let complete = !lessons.isEmpty && done == lessons.count
        VStack(alignment: .leading, spacing: 12) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    TrainIcon(symbol: unit.symbol, theme: theme, size: 40, tint: color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unit.title)
                            .font(.app(.headline))
                        Text(unit.subtitle)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    if complete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(color)
                    } else if !lessons.isEmpty {
                        Text("\(done)/\(lessons.count)")
                            .font(.app(.caption, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(isOpen ? "Folds the unit" : "Shows its lessons")

            if isOpen {
                Divider().opacity(0.5)
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
        }
        .padding(16)
        .trainingCard(theme)
    }

    private func lessonRow(_ lesson: Lesson, color: Color) -> some View {
        let isDone = store.isDone(lesson.id)
        let locked: Bool = !Premium.shared.opens(.lessons) && !library.isFreeLesson(lesson.id)
        let symbol: String = isDone ? "checkmark.circle.fill" : locked ? "crown.fill" : "play.circle.fill"
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(isDone ? color.opacity(0.7) : color)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(lesson.title)
                    .font(.app(.subheadline, weight: .semibold))
                Text(lesson.subtitle)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lesson.title), lesson\(isDone ? ", watched" : "")\(locked ? ", Premium" : "")")
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
                    .font(.app(.subheadline, weight: .semibold))
                Text(TrainingStore.levelName(level))
                    .font(.app(.caption))
                    .foregroundStyle(level >= 2 ? color : Color.secondary)
            }
            Spacer(minLength: 4)
            if hasDrills {
                Button("Practice") { practice(skill) }
                    .font(.app(.caption, weight: .bold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
