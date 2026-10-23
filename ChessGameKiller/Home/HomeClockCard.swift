import ChessKit
import SwiftUI

/// The first card on the home, at the foot of the board: a chess clock with two faces, yours
/// and your rival's, each with its king. A game under way shows the time left and whose move
/// it is, with Resume. Otherwise it shows the next game as last set up, ready to start.
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

    private enum Side { case you, rival }

    var body: some View {
        VStack(spacing: 12) {
            faces
            buttons
        }
        .padding(12)
        .homePane(RoundedRectangle(cornerRadius: 30, style: .continuous), tone: tone)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(upNext.inProgress ? "Your game" : "Next game")
        .accessibilityAction(.magicTap, primary)
    }

    private var stacked: Bool { typeSize.isAccessibilitySize }

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
        return HStack(alignment: .bottom, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(side == .you ? "You" : upNext.rival.name)
                    .font(.headline)
                    .foregroundStyle(tone.ink)
                Text(detail(side))
                    .font(.subheadline)
                    .foregroundStyle(tone.ink2)
                Text(time(side))
                    .font(.system(size: digits, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(lit ? tone.ink : tone.ink2)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 6)
                HStack(spacing: 6) {
                    if lit {
                        Circle()
                            .fill(tone.metal)
                            .frame(width: 7, height: 7)
                    }
                    Text(footer(side))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(lit ? tone.metal : tone.ink2)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            PieceImage(piece: Piece(.king, color: pieceColor, square: pieceColor == .white ? .e1 : .e8), theme: pieceTheme, size: king)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                .accessibilityHidden(true)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .homePane(RoundedRectangle(cornerRadius: 20, style: .continuous), tone: tone, weight: .well(lit: lit))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(side))
    }

    private func colorName(_ color: Piece.Color) -> String {
        color == .white ? "White" : "Black"
    }

    private func detail(_ side: Side) -> String {
        switch side {
        case .you:
            return upNext.randomSide ? "Either side" : colorName(color(.you))
        case .rival:
            let rival = upNext.rival
            return upNext.randomSide ? rival.elo : "\(rival.elo) · \(colorName(color(.rival)))"
        }
    }

    private func clockTime(_ side: Side) -> Duration? {
        guard upNext.timeControl.isTimed else { return nil }
        if upNext.inProgress {
            return side == .you ? upNext.yourTime : upNext.theirTime
        }
        return upNext.timeControl.initial
    }

    /// "4:12", or "∞" without a clock.
    private func time(_ side: Side) -> String {
        clockTime(side)?.clockLabel ?? "∞"
    }

    private func footer(_ side: Side) -> String {
        if upNext.inProgress {
            switch side {
            case .you: return upNext.yourMove ? "Your move" : "Their move"
            case .rival: return "Move \(upNext.moveNumber)"
            }
        }
        switch side {
        case .you:
            if upNext.randomSide { return "Random side" }
            return upNext.playerColor == .white ? "Moves first" : "Moves second"
        case .rival:
            return upNext.level.tagline
        }
    }

    private func spoken(_ side: Side) -> String {
        let name = side == .you ? "You" : "\(upNext.rival.name), rated \(upNext.level.spokenRating)"
        let clock = clockTime(side).map { $0.formatted(.units(allowed: [.minutes, .seconds], width: .wide)) } ?? "no clock"
        let playing = upNext.randomSide ? "either side" : colorName(color(side))
        return "\(name), \(playing), \(clock), \(footer(side))"
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
/// or to start the next game, from anywhere on the page.
struct HomeClockCapsule: View {
    let upNext: HomeUpNext
    let tone: HomeTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                content(withTimes: true)
                content(withTimes: false)
                Glyph(name: Glyphs.play, size: 24)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(tone.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Capsule())
        }
        .buttonStyle(HomePressStyle())
        .homePane(Capsule(), tone: tone, weight: .bar)
        .accessibilityLabel(upNext.inProgress ? "Resume your game against \(upNext.rival.name)" : "Play \(upNext.rival.name)")
    }

    private var title: String { upNext.inProgress ? "Resume" : "Play \(upNext.rival.name)" }

    private var subtitle: String {
        upNext.inProgress ? (upNext.yourMove ? "Your move" : "Their move") : upNext.level.tagline
    }

    private func content(withTimes: Bool) -> some View {
        HStack(spacing: 10) {
            if withTimes, upNext.inProgress, let you = upNext.yourTime, let them = upNext.theirTime {
                HStack(spacing: 6) {
                    Text(you.clockLabel)
                        .foregroundStyle(upNext.yourMove ? tone.ink : tone.ink2)
                    Text(them.clockLabel)
                        .foregroundStyle(upNext.yourMove ? tone.ink2 : tone.ink)
                }
                .font(.subheadline.weight(.medium).monospacedDigit())
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .background(tone.canvas.opacity(0.45), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(upNext.inProgress && upNext.yourMove ? tone.metal : tone.ink2)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}
