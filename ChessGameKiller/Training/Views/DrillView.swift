import ChessKit
import SwiftUI

/// One practice item: the board, what the coach asks, and the ways to answer.
struct DrillView: View {
    let runner: DrillRunner
    let theme: BoardTheme
    let boardSide: CGFloat
    /// Offers Talk it through on find-the-move puzzles. Rush and Cycles never do: they give no help.
    var talks = false

    /// The talk open over the puzzle.
    @State private var talk: TalkSession?
    /// The move Play picked in the talk, made once the talk has closed.
    @State private var talkMove: DrillTalkMove?

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
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
                // Under the board, never over the back rank; the space is kept so nothing jumps.
                turnBadge
            }

            messageCard
                .padding(.horizontal, 16)

            answers
                .padding(.horizontal, 16)
        }
        .animation(.snappy(duration: 0.25), value: runner.phase)
        .fullScreenCover(item: $talk, onDismiss: playTalkMove) { (session: TalkSession) in
            TalkPanel(session: session, theme: theme, play: { (uci: String) in
                talkMove = DrillTalkMove(fen: session.fen, uci: uci)
                talk = nil
            }, close: {
                talk = nil
            })
        }
    }

    // MARK: Pieces of the screen

    /// "White to move" in the learner's color, under the board.
    private var turnBadge: some View {
        TurnBadge(theme: theme, side: runner.learner,
                  showing: runner.phase == .solving && (runner.kind == .move || runner.kind == .playout))
    }

    private var messageCard: some View {
        let tint = runner.tone == .coach ? nil : theme.trainingTone(runner.tone)
        return HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
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
            .accessibilityElement(children: .combine)
            if showsTalk {
                talkButton
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme, tint: tint)
        .animation(.easeInOut(duration: 0.2), value: runner.message)
        .animation(.snappy(duration: 0.25), value: showsTalk)
    }

    private var roleChip: (text: String, symbol: String, color: Color)? {
        // One accent on the executive looks; Neon keeps a color for each.
        func color(_ neon: TrainingColor) -> Color { theme.glows ? neon.color(on: theme) : theme.trainingAccent }
        if case .mistake = runner.item.content {
            return ("From your game", "arrow.uturn.backward.circle.fill", color(.pink))
        }
        switch runner.item.role {
        case .warmUp: return ("Warm-up", "sun.max.fill", color(.yellow))
        case .focus: return nil
        case .review: return ("Review", "arrow.triangle.2.circlepath", color(.violet))
        case .mixed: return ("Mixed: no clues", "shuffle", color(.teal))
        case .finisher: return ("Finisher", "flag.checkered", color(.green))
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
                        Text("Skip")
                    }
                    .accessibilityHint("Gives this one up and moves on")
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
                        Text("Skip")
                    }
                    .accessibilityHint("Gives this one up and moves on")
                    .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                    .frame(maxWidth: 130)
                }
            }
        }
    }

    @ViewBuilder
    private var helpButtons: some View {
        if runner.strict {
            // Rush and Cycles give no hints. Passing counts as a miss, and says so.
            Button {
                withAnimation(.snappy) { runner.reveal() }
            } label: {
                Label("Pass (counts as a miss)", systemImage: "forward.fill")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
        } else {
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
    }

    // MARK: Talk it through

    /// Leo's microphone sits in his card for the whole of a find-the-move puzzle, so the words
    /// never jump; it only works on the learner's turn.
    private var showsTalk: Bool {
        talks && runner.kind == .move && !runner.strict && !runner.isDone
    }

    /// Answer Leo out loud: his microphone, at the end of what he just asked.
    private var talkButton: some View {
        let ready = runner.canTalkItThrough && talk == nil
        return Button(action: openTalk) {
            TalkMic(theme: theme)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Lined up with Leo's 40-point face, so the card keeps its height; still a 44-point target.
        .padding(.vertical, -2)
        .disabled(!ready)
        .opacity(ready ? 1 : 0.4)
        .animation(.easeInOut(duration: 0.2), value: ready)
        .accessibilityLabel("Talk it through")
        .accessibilityHint("Tell Leo your plan. He checks every part. Counts as a hint.")
    }

    private func openTalk() {
        guard talk == nil, let session = runner.talkSession() else { return }
        talkMove = nil
        talk = session
    }

    /// Makes the move Play picked, on the position the talk was about.
    private func playTalkMove() {
        guard let pending = talkMove else { return }
        talkMove = nil
        guard runner.game.fen == pending.fen else { return }
        withAnimation(.snappy) { _ = runner.playLearnerMove(pending.uci) }
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

/// A move picked with Play in a talk over a puzzle, and the position it was for.
private struct DrillTalkMove: Equatable {
    let fen: String
    let uci: String
}
