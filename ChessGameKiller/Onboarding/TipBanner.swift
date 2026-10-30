import SwiftUI

/// One tip on a slim line of glass: an icon in the look's accent, one sentence, and a close mark.
/// Tap it anywhere to put it away.
struct TipBanner: View {
    let tip: AppTip
    let theme: BoardTheme
    let close: () -> Void

    var body: some View {
        let accent = theme.accent ?? .accentColor
        Button(action: close) {
            HStack(spacing: 10) {
                Image(systemName: tip.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 22)
                Text(tip.text)
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassPane(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tip. \(tip.text)")
        .accessibilityHint("Dismisses the tip")
    }
}

/// The game screen's tips: watches the game and shows at most one tip at a time, the first
/// time each would help. Each fades after a few seconds, or when tapped, and never comes back.
struct GameTips: View {
    let match: MatchController
    let theme: BoardTheme
    let bigBoard: Bool
    /// Ghost Vision is switched on in Settings.
    let ghostVisionOn: Bool
    /// Something else has the spot right now (the army's news, the coach unfolded, a held board).
    let blocked: Bool

    @State private var shown: AppTip?
    @State private var playerMoves = 0
    @State private var justUndid = false
    @State private var gameNumber = -1

    private static let showFor: Duration = .seconds(7)

    var body: some View {
        ZStack {
            if let shown, !blocked {
                TipBanner(tip: shown, theme: theme) { hide(shown) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: shown)
        .onAppear {
            if let tip = TipBook.showcased() { shown = tip }
        }
        .onChange(of: match.gameNumber, initial: true) { _, number in
            guard number != gameNumber else { return }
            gameNumber = number
            playerMoves = 0
            justUndid = false
        }
        .onChange(of: match.game.plyCount) { old, new in
            guard match.gameNumber == gameNumber else { return }
            if new > old, let played = match.game.lastPlayed, match.game.humanColors.contains(played.color) {
                playerMoves += 1
            } else if new < old, new > 0 {
                // A take-back. Only a game that earns XP is worth the tip.
                justUndid = match.setup.opponent == .computer
                playerMoves = max(0, playerMoves - 1)
            }
            consider()
        }
        .onChange(of: match.ghostLine != nil) { _, _ in consider() }
        .onChange(of: bigBoard) { _, _ in consider() }
        .onChange(of: blocked) { _, isBlocked in
            // A tip under a held board has done its job: the player found it.
            if isBlocked, shown == .ghostVision { shown = nil }
        }
    }

    private func consider() {
        guard shown == nil, !blocked, !Welcome.isUnderTest, match.hasStarted, !match.isOver else { return }
        let tip = TipBook.next(playerMoves: playerMoves,
                               lineReady: ghostVisionOn && match.ghostLine != nil,
                               justUndid: justUndid, bigBoard: bigBoard)
        justUndid = false
        guard let tip else { return }
        TipBook.markSeen(tip)
        shown = tip
        Task { @MainActor in
            try? await Task.sleep(for: Self.showFor)
            hide(tip)
        }
    }

    private func hide(_ tip: AppTip) {
        if shown == tip { shown = nil }
    }
}
