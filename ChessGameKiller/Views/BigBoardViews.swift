import ChessKit
import SwiftUI

/// Big Board's tray at the bottom, on the same glass as the dock. Closed, it is a grabber over a
/// thin strip that shows how the game stands. Pulled up (or tapped), it opens the dock's controls
/// with the coach orb, and under them what the hidden top bar holds and the way back.
struct BigBoardTray<Dock: View>: View {
    let match: MatchController
    let theme: BoardTheme
    @Binding var isOpen: Bool
    /// While the coach is unfolded in the tray, the second row steps aside for it.
    var coachIsWide = false
    let onNewGame: () -> Void
    let onSettings: () -> Void
    let onExit: () -> Void
    var onArmy: (() -> Void)?
    /// Your saved games, to rewind.
    var onGames: (() -> Void)?
    /// Back to the home screen, when it is on.
    var onHome: (() -> Void)?
    @ViewBuilder let dock: () -> Dock

    @GestureState private var drag: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            handle
            if isOpen {
                VStack(spacing: 0) {
                    dock()
                    if !coachIsWide {
                        Rectangle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 0.5)
                            .padding(.horizontal, 18)
                        extras
                            .padding(.top, 4)
                            .transition(.opacity)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .glassPane(RoundedRectangle(cornerRadius: isOpen ? 32 : 22, style: .continuous))
        .offset(y: max(-24, min(drag, 60)) * 0.4)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isOpen)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: coachIsWide)
    }

    /// The grabber and the eval strip. Swipe up or tap to open, swipe down to close.
    private var handle: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color.primary.opacity(0.3))
                .frame(width: 38, height: 5)
            if !isOpen {
                EvalStrip(evaluation: match.evaluation, playerColor: match.setup.playerColor, theme: theme)
                    .padding(.horizontal, 18)
                    .transition(.opacity)
            }
        }
        .padding(.top, 7)
        .padding(.bottom, isOpen ? 2 : 12)
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
        .accessibilityLabel(isOpen ? "Hide controls" : "Show controls")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isOpen.toggle() }
    }

    /// What the hidden top bar holds, the same way round, and the way back to the normal screen.
    private var extras: some View {
        HStack(spacing: 0) {
            if let onHome {
                DockButton(title: "Home", symbol: Glyphs.home, theme: theme, action: onHome)
            }
            DockButton(title: "New game", symbol: "plus", theme: theme, action: onNewGame)
            Menu {
                if let onGames {
                    Button(action: onGames) { Label("Your games", image: Glyphs.games) }
                }
                if let onArmy {
                    Button(action: onArmy) { Label("Your pieces", image: Glyphs.army) }
                }
                Button(action: onSettings) { Label("Settings", image: Glyphs.settings) }
            } label: {
                DockLabel(title: "More", symbol: "ellipsis", theme: theme)
            }
            .accessibilityLabel("More")
            DockButton(title: "Exit Big Board", symbol: Glyphs.normalView, theme: theme, action: onExit)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }
}

/// A thin bar for how the game stands, from your side: your share, in the accent, grows from the
/// left as you get on top, and the rival's share is the rest, in a lighter tone over the track.
/// A fine tick marks even. It reads "—" until the engine has answered.
struct EvalStrip: View {
    let evaluation: Evaluation?
    let playerColor: Piece.Color
    let theme: BoardTheme

    private var accent: Color { theme.accent ?? .accentColor }

    private var mine: Evaluation? {
        guard let evaluation else { return nil }
        return playerColor == .white ? evaluation : evaluation.flipped
    }

    /// Your share of the bar, 0 to 1.
    private var share: Double? {
        mine.map { ($0.winningChances + 1) / 2 }
    }

    private var caption: String {
        guard let mine else { return "—" }
        if case .centipawns(let cp) = mine, abs(cp) < 20 { return "Even" }
        return mine.label
    }

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    if let share {
                        Capsule().fill(Color.primary.opacity(0.3))
                        Capsule()
                            .fill(accent)
                            .frame(width: max(4, geo.size.width * share))
                            .shadow(color: theme.glows ? accent.opacity(0.7) : .clear, radius: 5)
                    }
                    Rectangle()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 1, height: 10)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .frame(height: 6)
            Text(caption)
                .font(.system(.caption, design: .themed).weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .animation(.easeInOut(duration: 0.5), value: share)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Evaluation")
        .accessibilityValue(spokenValue)
    }

    private var spokenValue: String {
        switch caption {
        case "—": return "Waiting for the engine"
        case "Even": return "Even"
        default: return "\(caption) for you"
        }
    }
}

/// Shown under the board while the player swipes back through the game.
struct BrowsePill: View {
    let ply: Int
    let san: String?
    let theme: BoardTheme
    let onLive: () -> Void

    var body: some View {
        Button(action: onLive) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                Text(label)
                    .monospacedDigit()
                Text("·").foregroundStyle(.tertiary)
                Text("Back to game")
                    .foregroundStyle(theme.accent ?? .accentColor)
            }
            .font(.system(.footnote, design: .themed).weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .glassPane(Capsule())
            // Easier to hit than it looks.
            .contentShape(Capsule().inset(by: -10))
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityLabel("\(label). Back to the game")
    }

    /// "12. Nf3", "12… Nf6", or "Start".
    private var label: String {
        if ply == 0 { return "Start" }
        let number = (ply + 1) / 2
        let dots = ply % 2 == 0 ? "…" : "."
        return "\(number)\(dots) \(san ?? "")"
    }
}
