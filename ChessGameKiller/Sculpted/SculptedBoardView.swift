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

    @AppStorage(BoardTheme.coordinatesKey) private var showsCoordinates = true

    /// The state with the Coordinates setting, which every 3D board follows.
    private var shown: SculptedBoardState {
        var shown = state
        shown.showsCoordinates = showsCoordinates
        return shown
    }

    func makeUIView(context: Context) -> SculptedSceneKitView {
        let scene = stage.scene(for: look)
        scene.apply(shown, animated: false)
        return scene.view
    }

    func updateUIView(_ view: SculptedSceneKitView, context: Context) {
        stage.scene(for: look).apply(shown, animated: !context.transaction.disablesAnimations)
    }
}

/// The game board in real 3D: tap a piece to lift it and see its moves, tap a dot to play.
/// The same jobs as the flat `BoardView`: the coach's hints, check, promotion, the army's
/// glows, haptics and a VoiceOver square for every square.
struct SculptedBoardView: View {
    let match: MatchController
    let theme: BoardTheme
    /// An earlier position the player is looking back at; the pieces walk back to it.
    var browsing: Position?
    /// Called when the player taps the board while looking back.
    var endBrowsing: (() -> Void)?
    /// Ghost Vision, when the player can hold the board to see ahead.
    var vision: GhostVision?
    /// Seen from the player's chair, or from above with each piece lying in its square (Big Board).
    var framing: SculptedCamera.Framing = .standing

    /// Width over height: the board seen at an angle is wider than it is tall.
    static let aspect: CGFloat = SculptedCamera.Framing.standing.aspect

    @AppStorage("haptics") private var hapticsOn = true
    @Environment(ArmyStore.self) private var army: ArmyStore?
    @AppStorage(Heirloom.settingKey) private var showsHeirloom = true
    @State private var stage = SculptedStage()
    /// The latest move's feel, set as its piece touches down, so the phone taps then.
    @State private var touchdown: Touchdown?
    /// Bumps once the king has fallen in each game the player wins, for the haptic.
    @State private var wins = 0

    /// A move's feel, felt as its piece touches down.
    private struct Touchdown: Equatable {
        let move: Int
        let feel: MoveFeel
    }

