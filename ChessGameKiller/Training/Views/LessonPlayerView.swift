import ChessKit
import SwiftUI

/// A lesson on its own (from the Training screen or the game): the lesson,
/// then a finish card with the XP earned and a way straight into practice.
struct LessonScreen: View {
    let lesson: Lesson
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var reward: TrainingReward?
    @State private var practice: SessionPlan?

    var body: some View {
        if let practice {
            SessionView(plan: practice, theme: theme)
        } else {
            LessonPlayerView(lesson: lesson, theme: theme) {
                reward = store.completeLesson(lesson.id)
            }
            .overlay {
                if let reward {
                    LessonDoneCard(lesson: lesson, theme: theme, reward: reward, line: store.library?.course.lines.lessonDone.randomElement()) {
                        if let skill = store.library?.skill(lesson.skill) {
                            practice = store.practicePlan(for: skill)
                        }
                        if practice == nil { dismiss() }
                    } done: {
                        dismiss()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.snappy, value: reward)
        }
    }
}

/// Plays a lesson like a video, with the learner's turns along the way.
struct LessonPlayerView: View {
    let lesson: Lesson
    let theme: BoardTheme
    var onFinish: () -> Void = {}
    /// Inside a session: skips the lesson and goes on to the puzzles.
    var onSkip: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: LessonPlayer?
    /// Shared with CoachVoice.isMuted.
    @AppStorage("coachVoiceMuted") private var muted = false
    @State private var finished = false

    var body: some View {
        ZStack {
            TrainingBackdrop(theme: theme)
            if let player {
                content(player)
            } else {
                unavailable
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .onAppear {
            guard player == nil else { return }
            player = LessonPlayer(lesson: lesson)
            player?.start()
        }
        .onDisappear { player?.close() }
        .onChange(of: player?.phase) { _, phase in
            guard phase == .finished, !finished else { return }
            finished = true
            onFinish()
        }
        .onChange(of: scenePhase) { _, phase in
            // Locking the phone or switching apps pauses the lesson cleanly, with
            // the play button showing, instead of leaving it mid-line.
            if phase != .active, let player, player.phase == .playing {
                player.togglePause()
            }
        }
    }

    private func content(_ player: LessonPlayer) -> some View {
        GeometryReader { geo in
            let boardSide = max(200, min(geo.size.width - 32, geo.size.height * 0.56))
            VStack(spacing: 12) {
                header(player)
                progress(player)
                TrainingBoardView(
                    game: player.game,
                    theme: theme,
                    flipped: player.isFlipped,
                    arrows: player.arrows,
                    marks: player.marks,
                    labels: player.labels,
                    onTap: player.phase == .task ? { (square: Square) in player.tap(square) } : nil
                )
                .frame(width: boardSide, height: boardSide)
                .padding(.top, 4)
                ScrollView {
                    caption(player)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .scrollBounceBehavior(.basedOnSize)
                controls(player)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .frame(width: geo.size.width)
        }
    }

    // MARK: Top

    private func header(_ player: LessonPlayer) -> some View {
        HStack(spacing: 12) {
            Button {
                player.close()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close lesson")

            VStack(alignment: .leading, spacing: 1) {
                Text(lesson.title)
                    .font(.system(.headline, design: .themed))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(lesson.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let onSkip, player.phase != .finished {
                Button {
                    player.close()
                    onSkip()
                } label: {
                    Text("Skip")
                        .font(.system(.subheadline, design: .themed).weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip the lesson")
                .accessibilityHint("Goes straight to the puzzles")
            }
            Button {
                muted.toggle()
                if muted { CoachVoice.shared.stop() }
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(muted ? "Turn the coach's voice on" : "Mute the coach's voice")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func progress(_ player: LessonPlayer) -> some View {
        let accent = theme.trainingAccent
        return HStack(spacing: 3) {
            ForEach(0..<player.steps.count, id: \.self) { index in
                Capsule()
                    .fill(index < player.stepIndex || player.phase == .finished
                          ? accent
                          : (index == player.stepIndex ? accent.opacity(0.55) : Color.secondary.opacity(0.22)))
                    .frame(height: 4)
                    .shadow(color: theme.glows && index <= player.stepIndex ? accent.opacity(0.7) : .clear, radius: 3)
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.3), value: player.stepIndex)
        .accessibilityElement()
        .accessibilityLabel("Step \(player.stepIndex + 1) of \(player.steps.count)")
    }

    // MARK: What the coach says

    private func caption(_ player: LessonPlayer) -> some View {
        let tint = player.tone == .coach ? nil : theme.trainingTone(player.tone)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CoachAvatar(theme: theme, size: 42, tint: tint)
                VStack(alignment: .leading, spacing: 6) {
                    if player.phase == .task, player.task?.type != .choice {
                        TrainingChip(text: "Your turn", symbol: "hand.tap.fill", color: theme.trainingAccent)
                    }
                    Text(player.caption)
                        .font(.system(.body, design: .themed).weight(.medium))
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(player.caption)
                        .transition(.opacity)
                }
            }
            if let task = player.task, task.type == .choice, let options = task.options {
                VStack(spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        choiceButton(option, index: index, player: player)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme, tint: tint)
        .animation(.easeInOut(duration: 0.25), value: player.caption)
        .accessibilityElement(children: .contain)
    }

    private func choiceButton(_ option: ChoiceOption, index: Int, player: LessonPlayer) -> some View {
        let tried = player.tried.contains(index)
        let color: Color = tried
            ? (option.correct ? TrainingColor.green.color(on: theme) : TrainingColor.red.color(on: theme))
            : theme.trainingAccent
        return Button {
            withAnimation(.snappy) { player.choose(index) }
        } label: {
            HStack(spacing: 10) {
                Text(option.text)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .strikethrough(tried && !option.correct, color: color)
                Spacer(minLength: 4)
                if tried {
                    Image(systemName: option.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                }
            }
            .foregroundStyle(tried ? color : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(tried ? 0.16 : (theme.isDark ? 0.12 : 0.08)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(color.opacity(tried ? 0.7 : 0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(tried || player.solved)
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ player: LessonPlayer) -> some View {
        if player.phase == .task, let task = player.task {
            HStack(spacing: 10) {
                if task.hint != nil {
                    Button {
                        player.showHint()
                    } label: {
                        Label("Hint", systemImage: "lightbulb.fill")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false, tint: TrainingColor.yellow.color(on: theme)))
                }
                Button {
                    withAnimation(.snappy) { player.showAnswer() }
                } label: {
                    Label("Show me", systemImage: "eye.fill")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
            }
            .disabled(player.solved)
        } else {
            HStack(spacing: 28) {
                roundButton("backward.fill", label: "Previous step", size: 46) { player.back() }
                roundButton(player.phase == .playing ? "pause.fill" : (player.phase == .finished ? "arrow.counterclockwise" : "play.fill"),
                            label: player.phase == .playing ? "Pause" : (player.phase == .finished ? "Play again" : "Play"),
                            size: 62, prominent: true) {
                    if player.phase == .finished {
                        finished = false
                        player.restart()
                    } else {
                        player.togglePause()
                    }
                }
                roundButton("forward.fill", label: "Next step", size: 46) { player.skip() }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func roundButton(_ symbol: String, label: String, size: CGFloat, prominent: Bool = false,
                             action: @escaping () -> Void) -> some View {
        let accent = theme.trainingAccent
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(prominent ? (theme.isDark ? Color.black : Color.white) : accent)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(prominent ? AnyShapeStyle(accent) : AnyShapeStyle(accent.opacity(theme.isDark ? 0.16 : 0.12)))
                        .shadow(color: prominent && theme.glows ? accent.opacity(0.6) : .clear, radius: 12)
                }
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(TrainingColor.orange.color(on: theme))
            Text("This lesson couldn't load.")
                .font(.headline)
            Button("Close") { dismiss() }
                .buttonStyle(TrainingButtonStyle(theme: theme))
                .frame(maxWidth: 220)
        }
        .padding()
    }
}

/// The finish card after a lesson on its own.
struct LessonDoneCard: View {
    let lesson: Lesson
    let theme: BoardTheme
    let reward: TrainingReward
    let line: String?
    let practice: () -> Void
    let done: () -> Void

    @State private var appeared = false

    var body: some View {
        let green = TrainingColor.green.color(on: theme)
        ZStack {
            Color.black.opacity(theme.isDark ? 0.55 : 0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(green.opacity(0.18))
                        .frame(width: 96, height: 96)
                        .scaleEffect(appeared ? 1 : 0.6)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(green)
                        .shadow(color: theme.glows ? green : .clear, radius: 14)
                        .symbolEffect(.bounce, value: appeared)
                }
                VStack(spacing: 6) {
                    Text("Lesson complete")
                        .font(.system(.title2, design: .themed).weight(.bold))
                    Text(lesson.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    TrainingChip(text: "+\(reward.xp) XP", symbol: "sparkles", color: theme.trainingAccent)
                    if reward.streak > 0 {
                        TrainingChip(text: "\(reward.streak)-day streak", symbol: "flame.fill",
                                     color: TrainingColor.orange.color(on: theme))
                    }
                }
                if let promotion = reward.promotion {
                    Text("Promoted to \(promotion.title)!")
                        .font(.system(.headline, design: .themed))
                        .foregroundStyle(TrainingColor.yellow.color(on: theme))
                }
                if let line {
                    HStack(alignment: .top, spacing: 10) {
                        CoachAvatar(theme: theme, size: 32)
                        Text(line)
                            .font(.system(.subheadline, design: .themed))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(spacing: 10) {
                    Button("Practice it now", action: practice)
                        .buttonStyle(TrainingButtonStyle(theme: theme))
                    Button("Done", action: done)
                        .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 380)
            .trainingCard(theme, tint: green, cornerRadius: 28)
            .padding(24)
        }
        .onAppear { appeared = true }
        .sensoryFeedback(.success, trigger: appeared)
    }
}
