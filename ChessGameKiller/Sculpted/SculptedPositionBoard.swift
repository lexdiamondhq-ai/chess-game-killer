import ChessKit
import SwiftUI

/// Analysis on the real 3D board: any position (a photo's, one set up by hand, a game's), tilted
/// with the pieces standing or flat from above (the Board view setting), with Stockfish's best
/// moves as the game's hint arrows on the stone. Tap a piece and then its square, as on the flat
/// analysis board. The position has no lasting piece ids, so the scene matches each piece to the
/// one on the board before and moves it, rather than fading pieces in and out.
struct SculptedPositionBoard: View {
    let pieces: [Piece]
    let theme: BoardTheme
    var flipped = false
    /// The best move and the next best, best first.
    var hints: [MoveHint] = []
    var selected: Square?
    var targets: Set<Square> = []
    var lastMove: LastMove?
    /// Taps on squares. Nil makes the board look-only.
    var onTap: ((Square) -> Void)?
    var framing: SculptedCamera.Framing = .standing

    @State private var stage = SculptedStage()

    private var look: SculptedLook { theme.sculptedLook ?? .gilded }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let camera = SculptedCamera.fitted(aspect: Float(size.width / max(size.height, 1)), flipped: flipped, framing: framing)
            ZStack(alignment: .topLeading) {
                SculptedSceneView(stage: stage, look: look, state: state)
                    .id(look.name)
                    .frame(width: size.width, height: size.height)
                    .accessibilityHidden(true)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in tap(at: value.location) })
                    .accessibilityHidden(true)
                squareElements(camera: camera, size: size)
            }
        }
        .modifier(AspectRange(range: framing == .standing ? SculptedCamera.standingAspects : Float(framing.aspect)...Float(framing.aspect)))
    }

    /// The position, copied for the scene.
    var state: SculptedBoardState {
        var state = SculptedBoardState(
            pieces: pieces.map { PlacedPiece(id: 0, piece: $0) },
            selected: selected,
            targets: targets,
            lastMove: lastMove,
            hints: Self.sceneHints(hints),
            flipped: flipped,
            matchesPieces: true
        )
        state.framing = framing
        return state
    }

    /// The analysis lines' arrows for the scene: the best lit, the next one plain.
    static func sceneHints(_ hints: [MoveHint]) -> [SculptedHint] {
        hints.prefix(2).map { SculptedHint(from: $0.from, to: $0.to, isBest: $0.rank == 0) }
    }

    private func tap(at point: CGPoint) {
        guard let onTap, let square = stage.scene(for: look).square(at: point) else { return }
        onTap(square)
    }

    /// One element over each square's outline, read and tapped like the flat board's squares.
    private func squareElements(camera: SculptedCamera, size: CGSize) -> some View {
        ForEach(0..<64, id: \.self) { index in
            let square = Square(file: index % 8, rank: index / 8)
            let frame = camera.frame(of: square, in: size)
            Color.clear
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel(square))
                .accessibilityAddTraits(onTap == nil ? [] : .isButton)
                .accessibilityAction { onTap?(square) }
        }
        .allowsHitTesting(false)
    }

    private func accessibilityLabel(_ square: Square) -> String {
        let occupant = pieces.first { $0.square == square }
        var parts = [square.notation]
        if let occupant { parts.append(occupant.spokenName) }
        if targets.contains(square) { parts.append(occupant == nil ? "move here" : "capture") }
        if let best = hints.first, best.from == square || best.to == square { parts.append("best move") }
        return parts.joined(separator: ", ")
    }
}
