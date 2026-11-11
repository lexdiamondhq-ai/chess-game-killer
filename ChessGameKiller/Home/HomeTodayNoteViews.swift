import SwiftUI
import UIKit

/// The large card For today opens with (Alex, 2026-11-09: "For Today should be todays move";
/// "still have the larger card view"): a position in a gold frame, small caps, a serif title, a
/// line, and one button. It holds Today's Move, and your games under way swipe in before it
/// (Alex, 2026-11-10). A tap anywhere opens it.
struct HomeAuroraTodayCard: View {
    let eyebrow: String
    let fen: String?
    let flipped: Bool
    let title: String
    let detail: String
    let button: String
    let symbol: String
    /// Your move: the board wears a fine gold rim.
    var lit = false
    let palette: HomeAuroraPalette
    let open: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        Button(action: open) {
            HStack(spacing: 14) {
                frame(side: 112)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(palette.gold)
                        .lineLimit(1)
                    Text(title)
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.ink2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    pill(button, symbol: symbol)
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
            .contentShape(shape)
        }
        .buttonStyle(HomeStagePress())
        .accessibilityElement(children: .combine)
        .accessibilityHint(button)
    }

    private func frame(side: CGFloat) -> some View {
        let pad: CGFloat = side * 0.055
        return HomeAuroraBoard(fen: fen, flipped: flipped, lit: lit)
            .frame(width: side - 2 * pad, height: side - 2 * pad)
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
    }
}

/// Your finest move of the week as one of today's rows, the size of Puzzles: the framed move at
/// the right. A tap replays it; a press and hold shares the picture.
struct HomeAuroraFinestRow: View {
    let finest: HomeFinestMove
    let palette: HomeAuroraPalette
    var tile: Bool = false
    let replay: () -> Void

    @State private var picture: Image?

    var body: some View {
        HomeAuroraRow(eyebrow: "Your finest move", title: finest.move, detail: who,
                      accent: palette.gold, palette: palette, tile: tile, action: replay) {
            HomeFinestMoveFrame(finest: finest, side: tile ? 56 : 64)
        }
        .accessibilityHint("Replays the game at this move")
        .contextMenu {
            Button(action: replay) { Label("Replay", systemImage: "play.fill") }
            if let picture {
                ShareLink(item: picture, preview: SharePreview("My finest move: \(finest.move)", image: picture)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task(id: finest.gameID.uuidString + finest.uci) { picture = render() }
    }

    /// The row has one line: who it was against and when ("Against the Hunter, yesterday.").
    private var who: String {
        guard let end = finest.detail.range(of: ". ") else { return finest.detail }
        return String(finest.detail[..<end.lowerBound]) + "."
    }

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