    private var game: GameModel { match.game }
    private var flipped: Bool { match.isBoardFlipped }
    private var look: SculptedLook { theme.sculptedLook ?? .gilded }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let camera = SculptedCamera.fitted(aspect: Float(size.width / max(size.height, 1)), flipped: flipped, framing: framing)
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
                    // Called once the checking piece has landed, with the red under the king.
                    CheckCalloutLayer(game: game, color: theme.check, landing: { game in
                        game.lastPlayed.map { SculptedBoardScene.landingDelay(for: $0, in: game) } ?? 0
                    }, anchor: { square in
                        calloutPoint(over: square, camera: camera, size: size)
                    })
                    // Each game starts with a fresh layer: the move count runs on across games.
                    .id(match.gameNumber)
                    .frame(width: size.width, height: size.height)
                    // The fallen king says it all: no "Checkmate" over it.
                    .opacity(finale == nil ? 1 : 0)
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
                    PromotionPicker(
                        color: promotion.piece.color, theme: theme, squareSize: min(size.width / 8, size.height / 6),
                        cancel: { withAnimation(.snappy(duration: 0.2)) { match.cancelPromotion() } }
                    ) { kind in
                        withAnimation(.snappy(duration: 0.2)) { match.promote(to: kind) }
                    }
                    .frame(width: size.width, height: size.height)
                    .transition(.opacity)
                }
            }
        }
        .aspectRatio(framing.aspect, contentMode: .fit)
        // One tap as each move's piece touches down: firmer for a capture, a heavy thud as a
        // rook or queen falls and the board shakes, a sharp knock for a check against the player.
        .sensoryFeedback(trigger: touchdown) { _, new in
            guard hapticsOn, let new else { return nil }
            return new.feel.feedback(heavy: true)
        }
        .sensoryFeedback(.selection, trigger: game.selected) { _, new in hapticsOn && new != nil }
        .sensoryFeedback(.success, trigger: wins) { _, _ in hapticsOn }
        .onChange(of: game.moveCount) { _, count in
            guard let played = game.lastPlayed else { return }
            let feel = MoveFeel(of: game)
            let delay = SculptedBoardScene.landingDelay(for: played, in: game)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                touchdown = Touchdown(move: count, feel: feel)
            }
        }
        .onChange(of: match.winner) { _, winner in
            guard let winner, game.humanColors.contains(winner) else { return }
            // Once the losing king has fallen and settled.
            var delay = SculptedBoardScene.finaleDelay(afterLanding: 0)
            if game.isCheckmate, let played = game.lastPlayed {
                delay = SculptedBoardScene.finaleDelay(for: played, in: game)
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                wins += 1
            }
        }
    }

    /// Once the game is decided on the board, the clock or by resignation: the losing king.
    private var finale: SculptedFinale? {
        guard browsing == nil, match.isOver, let winner = match.winner,
              let king = game.pieces.first(where: { $0.piece.kind == .king && $0.piece.color == winner.opposite })
        else { return nil }
        return SculptedFinale(kingID: king.id, square: king.square)
    }

    /// The game, copied for the scene.
    private var boardState: SculptedBoardState {
        if let browsing {
            var state = SculptedBoardState(pieces: browsing.pieces.map { PlacedPiece(id: 0, piece: $0) },
                                           flipped: flipped, matchesPieces: true)
            state.framing = framing
            return state
        }
        var state = SculptedBoardState(
            pieces: game.pieces,
            selected: game.selected,
            targets: game.targets,
            lastMove: game.lastMove,
            checkedKing: game.checkedKing,
            // Only the best move is lit: one thing to look at.
            hints: match.bestHint.map { [SculptedHint(from: $0.from, to: $0.to, isBest: true)] } ?? [],
            flipped: flipped,
            lastCapture: game.captureEvents.last,
            halos: halos,
            heirlooms: heirlooms,
            finale: finale,
            ghosts: ghosts
        )
        state.framing = framing
        return state
    }

    /// Ghost Vision's steps while the player holds the board.
    private var ghosts: [SculptedGhostStep] {
        guard let vision, vision.isHolding, let line = match.ghostLine else { return [] }
        let focus: Int = vision.shownFocus(steps: line.steps.count)
        return line.steps.filter { $0.index <= focus }.map { step in
            SculptedGhostStep(moves: step.moves, captured: step.captured?.square,
                              opacity: Float(GhostLine.opacity(of: step.index, focus: focus)))
        }
    }

    /// Each army piece's history on the piece, when the player keeps "Piece history" on.
    private var heirlooms: [Int: Heirloom] {
        guard showsHeirloom, let army else { return [:] }
        var result: [Int: Heirloom] = [:]
        for placed in game.pieces {
            guard let slot = army.slot(of: placed, in: match) else { continue }
            let heirloom = army.heirloom(for: slot)
            if !heirloom.isEmpty { result[placed.id] = heirloom }
        }
        return result
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
        if vision?.swallowsTap == true { return }
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
        if let best = match.bestHint, best.from == square {
            parts.append("hint: \(HintWords.phrase(for: best, in: game))")
        }
        return parts.joined(separator: ", ")
    }

    /// Where the check callout floats: over the king's cross, or in front of its foot
    /// when the far edge of the view is too close.
    private func calloutPoint(over square: Square, camera: SculptedCamera, size: CGSize) -> CGPoint {
        let foot = SculptedCamera.position(of: square)
        let height = framing.lying ? 0.5 : SculptedAssets.shared.height(of: .king) + 0.2
        let top = camera.screenPoint(foot + SIMD3(0, height + 0.16, 0), in: size)
        let below = camera.screenPoint(foot + SIMD3(0, 0, flipped ? -0.62 : 0.62), in: size)
        return top.y - 14 >= 14 ? CGPoint(x: top.x, y: top.y - 12) : below
    }
}

/// A 3D board that is not for playing, such as the Settings preview: a position, a piece
/// shown as tapped with its moves, and the coach's hints.
struct SculptedStillBoard: View {
    let position: Position
    var look: SculptedLook = .gilded
    var hints: [SculptedHint] = []
    var selected: Square?
    var targets: Set<Square> = []

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
            selected: selected,
            targets: targets,
            hints: hints,
            matchesPieces: true
        )
    }
}
