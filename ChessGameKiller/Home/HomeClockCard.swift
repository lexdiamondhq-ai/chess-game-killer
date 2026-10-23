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
    /// Without a clock the king takes the time's place.
    @ScaledMetric(relativeTo: .largeTitle) private var tallKing: CGFloat = 62

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

    private func face(_ side: Side) -> some View {
        let pieceColor = color(side)
        let lit = upNext.sideToMove == pieceColor
        let kingSize = timed ? king : min(tallKing, 96)
        return HStack(alignment: .bottom, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(side == .you ? "You" : upNext.rival.name)
                    .font(.headline)
                    .foregroundStyle(tone.ink)
                Text(detail(side))
                    .font(.subheadline)
                    .foregroundStyle(tone.ink2)
                if let time = clockTime(side) {
                    Text(time.clockLabel)
                        .font(.system(size: digits, weight: .regular, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(lit ? tone.ink : tone.ink2)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 4)
                }
                // Only the side to move carries the mark, as only one face of a clock runs.
                // The other face keeps the line's height, so the two stay level.
                HStack(spacing: 6) {
                    Circle()
                        .fill(tone.metal)
                        .frame(width: 7, height: 7)
                    Text(lit ? toMove(side) : " ")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(tone.metal)
                }
                .opacity(lit ? 1 : 0)
                .padding(.top, timed ? 0 : 6)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            PieceImage(piece: Piece(.king, color: pieceColor, square: pieceColor == .white ? .e1 : .e8), theme: pieceTheme, size: kingSize)
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

    private func colorName(_ color: Piece.Color) -> String {
        color == .white ? "White" : "Black"
    }

    /// Your side and the clock ("White · No clock", "Black · 3+2"), said once; the rival's strength.
    private func detail(_ side: Side) -> String {
        switch side {
        case .you:
            let playing = upNext.randomSide ? "Either side" : colorName(color(.you))
            return "\(playing) · \(upNext.timeControl.name)"
        case .rival:
            return "Computer · \(upNext.rival.elo)"
        }
    }

    private func clockTime(_ side: Side) -> Duration? {
        guard timed else { return nil }
        if upNext.inProgress {
            return side == .you ? upNext.yourTime : upNext.theirTime
        }
        return upNext.timeControl.initial
    }

    /// What the lit face says: the move, and whose it is.
    private func toMove(_ side: Side) -> String {
        if upNext.inProgress {
            return side == .you ? "Your move" : "Their move"
        }
        return "Moves first"
    }

    private func spoken(_ side: Side) -> String {
        let name = side == .you ? "You" : "\(upNext.rival.name), computer, rated \(upNext.level.spokenRating)"
        let playing = upNext.randomSide ? "either side" : colorName(color(side))
        var parts = [name, playing]
        if let time = clockTime(side) {
            parts.append(time.formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
        } else if side == .you {
            parts.append("no clock")
        }
        if upNext.sideToMove == color(side) { parts.append(toMove(side)) }
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
/// or to start the next game, from anywhere on the page. The ivory disc is the clock card's
/// own button, so the way to play keeps its color all the way down the page.
struct HomeClockCapsule: View {
    let upNext: HomeUpNext
    let tone: HomeTone
    let action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var disc: CGFloat = 30

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                content(withSubtitle: true)
                content(withSubtitle: false)
                playDisc
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(tone.ink)
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Capsule())
        }
        .buttonStyle(HomePressStyle())
        .homePane(Capsule(), tone: tone, weight: .bar)
        .accessibilityLabel(upNext.inProgress ? "Resume your game against \(upNext.rival.name)" : "Play \(upNext.rival.name)")
        .accessibilityValue(subtitle)
    }

    private var title: String { upNext.inProgress ? "Resume" : "Play \(upNext.rival.name)" }

    /// The game in a few words: "White · No clock", "Your move · 4:12".
    private var subtitle: String {
        if upNext.inProgress {
            let move = upNext.yourMove ? "Your move" : "Their move"
            if let time = upNext.yourTime { return "\(move) · \(time.clockLabel)" }
            return move
        }
        let side = upNext.randomSide ? "Either side" : (upNext.playerColor == .white ? "White" : "Black")
        return "\(side) · \(upNext.timeControl.name)"
    }

    private var playDisc: some View {
        Image(systemName: "play.fill")
            .font(.system(size: disc * 0.4, weight: .bold))
            .foregroundStyle(tone.onIvory)
            .offset(x: disc * 0.04)
            .frame(width: disc, height: disc)
            .background(Circle().fill(tone.ivory))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }

    private func content(withSubtitle: Bool) -> some View {
        HStack(spacing: 10) {
            playDisc
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if withSubtitle {
                    Text(subtitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(upNext.inProgress && upNext.yourMove ? tone.metal : tone.ink2)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}
