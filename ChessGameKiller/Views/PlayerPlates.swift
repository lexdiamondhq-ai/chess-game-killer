import ChessKit
import SwiftUI

/// The two players above the board: who they are, their clocks, what they've
/// captured, and whose turn it is. The side to move glows in its own color.
struct PlayerPlates: View {
    let match: MatchController
    let theme: BoardTheme
    /// One thin line instead of two plates, for when the coach is open.
    var compact = false

    /// The side drawn at the top of the board.
    private var topColor: Piece.Color { match.isBoardFlipped ? .white : .black }

    var body: some View {
        if compact {
            strip
                .transition(.opacity)
        } else {
            HStack(spacing: 10) {
                PlayerPlate(match: match, theme: theme, color: topColor)
                PlayerPlate(match: match, theme: theme, color: topColor.opposite)
            }
            .transition(.opacity)
        }
    }

    private var strip: some View {
        HStack(spacing: 8) {
            PlayerName(match: match, theme: theme, color: topColor, size: 18)
            if let clock = match.clock {
                ClockLabel(clock: clock, color: topColor, theme: theme, size: 13)
            }
            Text("·").foregroundStyle(.tertiary)
            if let clock = match.clock {
                ClockLabel(clock: clock, color: topColor.opposite, theme: theme, size: 13)
            }
            PlayerName(match: match, theme: theme, color: topColor.opposite, size: 18)
        }
        .font(.footnote.weight(.semibold))
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(PlateBackground(theme: theme, glow: nil, radius: 15))
        .accessibilityElement(children: .combine)
    }
}

/// One player's plate.
private struct PlayerPlate: View {
    let match: MatchController
    let theme: BoardTheme
    let color: Piece.Color

    private var isComputer: Bool { match.setup.opponent == .computer && !match.game.humanColors.contains(color) }
    private var isActive: Bool { !match.isOver && match.game.sideToMove == color }
    private var sideColor: Color { theme.sideColor(color) }

    var body: some View {
        HStack(spacing: 8) {
            avatar
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isActive ? sideColor : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let clock = match.clock {
                        ClockLabel(clock: clock, color: color, theme: theme, size: 14)
                    }
                }
                HStack(spacing: 6) {
                    Text(status)
                        .font(.caption2.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? sideColor : Color.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    CapturedPieces(match: match, theme: theme, by: color)
                }
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(PlateBackground(theme: theme, glow: isActive ? sideColor : nil, radius: 18))
        .animation(.snappy(duration: 0.3), value: isActive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(status)")
    }

    @ViewBuilder
    private var avatar: some View {
        if isComputer {
            RivalSigil(rival: match.setup.level.rival, size: 40, glows: theme.isDark)
        } else {
            PieceImage(piece: Piece(.king, color: color, square: .e1), theme: theme, size: 36)
        }
    }

    private var name: String {
        if isComputer { return match.setup.level.rival.name }
        if match.setup.opponent == .computer { return "You" }
        return theme.name(of: color)
    }

    private var status: String {
        if match.isOver {
            if match.winner == color { return "Winner" }
            return match.winner == nil ? "Draw" : ""
        }
        if isActive {
            if isComputer { return match.isComputerThinking ? "thinking" : "to move" }
            if match.game.checkedKing != nil { return "\(theme.name(of: color)) is in check" }
            return "\(theme.name(of: color)) to move"
        }
        if isComputer {
            let rival = match.setup.level.rival
            return "\(rival.level.name) · Elo \(rival.elo)"
        }
        return theme.name(of: color)
    }
}

/// The name with a small avatar, for the compact strip.
private struct PlayerName: View {
    let match: MatchController
    let theme: BoardTheme
    let color: Piece.Color
    let size: CGFloat

    private var isComputer: Bool { match.setup.opponent == .computer && !match.game.humanColors.contains(color) }

    var body: some View {
        HStack(spacing: 4) {
            if isComputer {
                RivalSigil(rival: match.setup.level.rival, size: size, glows: false)
            } else {
                PieceImage(piece: Piece(.king, color: color, square: .e1), theme: theme, size: size)
            }
            Text(name).foregroundStyle(theme.sideColor(color))
        }
    }

    private var name: String {
        if isComputer { return match.setup.level.rival.name }
        if match.setup.opponent == .computer { return "You" }
        return theme.name(of: color)
    }
}

/// Glass on Neon, a soft card on Walnut; glowing in the side's color when it is that side's turn.
private struct PlateBackground: View {
    let theme: BoardTheme
    let glow: Color?
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            .overlay {
                shape.strokeBorder(glow?.opacity(theme.isDark ? 0.7 : 0.6) ?? Color.primary.opacity(theme.isDark ? 0.1 : 0.06),
                                   lineWidth: glow == nil ? 1 : 1.5)
            }
            .shadow(color: glow.map { $0.opacity(theme.isDark ? 0.35 : 0.25) } ?? .black.opacity(theme.isDark ? 0 : 0.06),
                    radius: glow == nil ? 6 : 14, y: theme.isDark ? 0 : 2)
    }
}

/// A side's remaining time, ticking while its clock runs and red in the last ten seconds.
struct ClockLabel: View {
    let clock: ChessClock
    let color: Piece.Color
    let theme: BoardTheme
    var size: CGFloat = 14

