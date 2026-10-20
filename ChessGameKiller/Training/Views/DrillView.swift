import ChessKit
import SwiftUI

/// One practice item: the board, what the coach asks, and the ways to answer.
struct DrillView: View {
    let runner: DrillRunner
    let theme: BoardTheme
    let boardSide: CGFloat

    var body: some View {
        VStack(spacing: 14) {
            TrainingBoardView(
                game: runner.game,
                theme: theme,
                flipped: runner.learner == .black,
                arrows: runner.arrows,
                marks: runner.marks,
                labels: runner.labels,
                onTap: runner.acceptsTaps ? { (square: Square) in runner.tap(square) } : nil
            )
            .frame(width: boardSide, height: boardSide)
            .overlay(alignment: .bottom) { turnBadge }

            messageCard
                .padding(.horizontal, 16)

            answers
                .padding(.horizontal, 16)
        }
        .animation(.snappy(duration: 0.25), value: runner.phase)
    }

    // MARK: Pieces of the screen

    /// "Your move" in the learner's color, under the board.
    @ViewBuilder
    private var turnBadge: some View {
        if runner.phase == .solving, runner.kind == .move || runner.kind == .playout {
            HStack(spacing: 6) {
                Circle()
                    .fill(theme.sideColor(runner.learner))
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: theme.isDark ? 0 : 1))
                    .frame(width: 10, height: 10)
                Text("\(theme.name(of: runner.learner)) to move")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .offset(y: 13)
            .transition(.opacity)
        }
    }

    private var messageCard: some View {
        let tint = runner.tone == .coach ? nil : theme.trainingTone(runner.tone)
        return HStack(alignment: .top, spacing: 12) {
            CoachAvatar(theme: theme, size: 40, tint: tint)
            VStack(alignment: .leading, spacing: 6) {
                if let chip = roleChip {
                    TrainingChip(text: chip.text, symbol: chip.symbol, color: chip.color)
                }
                Text(runner.message)
                    .font(.system(.body, design: .themed).weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(runner.message)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme, tint: tint)
        .animation(.easeInOut(duration: 0.2), value: runner.message)
        .accessibilityElement(children: .combine)
    }

    private var roleChip: (text: String, symbol: String, color: Color)? {
        if case .mistake = runner.item.content {
            return ("From your game", "arrow.uturn.backward.circle.fill", TrainingColor.pink.color(on: theme))
        }
        switch runner.item.role {
        case .warmUp: return ("Warm-up", "sun.max.fill", TrainingColor.yellow.color(on: theme))
        case .focus: return nil
        case .review: return ("Review", "arrow.triangle.2.circlepath", TrainingColor.violet.color(on: theme))
        case .mixed: return ("Mixed: no clues", "shuffle", TrainingColor.teal.color(on: theme))
        case .finisher: return ("Finisher", "flag.checkered", TrainingColor.green.color(on: theme))
        }
    }

    // MARK: Answering

    @ViewBuilder
    private var answers: some View {
        switch runner.kind {
        case .safe:
            if runner.phase == .solving {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.snappy) { runner.answer(true) }
                    } label: {
                        Label(runner.answerLabels.yes, systemImage: "checkmark.shield.fill")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme, tint: TrainingColor.green.color(on: theme)))
                    Button {
                        withAnimation(.snappy) { runner.answer(false) }
                    } label: {
                        Label(runner.answerLabels.no, systemImage: "exclamationmark.triangle.fill")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme, tint: TrainingColor.red.color(on: theme)))
                }
            }
        case .choice:
            VStack(spacing: 8) {
                ForEach(Array(runner.options.enumerated()), id: \.offset) { index, option in
                    optionButton(option, index: index)
                }
            }
        case .move, .tap:
            if runner.phase == .solving {
                helpButtons
            }
        case .playout:
            if runner.phase == .stuck {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.snappy) { runner.restart() }
                    } label: {
                        Label("Try again", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme))
                    Button {
                        runner.reveal()
                    } label: {
                        Text("Move on")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                }
            } else if runner.phase == .solving {
                HStack(spacing: 10) {
                    Text("Moves: \(runner.movesMade) of \(runner.moveLimit)")
                        .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .contentTransition(.numericText())
                    Button {
                        runner.hint()
                    } label: {
                        Label("Hint", systemImage: "lightbulb.fill")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false, tint: TrainingColor.yellow.color(on: theme)))
                    .frame(maxWidth: 130)
                    Button {
                        withAnimation(.snappy) { runner.reveal() }
                    } label: {
                        Text("Move on")
                    }
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                    .frame(maxWidth: 130)
                }
            }
        }
    }

    private var helpButtons: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { runner.hint() }
            } label: {
                Label("Hint", systemImage: "lightbulb.fill")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false, tint: TrainingColor.yellow.color(on: theme)))
            .disabled(runner.usedHint)
            Button {
                withAnimation(.snappy) { runner.reveal() }
            } label: {
                Label("Show me", systemImage: "eye.fill")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
        }
    }

    private func optionButton(_ option: ChoiceOption, index: Int) -> some View {
        let tried = runner.tried.contains(index)
        let revealed = runner.isDone && option.correct
        let color: Color = tried || revealed
            ? (option.correct ? TrainingColor.green.color(on: theme) : TrainingColor.red.color(on: theme))
            : theme.trainingAccent
        return Button {
            withAnimation(.snappy) { runner.choose(index) }
        } label: {
            HStack(spacing: 10) {
                Text(option.text)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .strikethrough(tried && !option.correct, color: color)
                Spacer(minLength: 4)
                if tried || revealed {
                    Image(systemName: option.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                }
            }
            .foregroundStyle(tried || revealed ? color : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(tried || revealed ? 0.16 : (theme.isDark ? 0.12 : 0.08)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(color.opacity(tried || revealed ? 0.7 : 0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(tried || runner.isDone || runner.phase != .solving)
    }
}
