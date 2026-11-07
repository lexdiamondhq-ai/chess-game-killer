import SwiftUI
import UIKit

/// Leo's note at the top of Today: the greeting in small teal caps, his line in serif italic, and
/// what in the games it comes from. "Hear Leo" shows once the line is recorded in his voice; the
/// home music rests while he talks.
struct HomeAuroraLeoNote: View {
    let note: HomeLeoNote
    let palette: HomeAuroraPalette

    @State private var speaker = LeoSpeaker()
    @State private var speaking = false

    private var recorded: Bool { CoachVoice.hasRecording(for: note.line) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(HomeAuroraPalette.tealTile)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Glyph(name: Glyphs.coach, size: 13, weight: .bold)
                            .foregroundStyle(Color.white)
                    }
                    .accessibilityHidden(true)
                Text(note.greeting.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(palette.teal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(note.line)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let evidence = note.evidence {
                Text(evidence)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if recorded {
                Button(action: hear) {
                    HStack(spacing: 7) {
                        Image(systemName: speaking ? "stop.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(speaking ? "Stop" : "Hear Leo")
                            .font(.system(size: 12.5, weight: .bold))
                    }
                    .foregroundStyle(palette.teal)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(palette.teal.opacity(0.14)))
                }
                .buttonStyle(HomeStagePress())
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(LinearGradient(colors: [palette.teal.opacity(palette.dark ? 0.13 : 0.1),
                                                       palette.teal.opacity(palette.dark ? 0.03 : 0.02)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)))
        .background(shape.fill(palette.card.opacity(palette.dark ? 0 : 0.7)))
        .overlay(shape.strokeBorder(palette.teal.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach Leo. \(note.line) \(note.evidence ?? "")")
        .onDisappear { if speaking { speaker.stop() } }
    }

    private func hear() {
        if speaking {
            speaker.stop()
            return
        }
        speaking = true
        HomeMusic.shared.setCovered(true)
        Task { @MainActor in
            await speaker.say(note.line)
            speaking = false
            HomeMusic.shared.setCovered(false)
        }
    }
}

/// The player's finest move of the week, hung in a gold frame: the position before it with the
/// move as a Dusk Blue arrow, the move in serif, against whom and when, and Replay and Share.
struct HomeAuroraFinestMove: View {
    let finest: HomeFinestMove
    let palette: HomeAuroraPalette
    let replay: () -> Void

    @State private var picture: Image?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        HStack(spacing: 14) {
            HomeFinestMoveFrame(finest: finest, side: 112)
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR FINEST MOVE THIS WEEK")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(palette.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(finest.move)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(finest.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(action: replay) { pill("Replay", symbol: "play.fill") }
                        .buttonStyle(HomeStagePress())
                    if let picture {
                        ShareLink(item: picture, preview: SharePreview("My finest move: \(finest.move)", image: picture)) {
                            pill("Share", symbol: "square.and.arrow.up")
                        }
                        .buttonStyle(HomeStagePress())
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(shape.fill(palette.card))
        .background(alignment: .topLeading) {
            // A warm gold light from the frame's corner.
            RadialGradient(colors: [palette.gold.opacity(palette.dark ? 0.18 : 0.14), palette.gold.opacity(0)],
                           center: .topLeading, startRadius: 0, endRadius: 220)
                .clipShape(shape)
                .allowsHitTesting(false)
        }
        .overlay(shape.strokeBorder(palette.gold.opacity(0.32), lineWidth: 1))
        .task(id: finest.gameID.uuidString + finest.uci) { picture = render() }
    }

    private func pill(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(palette.gold)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .overlay(Capsule().strokeBorder(palette.gold.opacity(0.45), lineWidth: 1))
        .contentShape(Capsule())
    }

    /// The picture to share: the framed move on the dark room, with the move and the app's name.
    @MainActor
    private func render() -> Image? {
        let renderer = ImageRenderer(content: HomeFinestMoveCard(finest: finest))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// The board in its gold frame, the move drawn on it.
struct HomeFinestMoveFrame: View {
    let finest: HomeFinestMove
    let side: CGFloat

    var body: some View {
        let pad: CGFloat = side * 0.055
        let board: CGFloat = side - 2 * pad
        HomeAuroraBoard(fen: finest.fen, flipped: finest.flipped, lit: false)
            .frame(width: board, height: board)
            .overlay { arrow(side: board) }
            .padding(pad)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: Color(hex: 0xF3D99A), location: 0),
                                                 .init(color: Color(hex: 0x9C6B2C), location: 0.45),
                                                 .init(color: Color(hex: 0xE9C47C), location: 0.7),
                                                 .init(color: Color(hex: 0x7E5520), location: 1)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func arrow(side: CGFloat) -> some View {
        if let squares = finest.squares {
            // The same geometry as HomeAuroraBoard: a thin frame round eight squares.
            let margin: CGFloat = side * 0.046
            let square: CGFloat = (side - 2 * margin) / 8
            let center = { (file: Int, rank: Int) -> CGPoint in
                let column: Int = finest.flipped ? 7 - file : file
                let row: Int = finest.flipped ? rank : 7 - rank
                return CGPoint(x: margin + (CGFloat(column) + 0.5) * square, y: margin + (CGFloat(row) + 0.5) * square)
            }
            MoveArrow(from: center(squares.from.file, squares.from.rank), to: center(squares.to.file, squares.to.rank),
                      squareSize: square, isBest: true, color: Color(hex: ArrowColors.best), glow: nil)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
        }
    }
}

/// The shared picture: a square card in the dark room.
struct HomeFinestMoveCard: View {
    let finest: HomeFinestMove

    var body: some View {
        let palette = HomeAuroraPalette(dark: true)
        VStack(spacing: 18) {
            Text("MY FINEST MOVE THIS WEEK")
                .font(.system(size: 13, weight: .bold))
                .tracking(2)
                .foregroundStyle(palette.gold)
            HomeFinestMoveFrame(finest: finest, side: 300)
            Text(finest.move)
                .font(.system(size: 40, weight: .regular, design: .serif))
                .foregroundStyle(palette.ink)
            Text(finest.detail)
                .font(.system(size: 15))
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            (Text("Beauty ") + Text("of").italic().foregroundColor(palette.gold) + Text(" Chess"))
                .font(.system(size: 18, weight: .medium, design: .serif))
                .foregroundStyle(palette.ink.opacity(0.8))
                .padding(.top, 4)
        }
        .padding(36)
        .frame(width: 420)
        .background(
            ZStack {
                palette.bg
                RadialGradient(colors: [palette.violet.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: 360)
                RadialGradient(colors: [palette.rose.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 320)
                RadialGradient(colors: [palette.gold.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 300)
            }
        )
        .environment(\.colorScheme, .dark)
    }
}