    private var isRunning: Bool { clock.running == color }

    var body: some View {
        TimelineView(.periodic(from: .now, by: isRunning ? 0.1 : 60)) { context in
            let remaining = clock.remaining(for: color)
            let urgent = isRunning && remaining < .seconds(10)
            Text(remaining.clockLabel)
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(urgent ? Color(hex: 0xFF4D6D) : (isRunning ? Color.primary : Color.secondary))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background {
                    if isRunning {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(theme.isDark ? 0.08 : 0.05))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                    }
                }
        }
        .accessibilityLabel("\(theme.name(of: color)) has \(clock.remaining(for: color).clockLabel) left")
    }
}

/// What a side has taken, as tiny pieces, with the material lead when it has one.
private struct CapturedPieces: View {
    let match: MatchController
    let theme: BoardTheme
    let by: Piece.Color

    private static let values: [Piece.Kind: Int] = [.pawn: 1, .knight: 3, .bishop: 3, .rook: 5, .queen: 9]
    private static let order: [Piece.Kind] = [.queen, .rook, .bishop, .knight, .pawn]

    var body: some View {
        let taken = captured(by: by)
        let lead = material(taken) - material(captured(by: by.opposite))
        let glow = theme.isDark ? (by.opposite == .white ? theme.whiteGlow : theme.blackGlow) : nil
        HStack(spacing: 4) {
            HStack(spacing: -3) {
                ForEach(Array(taken.prefix(8).enumerated()), id: \.offset) { _, kind in
                    Image(theme.imageName(for: Piece(kind, color: by.opposite, square: .a1)))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .shadow(color: glow?.opacity(0.8) ?? .clear, radius: 2)
                }
            }
            if lead > 0 {
                Text("+\(lead)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.bestArrow)
            }
        }
        .frame(height: 14)
        .accessibilityLabel(taken.isEmpty ? "" : "Captured \(taken.count) pieces" + (lead > 0 ? ", up \(lead)" : ""))
    }

    /// Pieces of the other color missing from the board, biggest first.
    private func captured(by color: Piece.Color) -> [Piece.Kind] {
        var counts: [Piece.Kind: Int] = [.pawn: 8, .knight: 2, .bishop: 2, .rook: 2, .queen: 1]
        for placed in match.game.pieces where placed.piece.color == color.opposite {
            counts[placed.piece.kind, default: 0] -= 1
        }
        return Self.order.flatMap { kind in Array(repeating: kind, count: max(0, counts[kind] ?? 0)) }
    }

    private func material(_ kinds: [Piece.Kind]) -> Int {
        kinds.reduce(0) { $0 + (Self.values[$1] ?? 0) }
    }
}

/// The moves so far in one scrolling line under the board, newest on the right.
struct MoveRibbon: View {
    let moves: [String]
    let theme: BoardTheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
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
                                .padding(.horizontal, isLast ? 7 : 0)
                                .padding(.vertical, 2)
                                .background {
                                    if isLast {
                                        Capsule()
                                            .fill(Color.primary.opacity(theme.isDark ? 0.1 : 0.07))
                                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                                    }
                                }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 4)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
            }
            .onChange(of: moves.count) { _, count in
                guard count > 0 else { return }
                withAnimation(.snappy(duration: 0.3)) {
                    proxy.scrollTo(count - 1, anchor: .trailing)
                }
            }
        }
        .font(.system(.caption, design: .rounded))
        .frame(height: 24)
        .mask {
            LinearGradient(colors: [.clear, .black, .black, .black], startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityLabel(moves.isEmpty ? "No moves yet" : "Moves: \(moves.joined(separator: " "))")
    }
}
