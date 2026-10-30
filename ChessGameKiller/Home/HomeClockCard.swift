import ChessKit
import SwiftUI

/// The first card on the home, at the foot of the board: a chess clock with two faces, yours
/// and your rival's, each with its king. A game under way shows the time left and whose move
/// it is, with Resume. Otherwise it shows the next game as last set up, ready to start.
/// Without a clock the faces show no time at all, just the two sides and their kings.
struct HomeClockCard: View {
    let upNext: HomeUpNext
    let tone: HomeTone
    /// The board look whose kings stand on the faces.
    let pieceTheme: BoardTheme
    let primary: () -> Void
    let secondary: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var digits: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var king: CGFloat = 44
    /// Without a clock the king stands a little taller, in the time's place.
    @ScaledMetric(relativeTo: .largeTitle) private var tallKing: CGFloat = 52

    private enum Side { case you, rival }

    var body: some View {
        VStack(spacing: 12) {
            faces
            buttons
        }
        .padding(HomeMetrics.inset)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous), tone: tone)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(upNext.inProgress ? "Your game" : "Next game")
        .accessibilityAction(.magicTap, primary)
    }

    private var stacked: Bool { typeSize.isAccessibilitySize }
    private var timed: Bool { upNext.timeControl.isTimed }

    private var faces: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            face(.you)
            face(.rival)
        }
    }

    private func color(_ side: Side) -> Piece.Color {
        side == .you ? upNext.playerColor : upNext.playerColor.opposite
    }

    /// Only the face of the side to move runs, as on a real clock; before a game neither does.
    private func isLit(_ side: Side) -> Bool {
        upNext.inProgress && upNext.sideToMove == color(side)
    }

    /// The clock's rule, said once on your face before a game: "No clock", "+2s per move".
    private var clockRule: String? {
        guard !upNext.inProgress else { return nil }
        guard timed else { return "No clock" }
        let increment = upNext.timeControl.increment.components.seconds
        return increment > 0 ? "+\(increment)s per move" : nil
    }

    /// The faces keep a line for whose move it is, or for the clock's rule, when either has one.
    private var hasFootLine: Bool { upNext.inProgress || clockRule != nil }

    private func face(_ side: Side) -> some View {
        let pieceColor = color(side)
        let lit = isLit(side)
        return HStack(alignment: .bottom, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(side == .you ? "You" : upNext.rival.name)
                    .font(.app(.headline))
                    .foregroundStyle(tone.ink)
                Text(detail(side))
                    .font(.app(.subheadline))
                    .foregroundStyle(tone.ink2)
                if let time = clockTime(side) {
                    Text(time.clockLabel)
                        .font(.app(size: digits, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(!upNext.inProgress || lit ? tone.ink : tone.ink2)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 4)
                }
                if hasFootLine {
                    footLine(side, lit: lit)
                        .padding(.top, timed ? 0 : 6)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            PieceImage(piece: Piece(.king, color: pieceColor, square: pieceColor == .white ? .e1 : .e8), theme: pieceTheme,
                       size: min(timed ? king : tallKing, 60))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .accessibilityHidden(true)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .homePane(RoundedRectangle(cornerRadius: HomeMetrics.innerRadius, style: .continuous), tone: tone, weight: .well(lit: lit))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(side))
    }

    /// The last line of a face: the mark of the side to move, or the clock's rule on yours.
    /// A face with neither keeps the line's height, so the two faces stay level.
    @ViewBuilder
    private func footLine(_ side: Side, lit: Bool) -> some View {
        if lit {
            HStack(spacing: 6) {
                Circle()
                    .fill(tone.metal)
                    .frame(width: 7, height: 7)
                Text(side == .you ? "Your move" : "Their move")
                    .font(.app(.footnote, weight: .medium))
                    .foregroundStyle(tone.metal)
            }
        } else if side == .you, let clockRule {
            Text(clockRule)
                .font(.app(.footnote))
                .foregroundStyle(tone.ink3)
        } else {
            Text(verbatim: " ")
                .font(.app(.footnote, weight: .medium))
                .accessibilityHidden(true)
        }
    }

    private func colorName(_ color: Piece.Color) -> String {
        color == .white ? "White" : "Black"
    }

    /// Your side; the rival's strength.
    private func detail(_ side: Side) -> String {
        switch side {
        case .you: return upNext.randomSide ? "Either side" : colorName(color(.you))
        case .rival: return upNext.rival.elo
        }
    }

    private func clockTime(_ side: Side) -> Duration? {
        guard timed else { return nil }
        if upNext.inProgress {
            return side == .you ? upNext.yourTime : upNext.theirTime
        }
        return upNext.timeControl.initial
    }

    private func spoken(_ side: Side) -> String {
        let name = side == .you ? "You" : "\(upNext.rival.name), computer, rated \(upNext.level.spokenRating)"
        let playing = upNext.randomSide ? "either side" : colorName(color(side))
        var parts = [name, playing]
        if let time = clockTime(side) {
            parts.append(time.formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
        }
        if side == .you, !upNext.inProgress {
            if !timed {
                parts.append("no clock")
            } else if upNext.timeControl.increment > .zero {
                let back = upNext.timeControl.increment.formatted(.units(allowed: [.seconds], width: .wide))
                parts.append("\(back) back per move")
            }
        }
        if isLit(side) { parts.append(side == .you ? "your move" : "their move") }
        return parts.joined(separator: ", ")
    }

    /// What Voice Control answers to for the main button.
    private var inputLabels: [String] {
        upNext.inProgress ? ["Resume"] : ["Play", "Play \(upNext.rival.name)"]
    }

    private var buttons: some View {
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button(action: primary) {
                Text(upNext.inProgress ? "Resume" : "Play \(upNext.rival.name)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HomeIvoryButtonStyle(tone: tone))
            .accessibilityInputLabels(inputLabels)
            Button(action: secondary) {
                Text(upNext.inProgress ? "New game" : "Change")
                    .frame(maxWidth: stacked ? .infinity : nil)
            }
            .buttonStyle(HomeGlassButtonStyle(tone: tone))
            .accessibilityHint(upNext.inProgress ? "Set up another game" : "Pick another rival, side or clock")
        }
    }
}

/// The clock card, folded into the dock once the card has scrolled away: one tap to resume
/// or to start the next game, from anywhere on the page. It is the card's own ivory button,
/// so the way to play looks the same all the way down the page.
struct HomeClockCapsule: View {
    let upNext: HomeUpNext
    let tone: HomeTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The longest label that fits beside the dock, down to the play mark alone.
            ViewThatFits(in: .horizontal) {
                label(title, subtitle)
                label(title, shortSubtitle)
                label(title, nil)
                label(shortTitle, shortSubtitle)
                label(shortTitle, nil)
                Image(systemName: "play.fill")
                    .font(.app(.body, weight: .bold))
            }
            .foregroundStyle(tone.onIvory)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background { HomeIvoryFill(tone: tone) }
            .contentShape(Capsule())
        }
        .buttonStyle(HomePressStyle())
        .accessibilityLabel(upNext.inProgress ? "Resume your game against \(upNext.rival.name)" : "Play \(upNext.rival.name)")
        .accessibilityValue(subtitle)
        .accessibilityInputLabels(inputLabels)
    }

    private var inputLabels: [String] {
        upNext.inProgress ? ["Resume"] : ["Play", "Play \(upNext.rival.name)"]
    }

    private var title: String { upNext.inProgress ? "Resume" : "Play \(upNext.rival.name)" }
    private var shortTitle: String { upNext.inProgress ? "Resume" : "Play" }

    private var side: String {
        upNext.randomSide ? "Either side" : (upNext.playerColor == .white ? "White" : "Black")
    }

    /// The game in a few words: "White · No clock", "Your move · 4:12".
    private var subtitle: String {
        if upNext.inProgress {
            if let time = upNext.yourTime { return "\(shortSubtitle) · \(time.clockLabel)" }
            return shortSubtitle
        }
        return "\(side) · \(upNext.timeControl.name)"
    }

    /// Fewer words for a narrow capsule: whose move it is, or your side.
    private var shortSubtitle: String {
        upNext.inProgress ? (upNext.yourMove ? "Your move" : "Their move") : side
    }

    private func label(_ title: String, _ subtitle: String?) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.app(.caption).monospacedDigit())
                    .opacity(0.68)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}
