import ChessKit
import SwiftUI

// The game screen's chrome, the same on every look: one player above the board and one below,
// each on its own glass, a labeled row of controls around the coach orb, and plain type.
// Neon keeps its colors and glows on the same glass.

/// One player's line above or below the board, on glass: avatar, name, a status that says only
/// what the name and the picture don't (whose move it is, check, the result), what they have
/// captured, and their clock.
struct ExecutivePlate: View {
    let match: MatchController
    let theme: BoardTheme
    let color: Piece.Color

    @ScaledMetric(relativeTo: .footnote) private var scaledStatusHeight: CGFloat = 16
    /// The status row's height. It stops growing where the line's type does.
    private var statusHeight: CGFloat { min(scaledStatusHeight, 21) }
    /// The player's army, so a selected named piece shows its name here.
    @Environment(ArmyStore.self) private var army: ArmyStore?

    private var isComputer: Bool { match.setup.opponent == .computer && !match.game.humanColors.contains(color) }
    private var isActive: Bool { !match.isOver && match.game.activeColor == color }
    private var accent: Color { theme.accent ?? .accentColor }
    /// On Neon the line of the side to move lights up in that side's color.
    private var glow: Color? { theme.glows && isActive ? theme.sideColor(color) : nil }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                avatar
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(.headline, design: .themed))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    statusRow
                        // The row keeps its height when it has nothing to say, so the name never jumps.
                        .frame(height: statusHeight, alignment: .leading)
                }
            }
            // The clock is its own element, so VoiceOver reads its time as it stands.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spokenLabel)
            Spacer(minLength: 8)
            if let clock = match.clock {
                ExecutiveClock(clock: clock, color: color, owner: clockOwner, theme: theme)
                    .fixedSize()
                    .layoutPriority(2)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPane(shape)
        .overlay {
            if let glow {
                shape.strokeBorder(
                    LinearGradient(colors: [glow.opacity(0.95), glow.opacity(0.3), glow.opacity(0.25), glow.opacity(0.8)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.2
                )
                .transition(.opacity)
            }
        }
        .background {
            if let glow {
                // Behind the glass, so the glass carries the color and the glow spills past its edge.
                shape.stroke(glow.opacity(0.55), lineWidth: 3)
                    .blur(radius: 9)
                    .transition(.opacity)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.snappy(duration: 0.3), value: isActive)
        .animation(.snappy(duration: 0.3), value: inCheck)
    }

    /// The CHECK tag, the turn dot and the status (or the selected army piece's name and rank),
    /// and the captured pieces. For a few seconds the rival's remark, or the coach's grade of
    /// your move, takes the place of the dot and the status; CHECK and the captures stay.
    private var statusRow: some View {
        HStack(spacing: 6) {
            if inCheck {
                CheckTag(color: theme.check)
                    .transition(.scale.combined(with: .opacity))
            }
            PlateRemark(match: match, theme: theme, isRival: isComputer) {
                statusWords
            }
            .layoutPriority(1)
            CapturedPieces(match: match, by: color)
        }
        .animation(.easeInOut(duration: 0.2), value: selectedArmyPiece?.name)
    }

    /// The turn dot and the status, or the selected army piece's name and rank.
    private var statusWords: some View {
        HStack(spacing: 6) {
            if isActive, !inCheck {
                Circle()
                    .fill(glow ?? accent)
                    .frame(width: 6, height: 6)
                    .transition(.scale.combined(with: .opacity))
            }
            if let piece = selectedArmyPiece {
                HStack(spacing: 4) {
                    Image(systemName: piece.rank == .legend ? "crown.fill" : "shield.lefthalf.filled")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(piece.color)
                    Text("\(piece.name) · \(piece.rank.title)")
                        .font(.system(.footnote, design: .themed).weight(.medium))
                        .foregroundStyle(Color.primary.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .layoutPriority(1)
                .transition(.opacity)
            } else if !status.isEmpty {
                Text(status)
                    .font(.system(.footnote, design: .themed).weight(isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? Color.primary.opacity(0.86) : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .transition(.opacity)
            }
        }
    }

    /// While the player has one of their named army pieces selected: its name and rank, in the
    /// rank's color. It is shown here rather than over the board, where it hid the move dots.
    private var selectedArmyPiece: (name: String, rank: ArmyRank, color: Color)? {
        guard !isComputer, let army, let square = match.game.selected,
              let placed = match.game.pieces.first(where: { $0.square == square }),
              placed.piece.color == color,
              let slot = army.slot(of: placed, in: match),
              let name = army.record(for: slot).name else { return nil }
        let rank = army.record(for: slot).rank
        // Black's own color is near black on every look but Neon, and would vanish on the glass.
        let readable = rank == .legend || placed.piece.color == .white || theme.glows
        return (name, rank, readable ? rank.color(for: placed.piece, theme: theme) : Color.secondary)
    }

    /// This side's king is in check right now.
    private var inCheck: Bool {
        guard !match.isOver, let king = match.game.checkedKing else { return false }
        return match.game.piece(at: king)?.color == color
    }

    /// Name, status and captures. The captured pieces are hidden from VoiceOver, so they are
    /// spelled out here; the clock speaks for itself.
    private var spokenLabel: String {
        var parts = [name]
        if inCheck { parts.append("in check") }
        if let piece = selectedArmyPiece {
            parts.append("\(piece.name), \(piece.rank.title)")
        } else if !status.isEmpty {
            parts.append(status)
        }
        let taken = match.game.captured(by: color)
        if !taken.isEmpty {
            parts.append(CapturedPieces.spoken(taken, lead: match.game.materialLead(for: color)))
        }
        return parts.joined(separator: ", ")
    }

    private var clockOwner: String {
        Self.spokenClockOwner(of: color, in: match, theme: theme)
    }

    /// How a line names a side: the rival's name or "You"; in a game between two people, the side's color.
    static func displayName(of color: Piece.Color, in match: MatchController, theme: BoardTheme) -> String {
        guard match.setup.opponent == .computer else { return theme.name(of: color) }
        return match.game.humanColors.contains(color) ? "You" : match.setup.level.rival.name
    }

    /// For VoiceOver: "Your clock", or "Pulse's clock".
    static func spokenClockOwner(of color: Piece.Color, in match: MatchController, theme: BoardTheme) -> String {
        if match.setup.opponent == .computer, match.game.humanColors.contains(color) { return "Your clock" }
        return "\(displayName(of: color, in: match, theme: theme))'s clock"
    }

    @ViewBuilder
    private var avatar: some View {
        if isComputer {
            RivalPortrait(rival: match.setup.level.rival, size: 40, glows: theme.glows)
        } else {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            PieceImage(piece: Piece(.king, color: color, square: .e1), theme: theme, size: 32)
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.06), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
    }

    private var name: String {
        Self.displayName(of: color, in: match, theme: theme)
    }

    /// The rival's level while it waits, "Thinking…" on its turn; "Your move" on yours, and
    /// nothing while you wait (your captures say enough). The result once the game is over.
    private var status: String {
        if match.isOver {
            if match.winner == color { return "Won" }
            return match.winner == nil ? "Draw" : "Lost"
        }
        if isComputer {
            if isActive { return match.engineFailed ? "Coach offline" : "Thinking…" }
            let rival = match.setup.level.rival
            return "\(rival.level.name) · \(rival.elo.replacingOccurrences(of: "~", with: ""))"
        }
        return isActive ? "Your move" : ""
    }
}

/// The pieces a side has taken, as small crisp silhouettes: they are the other side's, so their
/// color goes without saying. They overlap within a kind, with the material lead after them.
/// When the line runs short of room, one of each kind with a count; then only the lead.
private struct CapturedPieces: View {
    let match: MatchController
    /// The side that did the capturing.
    let by: Piece.Color

    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 14

    var body: some View {
        let taken = match.game.captured(by: by)
        let lead = match.game.materialLead(for: by)
        ViewThatFits(in: .horizontal) {
            strip(taken, lead: lead, stacked: true)
            strip(taken, lead: lead, stacked: false)
            leadLabel(lead)
        }
        .foregroundStyle(.secondary)
        .animation(.snappy(duration: 0.3), value: taken)
        .accessibilityHidden(true)
    }

    private func strip(_ taken: [CapturedCount], lead: Int, stacked: Bool) -> some View {
        HStack(spacing: 3) {
            ForEach(taken) { entry in
                if stacked {
                    HStack(spacing: -size * 0.43) {
                        ForEach(0..<entry.count, id: \.self) { _ in
                            silhouette(of: entry.kind)
                        }
                    }
                } else {
                    HStack(spacing: 1) {
                        silhouette(of: entry.kind)
                        if entry.count > 1 {
                            Text("\(entry.count)")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                        }
                    }
                }
            }
            leadLabel(lead)
        }
    }

    @ViewBuilder
    private func leadLabel(_ lead: Int) -> some View {
        if lead > 0 {
            Text("+\(lead)")
                .font(.footnote.weight(.semibold).monospacedDigit())
        }
    }

    /// The flat vector set, drawn as a one-color shape so it stays sharp at this size on any glass.
    private func silhouette(of kind: Piece.Kind) -> some View {
        Image(Piece(kind, color: .white, square: .a1).assetName)
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }

    /// For VoiceOver: "captured 1 knight and 2 pawns, up 2".
    static func spoken(_ taken: [CapturedCount], lead: Int) -> String {
        let pieces = taken.map { "\($0.count) \(String(describing: $0.kind))\($0.count == 1 ? "" : "s")" }
        var text = "captured " + (ListFormatter.localizedString(byJoining: pieces))
        if lead > 0 { text += ", up \(lead)" }
        return text
    }
}

/// A side's time in a quiet box that turns solid while its clock runs.
private struct ExecutiveClock: View {
    let clock: ChessClock
    let color: Piece.Color
    /// "Your clock" or "Pulse's clock", for VoiceOver.
    let owner: String
    let theme: BoardTheme

    private var isRunning: Bool { clock.running == color }

    var body: some View {
        TimelineView(.periodic(from: .now, by: isRunning ? 0.1 : 60)) { _ in
            let remaining = clock.remaining(for: color)
            let urgent = isRunning && remaining < .seconds(10)
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            Text(remaining.clockLabel)
                .font(.system(.title3, design: .themed).weight(.medium).monospacedDigit())
                .foregroundStyle(isRunning ? Color.black.opacity(0.88) : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background {
                    if isRunning {
                        shape.fill(urgent ? Color(hex: 0xFF4D6D) : Color.white.opacity(0.92))
                    } else {
                        shape.fill(Color.primary.opacity(0.05))
                            .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                    }
                }
                // Inside the timeline, so VoiceOver reads the time as it stands now.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(owner)
                .accessibilityValue(remaining.formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
        }
        .animation(.snappy(duration: 0.25), value: isRunning)
    }
}

/// The middle of the top bar: the time control in small capitals over the game's progress.
/// An untimed game shows the progress alone. The players are named on their own lines below.
struct ExecutiveMatchTitle: View {
    let match: MatchController

    @ScaledMetric(relativeTo: .caption2) private var scaledKickerSize: CGFloat = 10
    /// It stops growing where the headline's type does, so both fit the bar.
    private var kickerSize: CGFloat { min(scaledKickerSize, 13.5) }

    var body: some View {
        VStack(spacing: 1) {
            if let kicker {
                Text(kicker)
                    .font(.system(size: kickerSize, weight: .medium, design: .themed))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(headline)
                .font(.system(.subheadline, design: .themed).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .minimumScaleFactor(0.85)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// "RAPID · 15+10".
    private var kicker: String? {
        let control = match.setup.timeControl
        guard control.isTimed, let kind = control.kind else { return nil }
        return "\(kind) · \(control.rawValue)".uppercased()
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
    /// Set for a toggle: it lights in the accent while on, and VoiceOver says which way it is.
    var isOn: Bool? = nil
    let theme: BoardTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DockLabel(title: title, symbol: symbol, lit: isOn == true, theme: theme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.map { $0 ? "On" : "Off" } ?? "")
        .accessibilityAddTraits(isOn == nil ? [] : .isToggle)
        // The dock's type stops growing at large sizes; a long press shows the name big instead.
        .accessibilityShowsLargeContentViewer()
    }
}

/// What a dock control looks like: its icon with its name under it, in the accent while lit.
struct DockLabel: View {
    let title: String
    let symbol: String
    var lit = false
    let theme: BoardTheme

    @Environment(\.isEnabled) private var isEnabled

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        VStack(spacing: 4) {
            Glyph(name: symbol, size: Glyph.isGlyph(symbol) ? 25 : 24, weight: .regular)
                .frame(height: 25)
                .contentTransition(.symbolEffect(.replace))
                .shadow(color: theme.glows && lit ? accent.opacity(0.7) : .clear, radius: 6)
            Text(title)
                .font(.system(.caption2, design: .themed).weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(lit ? accent : Color.primary.opacity(0.78))
        .opacity(isEnabled ? 1 : 0.5)
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }
}

/// A small red "Check" tag at the front of the player's line while their king is in check.
struct CheckTag: View {
    let color: Color

    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 9.5

    var body: some View {
        Text("CHECK")
            .font(.system(size: size, weight: .heavy, design: .themed))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color))
            .fixedSize()
    }
}
