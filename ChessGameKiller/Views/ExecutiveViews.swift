import ChessKit
import SwiftUI

// The quiet "executive" game screen used by every theme except Neon:
// one player above the board and one below, plain type, fine lines, no glow,
// and a labeled row of controls around the coach orb.

/// One player's line above or below the board: avatar, name, status with
/// what they have captured, and their clock.
struct ExecutivePlate: View {
    let match: MatchController
    let theme: BoardTheme
    let color: Piece.Color

    private var isComputer: Bool { match.setup.opponent == .computer && !match.game.humanColors.contains(color) }
    private var isActive: Bool { !match.isOver && match.game.activeColor == color }
    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        HStack(spacing: 12) {
            avatar
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if isActive {
                        Circle()
                            .fill(accent)
                            .frame(width: 6, height: 6)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(status)
                        .font(.system(size: 12.5, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? Color.primary.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        // The words come first; the strip of captured pieces condenses to make room.
                        .layoutPriority(1)
                    CapturedPieces(match: match, theme: theme, by: color)
                }
            }
            Spacer(minLength: 8)
            if let clock = match.clock {
                ExecutiveClock(clock: clock, color: color, theme: theme)
            }
        }
        .padding(.horizontal, 4)
        .animation(.snappy(duration: 0.3), value: isActive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
        .rivalBubble(match, theme: theme, show: isComputer, avatarWidth: 54)
    }

    /// Name, status, time left and captures. The label stands in for the children's
    /// own, and the strip of pieces is hidden from VoiceOver, so both are spelled out here.
    private var spokenLabel: String {
        var text = "\(name), \(status)"
        if let clock = match.clock {
            text += ", \(clock.remaining(for: color).clockLabel) left"
        }
        let taken = match.game.captured(by: color)
        if !taken.isEmpty {
            text += ", " + CaptureRail.spokenCaptures(taken, lead: match.game.materialLead(for: color), name: theme.name(of: color))
        }
        return text
    }

    @ViewBuilder
    private var avatar: some View {
        if isComputer {
            RivalPortrait(rival: match.setup.level.rival, size: 38, glows: false)
        } else {
            PieceImage(piece: Piece(.king, color: color, square: .e1), theme: theme, size: 30)
                .frame(width: 38, height: 38)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
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
            return match.winner == nil ? "Draw" : "Lost"
        }
        if isActive {
            if isComputer {
                if match.isComputerThinking { return "Thinking" }
                if match.engineFailed, !match.game.isHumanTurn { return "Engine unavailable" }
                return "To move"
            }
            if match.game.checkedKing != nil { return "\(theme.name(of: color)) in check" }
            return "\(theme.name(of: color)) to move"
        }
        if isComputer {
            let rival = match.setup.level.rival
            return "\(rival.level.name) · \(rival.elo)"
        }
        return theme.name(of: color)
    }
}

/// The pieces a side has taken, small and overlapping, with the material lead.
/// When the line runs short of room, one piece of each kind with its count instead.
private struct CapturedPieces: View {
    let match: MatchController
    let theme: BoardTheme
    /// The side that did the capturing.
    let by: Piece.Color

    private static let size: CGFloat = 15

    var body: some View {
        let taken = match.game.captured(by: by)
        let lead = match.game.materialLead(for: by)
        ViewThatFits(in: .horizontal) {
            strip(taken, lead: lead, stacked: true)
            strip(taken, lead: lead, stacked: false)
        }
        .animation(.snappy(duration: 0.3), value: taken)
        .accessibilityHidden(true)
    }

    /// Every piece taken, overlapping within its kind; or, condensed, one of each kind with a count.
    private func strip(_ taken: [CapturedCount], lead: Int, stacked: Bool) -> some View {
        HStack(spacing: stacked ? 4 : 3) {
            ForEach(taken) { entry in
                if stacked {
                    HStack(spacing: -Self.size * 0.55) {
                        ForEach(0..<entry.count, id: \.self) { _ in
                            image(of: entry.kind)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        image(of: entry.kind)
                        if entry.count > 1 {
                            Text("\(entry.count)")
                                .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if lead > 0 {
                Text("+\(lead)")
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func image(of kind: Piece.Kind) -> some View {
        Image(theme.imageName(for: Piece(kind, color: by.opposite, square: .a1)))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: Self.size, height: Self.size)
    }
}

/// A side's time in a quiet box that turns solid while its clock runs.
private struct ExecutiveClock: View {
    let clock: ChessClock
    let color: Piece.Color
    let theme: BoardTheme

    private var isRunning: Bool { clock.running == color }

    var body: some View {
        TimelineView(.periodic(from: .now, by: isRunning ? 0.1 : 60)) { _ in
            let remaining = clock.remaining(for: color)
            let urgent = isRunning && remaining < .seconds(10)
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            Text(remaining.clockLabel)
                .font(.system(size: 21, weight: .medium).monospacedDigit())
                .foregroundStyle(isRunning ? Color.black.opacity(0.88) : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if isRunning {
                        shape.fill(urgent ? Color(hex: 0xFF4D6D) : Color.white.opacity(0.92))
                    } else {
                        shape.fill(Color.primary.opacity(0.04))
                            .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    }
                }
                // Inside the timeline, so VoiceOver reads the time as it stands now.
                .accessibilityLabel("\(theme.name(of: color)) has \(remaining.clockLabel) left")
        }
        .animation(.snappy(duration: 0.25), value: isRunning)
    }
}

/// The middle of the top bar: the opponent and clock in small capitals over the move number.
struct ExecutiveMatchTitle: View {
    let match: MatchController

    var body: some View {
        VStack(spacing: 1) {
            Text(kicker.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(1.6)
                .foregroundStyle(.secondary)
            Text(headline)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var kicker: String {
        let opponent = match.setup.opponent == .computer ? "vs \(match.setup.level.rival.name)" : "Two players"
        let control = match.setup.timeControl
        guard control.isTimed else { return opponent }
        return "\(opponent) · \(control.rawValue.replacingOccurrences(of: "+", with: " + "))"
    }

    private var headline: String {
        if match.isOver { return "Game over" }
        let moves = match.game.moves.count
        return moves == 0 ? "New game" : "Move \(moves / 2 + 1)"
    }
}

/// A plain icon with its name under it, for the row around the orb.
struct DockButton: View {
    let title: String
    let symbol: String
    var isOn = false
    let theme: BoardTheme
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Glyph(name: symbol, size: Glyph.isGlyph(symbol) ? 25 : 24, weight: .regular)
                    .frame(height: 25)
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? (theme.accent ?? .accentColor) : Color.primary.opacity(0.7))
            .opacity(isEnabled ? 1 : 0.35)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "")
    }
}
