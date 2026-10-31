import ChessKit
import SwiftUI

/// Perfect Endgames, full screen: one study against perfect defence. The goal sits above the
/// board, Coach Leo's plan and feedback below it, and when it's over the player can go again
/// or move on to the next study. Completed studies are recorded in `EndgameProgress.shared`.
struct EndgameView: View {
    let theme: BoardTheme
    private let firstStudy: EndgameStudy
    @State private var runner: EndgameRunner?
    @Environment(\.dismiss) private var dismiss

    init(study: EndgameStudy, theme: BoardTheme) {
        firstStudy = study
        self.theme = theme
    }

    /// For tests and previews: a runner set up by hand.
    init(runner: EndgameRunner, theme: BoardTheme) {
        firstStudy = runner.study
        self.theme = theme
        _runner = State(initialValue: runner)
    }

    private var study: EndgameStudy { runner?.study ?? firstStudy }

    var body: some View {
        GeometryReader { geo in
            let side = boardSide(in: geo.size)
            VStack(spacing: 12) {
                RoomHeader(title: study.title, subtitle: subtitle) { dismiss() }
                if let runner {
                    goalRow(runner)
                    TrainingBoardView(game: runner.board, theme: theme, flipped: runner.player == .black,
                                      marks: runner.marks,
                                      onTap: runner.phase == .playing ? { (square: Square) in runner.tap(square) } : nil)
                        .frame(width: side, height: side)
                        .boardHeadroom(theme: theme, side: side)
                        .id(runner.study.id)
                        .transition(.opacity)
                    RoomMessage(text: runner.message, tone: runner.tone, theme: theme)
                        .padding(.horizontal, 16)
                    controls(runner)
                        .padding(.horizontal, 16)
                    Spacer(minLength: 0)
                    judgeLine(runner)
                }
            }
            .frame(width: geo.size.width)
        }
        .background { TrainingBackdrop(theme: theme) }
        .animation(.snappy, value: runner?.phase)
        .onAppear {
            guard runner == nil else { return }
            let made = EndgameRunner.live(study: firstStudy)
            runner = made
            made.start()
        }
        .onDisappear { runner?.cancel() }
    }

    /// The board gets what the header, goal line, Leo's card (up to five lines on a small
    /// phone), buttons and judge line leave.
    private func boardSide(in size: CGSize) -> CGFloat {
        max(200, min(size.width - 24, size.height - 340))
    }

    private var subtitle: String {
        "\(study.group.rawValue) · \(study.levelName)"
    }

    // MARK: Goal and count

    private func goalRow(_ runner: EndgameRunner) -> some View {
        HStack(spacing: 8) {
            Label(runner.study.goalText, systemImage: runner.study.goal == .win ? "flag.checkered" : "shield.lefthalf.filled")
                .font(.app(.headline))
                .foregroundStyle(theme.trainingAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if (runner.phase == .won || runner.phase == .held) && runner.isClean {
                TrainingChip(text: "Flawless", symbol: "sparkles", color: theme.trainingAccent)
                    .transition(.opacity)
            } else {
                Text(countText(runner))
                    .font(.app(.subheadline, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 20)
    }

    /// How many moves it took, at the end. Before that: "Held 3 of 10" for a draw, "Mate in 12"
    /// while the tablebase counts down a mate, or else the move number.
    private func countText(_ runner: EndgameRunner) -> String {
        if runner.phase.isFinished {
            return EndgameRunner.moves(runner.movesMade)
        }
        if runner.study.goal == .draw {
            return "Held \(runner.movesMade) of \(runner.study.movesToHold)"
        }
        if let mate = runner.mateLeft {
            return "Mate in \(mate)"
        }
        return "Move \(runner.movesMade + 1)"
    }

    // MARK: Buttons

    @ViewBuilder
    private func controls(_ runner: EndgameRunner) -> some View {
        HStack(spacing: 10) {
            switch runner.phase {
            case .loading, .playing, .thinking:
                Button {
                    runner.hint()
                } label: {
                    Label("Hint", systemImage: "lightbulb.fill")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false, tint: TrainingColor.yellow.color(on: theme)))
                .disabled(runner.phase != .playing)
                // Dimmed only before the study starts, so the buttons don't flicker with every move.
                .opacity(runner.phase == .loading ? 0.5 : 1)
                Button {
                    runner.restart()
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                .disabled(runner.phase == .loading)
                .opacity(runner.phase == .loading ? 0.5 : 1)
            case .won, .held:
                Button {
                    runner.restart()
                } label: {
                    Label("Again", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
                nextButton(after: runner.study, prominent: true)
            case .failed, .unavailable:
                Button {
                    runner.restart()
                } label: {
                    Label("Try again", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
                nextButton(after: runner.study, prominent: false)
            }
        }
    }

    @ViewBuilder
    private func nextButton(after current: EndgameStudy, prominent: Bool) -> some View {
        if let next = EndgameProgress.shared.next(after: current), next.id != current.id {
            Button {
                open(next)
            } label: {
                Label("Next study", systemImage: "arrow.right")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: prominent))
        } else if prominent {
            Button {
                dismiss()
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
        }
    }

    private func open(_ next: EndgameStudy) {
        runner?.cancel()
        let made = EndgameRunner.live(study: next)
        withAnimation(.easeInOut(duration: 0.25)) { runner = made }
        made.start()
    }

    // MARK: Judge

    /// Who judges the moves, quietly. While the judge thinks, its mark turns into a small
    /// spinner, but only once the wait is long enough to notice.
    private func judgeLine(_ runner: EndgameRunner) -> some View {
        let waiting = runner.phase == .thinking || runner.phase == .loading
        let kind = runner.judgeKind
        return HStack(spacing: 6) {
            ZStack {
                Image(systemName: kind == .tablebase ? "checkmark.seal" : "cpu")
                    .opacity(waiting || kind == nil ? 0 : 1)
                ProgressView()
                    .scaleEffect(0.6)
                    .opacity(waiting ? 1 : 0)
            }
            .frame(width: 16, height: 16)
            .animation(waiting ? .easeIn(duration: 0.2).delay(0.6) : .easeOut(duration: 0.15), value: waiting)
            .accessibilityHidden(true)
            Text(kind?.label ?? "Looking at the position")
                .contentTransition(.opacity)
        }
        .font(.app(.caption))
        .foregroundStyle(.secondary)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.3), value: kind)
        .accessibilityElement(children: .combine)
    }
}
