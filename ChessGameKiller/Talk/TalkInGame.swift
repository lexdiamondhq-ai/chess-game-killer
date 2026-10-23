import ChessKit
import SwiftUI

// Talk it through during a game: a row in the open coach, and a hold on the closed orb. The game
// waits under it like under any screen over the board (the clock holds, the rival's engine work
// stops and picks up after), a send counts as help like Undo, Leo never names the best move, and
// Play makes the checked move as the player's own, graded like one made on the board.

extension MatchController {
    /// The player's turn in a game still on, with no pawn waiting to promote.
    var canTalkItThrough: Bool {
        !isOver && game.isHumanTurn && game.pendingPromotion == nil
    }

    /// A talk about the position on the board, for the side to move. Nil when it isn't their turn.
    func talkSession() -> TalkSession? {
        guard canTalkItThrough else { return nil }
        let last = game.lastPlayed?.uci ?? game.lastMove.map { $0.from.notation + $0.to.notation }
        let session = TalkSession(fen: game.fen, player: game.sideToMove, context: .game, reveal: false,
                                  lastMove: last)
        session.onSend = { [weak self] in self?.markAssisted() }
        return session
    }

    /// Talking it through would count as help: the game is under way and has had none yet.
    var talkCountsAsHelp: Bool { canResign && !wasAssisted }
}

/// The way into Talk it through from the open coach: Leo's microphone, and what it does.
struct TalkEntryRow: View {
    let theme: BoardTheme
    /// Say that a talk counts as help, like Undo.
    let countsAsHelp: Bool
    let open: () -> Void

    private var detail: String {
        countsAsHelp
            ? "Tell Leo your plan. He checks every part. Counts as help, like Undo."
            : "Tell Leo your plan. He checks every part."
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        Button(action: open) {
            HStack(spacing: 12) {
                TalkMic(theme: theme)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Talk it through")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background {
                shape
                    .fill(Color.primary.opacity(theme.isDark ? 0.05 : 0.04))
                    .overlay { shape.strokeBorder(Color.primary.opacity(theme.isDark ? 0.09 : 0.08), lineWidth: 1) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Talk it through")
        .accessibilityHint(detail)
    }
}

/// Leo's microphone: the talk button of the Talk screen, in small. It marks every way into
/// Talk it through, in the coach and on a training puzzle.
struct TalkMic: View {
    let theme: BoardTheme

    @ScaledMetric(relativeTo: .subheadline) private var scaled: CGFloat = 34

    var body: some View {
        let accent: Color = theme.challengeAccent
        let side: CGFloat = min(max(scaled, 30), 42)
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [accent, accent.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            Circle()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.75)
            Image(systemName: "mic.fill")
                .font(.system(size: side * 0.42, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
        }
        .frame(width: side, height: side)
        .shadow(color: accent.opacity(theme.glows ? 0.55 : 0.25), radius: theme.glows ? 8 : 3, y: theme.glows ? 0 : 1)
        .accessibilityHidden(true)
    }
}
