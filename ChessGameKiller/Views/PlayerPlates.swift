import ChessKit
import SwiftUI

/// Both players on one line of glass, for while the coach is open: the rival and you with your
/// clocks between you. The side to move reads brighter.
struct PlayersStrip: View {
    let match: MatchController
    let theme: BoardTheme

    /// The side drawn at the top of the board.
    private var topColor: Piece.Color { match.isBoardFlipped ? .white : .black }

    var body: some View {
        HStack(spacing: 8) {
            PlayerName(match: match, theme: theme, color: topColor)
            if let clock = match.clock {
                ClockLabel(clock: clock, color: topColor, owner: clockOwner(topColor), theme: theme, size: 13)
            }
            Text("·")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            if let clock = match.clock {
                ClockLabel(clock: clock, color: topColor.opposite, owner: clockOwner(topColor.opposite), theme: theme, size: 13)
            }
            PlayerName(match: match, theme: theme, color: topColor.opposite, pictureAfter: true)
        }
        .font(.system(.footnote, design: .themed).weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPane(Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
    }

    private func clockOwner(_ color: Piece.Color) -> String {
        ExecutivePlate.spokenClockOwner(of: color, in: match, theme: theme)
    }
}

/// A player's name with a small picture, for the strip: the rival's portrait, or your king.
private struct PlayerName: View {
    let match: MatchController
    let theme: BoardTheme
    let color: Piece.Color
    /// The picture after the name, for the side on the right.
    var pictureAfter = false

    private var isComputer: Bool { match.setup.opponent == .computer && !match.game.humanColors.contains(color) }
    private var isActive: Bool { !match.isOver && match.game.activeColor == color }

    var body: some View {
        HStack(spacing: 5) {
            if !pictureAfter { picture }
            Text(ExecutivePlate.displayName(of: color, in: match, theme: theme))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
            if pictureAfter { picture }
        }
    }

    @ViewBuilder
    private var picture: some View {
        if isComputer {
            RivalPortrait(rival: match.setup.level.rival, size: 18, glows: theme.glows)
        } else {
            PieceImage(piece: Piece(.king, color: color, square: .e1), theme: theme, size: 18)
        }
    }
}

/// A side's remaining time, ticking while its clock runs and red in the last ten seconds.
struct ClockLabel: View {
    let clock: ChessClock
    let color: Piece.Color
    /// "Your clock" or "Pulse's clock", for VoiceOver.
    let owner: String
    let theme: BoardTheme
    var size: CGFloat = 14

    private var isRunning: Bool { clock.running == color }

    var body: some View {
        TimelineView(.periodic(from: .now, by: isRunning ? 0.1 : 60)) { _ in
            let remaining = clock.remaining(for: color)
            let urgent = isRunning && remaining < .seconds(10)
            Text(remaining.clockLabel)
                .font(.system(size: size, weight: .semibold, design: .themed).monospacedDigit())
                .foregroundStyle(urgent ? Color(hex: 0xFF4D6D) : (isRunning ? Color.primary : Color.secondary))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background {
                    if isRunning {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(theme.isDark ? 0.1 : 0.06))
                    }
                }
                // Inside the timeline, so VoiceOver reads the time as it stands now.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(owner)
                .accessibilityValue(remaining.formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
        }
    }
}

/// The moves so far in one line under the board, from the left. Once the line is full it
/// scrolls to keep the newest move in view, and the oldest fade out at the left edge.
/// Before the first move it says how to begin.
struct MoveRibbon: View {
    let moves: [String]
    let theme: BoardTheme

    @State private var lineWidth: CGFloat = 0

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        GeometryReader { geo in
            if moves.isEmpty {
                Text("Tap a piece to see where it can go")
                    .font(.system(.footnote, design: .themed))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            } else {
                let overflows = lineWidth > geo.size.width + 0.5
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        line
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.size.width
                            } action: { width in
                                lineWidth = width
                            }
                            // At least as wide as the row, so a short game sits at the left.
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .leading)
                    }
                    // A long game opens at its newest move, even when the screen is rebuilt mid-game.
                    .defaultScrollAnchor(.trailing)
                    .onChange(of: moves.count) { _, count in
                        guard count > 0 else { return }
                        withAnimation(.snappy(duration: 0.3)) {
                            proxy.scrollTo(count - 1, anchor: .trailing)
                        }
                    }
                }
                .mask {
                    LinearGradient(stops: [
                        .init(color: overflows ? .clear : .black, location: 0),
                        .init(color: .black, location: min(1, 28 / max(geo.size.width, 1))),
                    ], startPoint: .leading, endPoint: .trailing)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(moves.isEmpty ? "No moves yet. Tap a piece to see where it can go." : "Moves: \(moves.joined(separator: " "))")
    }

    private var line: some View {
        HStack(spacing: 8) {
            ForEach(Array(moves.enumerated()), id: \.offset) { index, san in
                let isLast = index == moves.count - 1
                HStack(spacing: 3) {
                    if index % 2 == 0 {
                        Text("\(index / 2 + 1).")
                            .foregroundStyle(.tertiary)
                    }
                    Text(san)
                        .fontWeight(.semibold)
                        .foregroundStyle(isLast ? Color.primary : Color.secondary)
                        .overlay(alignment: .bottom) {
                            // The newest move is marked with a fine accent line.
                            if isLast {
                                Rectangle()
                                    .fill(accent)
                                    .frame(height: 1.5)
                                    .offset(y: 2)
                                    .shadow(color: theme.glows ? accent.opacity(0.8) : .clear, radius: 3)
                            }
                        }
                }
                .id(index)
            }
        }
        .font(Font.system(.footnote, design: .themed).monospacedDigit())
        .padding(.vertical, 2)
    }
}
