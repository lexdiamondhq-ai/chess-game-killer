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
                Text(status)
                    .font(.caption2.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? sideColor : Color.secondary)
                    .lineLimit(1)
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
            RivalSigil(rival: match.setup.level.rival, size: 40, glows: theme.glows)
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

/// Glass on the dark themes; glowing in the side's color when it is that side's turn.
private struct PlateBackground: View {
    let theme: BoardTheme
    let glow: Color?
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            .overlay {
                shape.strokeBorder(glow?.opacity(theme.glows ? 0.7 : 0.6) ?? Color.primary.opacity(theme.glows ? 0.1 : 0.06),
                                   lineWidth: glow == nil ? 1 : 1.5)
            }
            .shadow(color: glow.map { $0.opacity(theme.glows ? 0.35 : 0.25) } ?? .black.opacity(theme.glows ? 0 : 0.06),
                    radius: glow == nil ? 6 : 14, y: theme.glows ? 0 : 2)
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
                .font(.system(size: size, weight: .semibold, design: .themed).monospacedDigit())
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

/// What one side has taken, down the edge of the board: each kind of the
/// opponent's pieces with how many are gone, biggest first, and the material
/// lead at the bottom when there is one.
struct CaptureRail: View {
    let match: MatchController
    let theme: BoardTheme
    /// The side that did the capturing.
    let by: Piece.Color
    var width: CGFloat = 26

    var body: some View {
        let taken = match.game.captured(by: by)
        let lead = match.game.materialLead(for: by)
        let glow = theme.glows ? (by.opposite == .white ? theme.whiteGlow : theme.blackGlow) : nil
        VStack(spacing: 6) {
            ForEach(taken) { entry in
                VStack(spacing: 0) {
                    Image(theme.imageName(for: Piece(entry.kind, color: by.opposite, square: .a1)))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: width - 2, height: width - 2)
                        .shadow(color: glow?.opacity(0.8) ?? .black.opacity(0.15), radius: 2)
                    Text("\(entry.count)")
                        .font(.system(size: 10.5, weight: .bold, design: .themed).monospacedDigit())
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
                .transition(.scale.combined(with: .opacity))
            }
            if lead > 0 {
                Text("+\(lead)")
                    .font(.system(size: 11, weight: .heavy, design: .themed))
                    .foregroundStyle(theme.bestArrow)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .center)
        .animation(.snappy(duration: 0.3), value: taken)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(taken: taken, lead: lead))
    }

    private func label(taken: [CapturedCount], lead: Int) -> String {
        guard !taken.isEmpty else { return "\(theme.name(of: by)) has captured nothing" }
        let pieces = taken.map { "\($0.count) \(name(of: $0.kind))\($0.count == 1 ? "" : "s")" }
        var text = "\(theme.name(of: by)) has captured " + pieces.joined(separator: ", ")
        if lead > 0 { text += ", up \(lead)" }
        return text
    }

    private func name(of kind: Piece.Kind) -> String {
        switch kind {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        }
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
                                .padding(.horizontal, isLast && theme.glows ? 7 : 0)
                                .padding(.vertical, 2)
                                .background {
                                    if isLast && theme.glows {
                                        Capsule()
                                            .fill(Color.primary.opacity(theme.isDark ? 0.1 : 0.07))
                                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    // The executive look marks the newest move with a fine accent line.
                                    if isLast && !theme.glows {
                                        Rectangle()
                                            .fill(theme.accent ?? .accentColor)
                                            .frame(height: 1.5)
                                            .offset(y: 2)
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
        .font(theme.glows ? Font.system(.caption, design: .themed) : Font.system(.footnote).monospacedDigit())
        .frame(height: 24)
        .mask {
            LinearGradient(colors: [.clear, .black, .black, .black], startPoint: .leading, endPoint: .trailing)
        }
        .accessibilityLabel(moves.isEmpty ? "No moves yet" : "Moves: \(moves.joined(separator: " "))")
    }
}
