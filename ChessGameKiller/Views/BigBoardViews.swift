import ChessKit
import SwiftUI

/// Big Board's bottom tray. Closed, it is a grabber over a thin strip that shows
/// who is winning. Pulled up (or tapped), it opens the usual controls with the
/// coach orb, plus New game, Settings and the way back to the normal screen.
struct BigBoardTray<Dock: View>: View {
    let match: MatchController
    let theme: BoardTheme
    @Binding var isOpen: Bool
    let onNewGame: () -> Void
    let onSettings: () -> Void
    let onExit: () -> Void
    /// Set when the army isn't in the dock already.
    var onArmy: (() -> Void)?
    /// Your saved games, to rewind.
    var onGames: (() -> Void)?
    @ViewBuilder let dock: () -> Dock

    @GestureState private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            handle
            if isOpen {
                VStack(spacing: 4) {
                    dock()
                    extras
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
                        .strokeBorder(theme.glows ? (theme.accent ?? .primary).opacity(0.25) : Color.primary.opacity(0.08),
                                      lineWidth: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
                .opacity(isOpen ? 1 : 0.85)
        }
        .offset(y: max(-24, min(drag, 60)) * 0.4)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isOpen)
    }

    /// The grabber and the eval strip. Swipe up or tap to open, swipe down to close.
    private var handle: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.primary.opacity(0.28))
                .frame(width: 38, height: 5)
            if !isOpen {
                EvalStrip(evaluation: match.evaluation, playerColor: match.setup.playerColor, theme: theme)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, isOpen ? 4 : 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .updating($drag) { value, state, _ in state = value.translation.height }
                .onEnded { value in
                    let dy = value.predictedEndTranslation.height
                    if dy < -30 { isOpen = true } else if dy > 30 { isOpen = false }
                }
        )
        .onTapGesture { isOpen.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOpen ? "Close the tools" : "Open the tools")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isOpen.toggle() }
    }

    /// What the hidden top bar would have held, and the way back to the normal screen.
    private var extras: some View {
        HStack(spacing: 0) {
            DockButton(title: "New game", symbol: "plus", theme: theme, action: onNewGame)
            if let onArmy {
                DockButton(title: "Army", symbol: "shield.lefthalf.filled", theme: theme, action: onArmy)
            }
            if let onGames {
                DockButton(title: "Games", symbol: "backward.circle", theme: theme, action: onGames)
            }
            DockButton(title: "Settings", symbol: "gearshape", theme: theme, action: onSettings)
            DockButton(title: "Normal view", symbol: "arrow.down.right.and.arrow.up.left", theme: theme, action: onExit)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}

/// A thin bar for how the game stands, from the player's side: their share
/// grows to the right as they get on top. The number sits at the end.
struct EvalStrip: View {
    let evaluation: Evaluation?
    let playerColor: Piece.Color
    let theme: BoardTheme

    private var mine: Evaluation? {
        guard let evaluation else { return nil }
        return playerColor == .white ? evaluation : evaluation.flipped
    }

    /// The player's share of the bar, 0 to 1.
    private var share: Double {
        guard let mine else { return 0.5 }
        return (mine.winningChances + 1) / 2
    }

    private var caption: String {
        guard let mine else { return "Even" }
        if case .centipawns(let cp) = mine, abs(cp) < 20 { return "Even" }
        return mine.label
    }

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.sideColor(playerColor.opposite).opacity(theme.isDark ? 0.9 : 1))
                    Capsule()
                        .fill(theme.sideColor(playerColor))
                        .frame(width: max(4, geo.size.width * share))
                        .shadow(color: theme.glows ? theme.sideColor(playerColor).opacity(0.7) : .clear, radius: 5)
                }
                .overlay { Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
            }
            .frame(height: 6)
            Text(caption)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .animation(.easeInOut(duration: 0.5), value: share)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Evaluation")
        .accessibilityValue(caption == "Even" ? "Even" : "\(caption) for you")
    }
}

/// Shown under the board while the player swipes back through the game.
struct BrowsePill: View {
    let ply: Int
    let total: Int
    let san: String?
    let theme: BoardTheme
    let onLive: () -> Void

    var body: some View {
        Button(action: onLive) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                Text(label)
                    .monospacedDigit()
                Text("·").foregroundStyle(.tertiary)
                Text("Back to live")
                    .foregroundStyle(theme.accent ?? .accentColor)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label). Back to the live position")
    }

    private var label: String {
        if ply == 0 { return "Start" }
        let number = (ply + 1) / 2
        let dots = ply % 2 == 0 ? "…" : "."
        return "\(number)\(dots) \(san ?? "")  ·  \(ply)/\(total)"
    }
}
