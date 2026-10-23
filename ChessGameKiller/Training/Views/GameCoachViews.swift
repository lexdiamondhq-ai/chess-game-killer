import ChessKit
import SwiftUI

/// Coach Leo's line in the coach bar during a game: the pattern behind the
/// last move, with ways to try again or watch the lesson that teaches it.
struct GameCoachRow: View {
    let coach: GameCoach
    let store: TrainingStore
    let match: MatchController
    let theme: BoardTheme

    /// True when the row has something to show: a tip, a second try, or saved mistakes after the game.
    static func hasContent(coach: GameCoach, match: MatchController) -> Bool {
        coach.retrying != nil || coach.moment != nil || (match.isOver && coach.savedThisGame > 0)
    }

    var body: some View {
        Group {
            if let retry = coach.retrying {
                line(title: "Your turn again", detail: "Find something better than \(sanOf(retry)).",
                     tint: TrainingColor.yellow.color(on: theme)) { EmptyView() }
            } else if match.isOver, coach.savedThisGame > 0 {
                // At the end of a game the way into practice comes first: it's what the game was for.
                line(title: coach.savedThisGame == 1 ? "1 position to practice" : "\(coach.savedThisGame) positions to practice",
                     detail: "The moments that cost you, saved for a second try.",
                     tint: TrainingColor.pink.color(on: theme)) {
                    smallButton("Practice", symbol: "arrow.uturn.backward.circle.fill") {
                        coach.practiceMistakes(store: store)
                    }
                }
            } else if let moment = coach.moment {
                momentView(moment)
            }
        }
        .animation(.snappy(duration: 0.3), value: coach.moment)
        .animation(.snappy(duration: 0.3), value: coach.retrying)
    }

    private func momentView(_ moment: CoachMoment) -> some View {
        let tint = moment.isPraise ? TrainingColor.green.color(on: theme) : TrainingColor.orange.color(on: theme)
        let lesson = coach.lesson(for: moment, in: store.library)
        return line(title: moment.title, detail: moment.detail, tint: tint) {
            if !moment.isPraise, match.canUndo {
                smallButton("Try again", symbol: "arrow.uturn.backward") {
                    withAnimation(.snappy(duration: 0.22)) { coach.tryAgain(in: match) }
                }
            }
            if let lesson, !moment.isPraise || !store.isDone(lesson.id) {
                smallButton("Watch lesson", symbol: "play.rectangle.fill") {
                    coach.watchLesson(for: moment, store: store)
                }
            }
        }
        .id(moment.id)
        .transition(.push(from: .bottom))
    }

    private func line<Buttons: View>(title: String, detail: String, tint: Color,
                                     @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CoachAvatar(theme: theme, size: 38, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    buttons()
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 0)
            if coach.moment != nil {
                Button {
                    withAnimation(.snappy) { coach.dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.secondary.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.secondary.opacity(theme.isDark ? 0.25 : 0.15))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        let accent = theme.trainingAccent
        return Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(accent)
                .background(accent.opacity(theme.isDark ? 0.16 : 0.12), in: Capsule())
                .overlay {
                    if theme.isDark {
                        Capsule().strokeBorder(accent.opacity(0.4), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func sanOf(_ moment: CoachMoment) -> String {
        Notation.san(of: moment.played, fen: moment.fen) ?? "your last move"
    }
}

/// "Think" in the coach orb's row of round buttons: the Traffic Light, for the
/// position on the board. Drawn like the orb's other buttons, with the three lights as its icon.
struct ThinkActionButton: View {
    let match: MatchController
    let theme: BoardTheme
    @State private var showing = false
    @Environment(\.isEnabled) private var isEnabled

    private var canThink: Bool { !match.isOver && match.game.isHumanTurn }

    var body: some View {
        Button {
            showing = true
        } label: {
            VStack(spacing: 5) {
                TrafficLightDots(theme: theme, size: 7)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(theme.isDark ? 0.07 : 0.05), in: Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.11), lineWidth: 1))
                Text("Think")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.primary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .opacity(isEnabled && canThink ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!canThink)
        .accessibilityLabel("Think with me")
        .accessibilityHint("Walks through the three questions to ask before you move.")
        .sheet(isPresented: $showing) {
            ThinkWithMeSheet(fen: match.game.fen, lastMove: match.game.lastMove, theme: theme)
        }
    }
}

/// Little Leo on the closed coach orb: he has a tip about the last move. Open the orb to read it.
struct CoachOrbBadge: View {
    let moment: CoachMoment
    let theme: BoardTheme

    var body: some View {
        let tint = moment.isPraise ? TrainingColor.green.color(on: theme) : TrainingColor.orange.color(on: theme)
        CoachAvatar(theme: theme, size: 26, tint: tint)
            .accessibilityElement()
            .accessibilityLabel(moment.isPraise ? "Coach Leo liked that move" : "Coach Leo has a tip")
    }
}

/// The Traffic Light, worked through for the position on the board.
struct ThinkWithMeSheet: View {
    let fen: String
    let lastMove: LastMove?
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var store: TrainingStore?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let scan = TrafficLightScan(fen: fen, lastMove: lastMove)
        let habit = store?.library?.course.habit ?? []
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        CoachAvatar(theme: theme, size: 48)
                        Text("Before you move, ask three questions. Here's what I see.")
                            .font(.system(.subheadline, design: .themed).weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let scan {
                        light(.red, title: habit.first?.question ?? "What are they threatening?", lines: scan.red)
                        light(.yellow, title: habit.dropFirst().first?.question ?? "Any checks, captures or attacks?", lines: scan.yellow)
                        light(.green, title: habit.dropFirst(2).first?.question ?? "Is my move safe?", lines: scan.green)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Think with me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground {
            TrainingBackdrop(theme: theme)
        }
        .tint(theme.trainingAccent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
    }

    private func light(_ color: TrainingColor, title: String, lines: [String]) -> some View {
        let tint = color.color(on: theme)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(tint)
                    .frame(width: 14, height: 14)
                    .shadow(color: theme.glows ? tint : .clear, radius: 6)
                Text(title)
                    .font(.system(.headline, design: .themed))
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 24)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme, tint: tint, cornerRadius: 18)
    }
}
