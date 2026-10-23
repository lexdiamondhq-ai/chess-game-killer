import ChessKit
import SwiftUI

/// The word "Check" in a small red capsule, floating over the king that is in check.
/// It comes in when the check is given, stays a moment and goes; the square under the
/// king keeps its red ring for as long as the check lasts.
struct CheckCallout: View {
    var mate = false
    var color: Color = Color(hex: 0xFF3B4D)

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 9.5, weight: .black))
                .foregroundStyle(color)
                .frame(width: 15, height: 15)
                .background(Circle().fill(.white))
            Text(mate ? "Checkmate" : "Check")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize()
        }
        .padding(.leading, 5)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(color))
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .accessibilityHidden(true)
    }
}

/// Shows `CheckCallout` over the checked king for a moment after each check.
/// `anchor` turns the king's square into the point the callout is centered on.
struct CheckCalloutLayer: View {
    let game: GameModel
    var color: Color = Color(hex: 0xFF3B4D)
    let anchor: (Square) -> CGPoint

    /// The move after which the callout is up; nil when it has gone.
    @State private var shownAfter: Int?

    private static let seconds = 1.9

    var body: some View {
        ZStack {
            if let king = game.checkedKing, shownAfter == game.moveCount {
                let point = anchor(king)
                NameTagPlacement(x: point.x, y: point.y) {
                    CheckCallout(mate: game.isCheckmate, color: color)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.7), value: shownAfter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: game.moveCount, initial: true) { _, count in
            guard game.checkedKing != nil else {
                shownAfter = nil
                return
            }
            shownAfter = count
            // Checkmate stays: the game is over and the board says why.
            guard !game.isCheckmate else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.seconds))
                if shownAfter == count { shownAfter = nil }
            }
        }
    }
}

/// The red ring under a king in check: a soft glow and a crisp ring that breathes.
struct CheckSquareMark: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [color.opacity(0.85), color.opacity(0.4), .clear],
                center: .center, startRadius: 0, endRadius: size * 0.62
            )
            // The ring breathes by the clock, not by an animation, so a board that is still
            // settling its layout never drags the ring along from somewhere else.
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                    .strokeBorder(color, lineWidth: max(2, size * 0.055))
                    .padding(size * 0.035)
                    .opacity(0.775 + 0.225 * sin(t * .pi / 0.7))
            }
        }
        .allowsHitTesting(false)
    }
}

extension GameModel {
    var isCheckmate: Bool {
        if case .checkmate = state { return true }
        return false
    }

    /// The move after which a person's own king is in check, so the phone can buzz once; nil otherwise.
    var personInCheck: Int? {
        guard let king = checkedKing, let color = piece(at: king)?.color, humanColors.contains(color) else { return nil }
        return moveCount
    }
}
