import ChessKit
import SceneKit
import SwiftUI

/// Holds one board's 3D scene, made the first time the board is drawn, and made again
/// in the new look when the player picks another.
final class SculptedStage {
    private var made: SculptedBoardScene?

    func scene(for look: SculptedLook) -> SculptedBoardScene {
        if let made, made.look.name == look.name { return made }
        let scene = SculptedBoardScene(look: look)
        made = scene
        return scene
    }
}

/// The SceneKit view inside SwiftUI. Taps are read by the SwiftUI layer laid over it.
/// Callers give it `.id(look.name)`, so a new look brings a new view.
struct SculptedSceneView: UIViewRepresentable {
    let stage: SculptedStage
    let look: SculptedLook
    let state: SculptedBoardState

    func makeUIView(context: Context) -> SculptedSceneKitView {
        let scene = stage.scene(for: look)
        scene.apply(state, animated: false)
        return scene.view
    }

    func updateUIView(_ view: SculptedSceneKitView, context: Context) {
        stage.scene(for: look).apply(state, animated: !context.transaction.disablesAnimations)
    }
}

/// The game board in real 3D: tap a piece to lift it and see its moves, tap a dot to play.
/// The same jobs as the flat `BoardView`: best-move arrows, check, promotion, the army's
/// names and glows, haptics and a VoiceOver square for every square.
struct SculptedBoardView: View {
    let match: MatchController
    let theme: BoardTheme
    /// An earlier position the player is looking back at; the pieces walk back to it.
    var browsing: Position?
    /// Called when the player taps the board while looking back.
    var endBrowsing: (() -> Void)?

    /// Width over height: the board seen at an angle is wider than it is tall.
    static let aspect: CGFloat = 1.35

    @AppStorage("haptics") private var hapticsOn = true
    @Environment(ArmyStore.self) private var army: ArmyStore?
    @State private var stage = SculptedStage()

    private var game: GameModel { match.game }
    private var flipped: Bool { match.isBoardFlipped }
    private var look: SculptedLook { theme.sculptedLook ?? .gilded }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let camera = SculptedCamera.fitted(aspect: Float(size.width / max(size.height, 1)), flipped: flipped)
            ZStack(alignment: .topLeading) {
                SculptedSceneView(stage: stage, look: look, state: boardState)
                    .id(look.name)
                    .frame(width: size.width, height: size.height)
                    .accessibilityHidden(true)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in tap(at: value.location) })
                    .accessibilityHidden(true)
                if browsing == nil {
                    squareElements(camera: camera, size: size)
                    nameTag(camera: camera, size: size)
                } else {
                    Color.clear
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel("An earlier position. Tap to go back to the game.")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { endBrowsing?() }
                }
                // A flag that falls mid-promotion puts the pawn back; the picker never outlives the game.
                if browsing == nil, let promotion = game.pendingPromotion, !match.isOver {
                    PromotionPicker(color: promotion.piece.color, theme: theme, squareSize: size.width / 8) { kind in
                        withAnimation(.snappy(duration: 0.2)) { match.promote(to: kind) }
                    }
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
                }
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .sensoryFeedback(.impact(weight: .light), trigger: game.moveCount) { _, _ in hapticsOn }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.7), trigger: game.captureEvents.last?.id) { _, new in
            hapticsOn && new != nil
        }
    }

    /// The game, copied for the scene.
    private var boardState: SculptedBoardState {
        if let browsing {
            return SculptedBoardState(pieces: browsing.pieces.map { PlacedPiece(id: 0, piece: $0) },
                                      flipped: flipped, matchesPieces: true)
        }
        return SculptedBoardState(
            pieces: game.pieces,
            selected: game.selected,
            targets: game.targets,
            lastMove: game.lastMove,
            checkedKing: game.checkedKing,
            hints: match.hints.map { SculptedHint(from: $0.from, to: $0.to, isBest: $0.rank == 0) },
            flipped: flipped,
            lastCapture: game.captureEvents.last,
            halos: halos
        )
    }

    /// The player's veterans glow: ivory or platinum by side, gold for a Legend, which breathes.
    private var halos: [Int: SculptedHalo] {
        guard let army else { return [:] }
        var result: [Int: SculptedHalo] = [:]
        for placed in game.pieces {
            guard let slot = army.slot(of: placed, in: match) else { continue }
            let rank = army.record(for: slot).rank
            guard rank >= .veteran else { continue }
            let tone: SculptedHalo.Tone = rank == .legend ? .gold : (placed.piece.color == .white ? .ivory : .platinum)
            result[placed.id] = SculptedHalo(tone: tone, breathing: rank == .legend)
        }
        return result
    }

    private func tap(at point: CGPoint) {
        if browsing != nil {
            endBrowsing?()
            return
        }
        guard let square = stage.scene(for: look).square(at: point) else { return }
        withAnimation(.snappy(duration: 0.22)) { match.tap(square) }
    }

    // MARK: VoiceOver

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
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { match.tap(square) }
        }
        .allowsHitTesting(false)
    }

    private func accessibilityLabel(_ square: Square) -> String {
        let occupant = game.piece(at: square)
        var parts = [square.notation]
        if let occupant { parts.append(occupant.spokenName) }
        if game.targets.contains(square) { parts.append(occupant == nil ? "move here" : "capture") }
        if let hint = match.hints.first(where: { $0.from == square }) {
            parts.append(hint.rank == 0 ? "best move \(hint.san)" : "second best move \(hint.san)")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Army

    /// The selected piece's name, floating above its head (below its foot on the far rank).
    @ViewBuilder
    private func nameTag(camera: SculptedCamera, size: CGSize) -> some View {
        if let army, let square = game.selected,
           let placed = game.pieces.first(where: { $0.square == square }),
           let slot = army.slot(of: placed, in: match),
           let name = army.record(for: slot).name {
            let rank = army.record(for: slot).rank
            let foot = SculptedCamera.position(of: square)
            let height = SculptedAssets.shared.height(of: placed.piece.kind) + 0.12
            let top = camera.screenPoint(foot + SIMD3(0, height + 0.16, 0), in: size)
            let below = camera.screenPoint(foot + SIMD3(0, 0, flipped ? -0.62 : 0.62), in: size)
            let y = top.y - 14 >= 14 ? top.y - 14 : below.y
            NameTagPlacement(x: top.x, y: y) {
                ArmyNameTag(name: name, rank: rank, color: rank.color(for: placed.piece, theme: theme))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A 3D board that is not for playing, such as the Settings preview: a position and arrows.
struct SculptedStillBoard: View {
    let position: Position
    var look: SculptedLook = .gilded
    var hints: [SculptedHint] = []

    @State private var stage = SculptedStage()

    var body: some View {
        SculptedSceneView(stage: stage, look: look, state: state)
            .id(look.name)
            .aspectRatio(SculptedBoardView.aspect, contentMode: .fit)
            .allowsHitTesting(false)
    }

    private var state: SculptedBoardState {
        SculptedBoardState(
            pieces: position.pieces.map { PlacedPiece(id: 0, piece: $0) },
            hints: hints,
            matchesPieces: true
        )
    }
}
