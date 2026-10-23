import ChessKit
import SwiftUI
import UIKit

/// The word "Check" in a small red capsule, floating over the king that is in check.
/// It comes in when the check is given, stays a moment and goes; the square under the
/// king keeps its red ring for as long as the check lasts.
struct CheckCallout: View {
    var mate = false
    var color: Color = Color(hex: 0xFF3B4D)

    var body: some View {
        let ink = Self.ink(on: color)
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 9.5, weight: .black))
                .foregroundStyle(color)
                .frame(width: 15, height: 15)
                .background(Circle().fill(ink))
            Text(mate ? "Checkmate" : "Check")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(ink)
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

    /// The words' color: white on the reds, near-black on a light capsule, such as a pale accent.
    static func ink(on color: Color) -> Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .white }
        let linear = { (value: CGFloat) -> Double in
            let c = min(max(Double(value), 0), 1)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return luminance > 0.3 ? Color.black.opacity(0.82) : .white
    }
}

/// Shows `CheckCallout` over the checked king for a moment after each check.
/// `anchor` turns the king's square into the point the callout is centered on.
struct CheckCalloutLayer: View {
    let game: GameModel
    var color: Color = Color(hex: 0xFF3B4D)
    /// Seconds until the checking piece is down, on a board that animates its moves.
    var landing: ((GameModel) -> TimeInterval)? = nil
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
        .onChange(of: game.moveCount, initial: true) { old, count in
            announce(after: count, fresh: old != count)
        }
    }

    /// Calls the check out over the king for a moment, once the checking piece is down. A board
    /// drawn again with the same position (back from Home, the Big Board, another look) only
    /// shows what is left of a callout already made, so the same check is never called twice.
    private func announce(after count: Int, fresh: Bool) {
        guard game.checkedKing != nil else {
            shownAfter = nil
            return
        }
        let now = Date()
        if fresh || game.checkCallout?.move != count {
            let from = now.addingTimeInterval(fresh ? (landing?(game) ?? 0) : 0)
            // Checkmate stays: the game is over and the board says why.
            let until = game.isCheckmate ? Date.distantFuture : from.addingTimeInterval(Self.seconds)
            game.checkCallout = (move: count, from: from, until: until)
        }
        guard let callout = game.checkCallout, callout.until > now else {
            shownAfter = nil
            return
        }
        let wait = callout.from.timeIntervalSince(now)
        shownAfter = wait > 0 ? nil : count
        Task { @MainActor in
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                guard game.moveCount == count else { return }
                shownAfter = count
            }
            guard callout.until != .distantFuture else { return }
            try? await Task.sleep(for: .seconds(max(0, callout.until.timeIntervalSinceNow)))
            if shownAfter == count { shownAfter = nil }
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
