import ChessKit
import SwiftUI

/// A puzzle's board in real 3D: the game's own board, tilted with the pieces standing or flat
/// from above (the Board view setting), with the coach's glowing squares and arrows lying on
/// the stone. Tap a piece and then its square, as on the flat training board. Drills put no
/// labels on the board, so it has none.
struct SculptedTrainingBoard: View {
    let game: GameModel
    let theme: BoardTheme
    var flipped = false
    var arrows: [BoardArrow] = []
    var marks: [SquareMark] = []
    /// Taps on squares. Nil makes the board look-only.
    var onTap: ((Square) -> Void)?
    /// Seen from the player's chair, or from above with the flat pieces.
    var framing: SculptedCamera.Framing = .standing

    @AppStorage("haptics") private var hapticsOn = true
    @State private var stage = SculptedStage()
    /// The latest move's feel, set as its piece touches down, so the phone taps then.
    @State private var touchdown: Touchdown?
    @State private var landings = 0

    private struct Touchdown: Equatable {
        let landing: Int
        let feel: MoveFeel
    }

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
        // Flat from above it keeps its one shape; standing it may be taller, and the camera tips higher to fill it.
        .modifier(AspectRange(range: framing == .standing ? SculptedCamera.standingAspects : Float(framing.aspect)...Float(framing.aspect)))
        // One tap as each move's piece touches down, as on the game's 3D board.
        .sensoryFeedback(trigger: touchdown) { _, new in
            guard hapticsOn, let new else { return nil }
            return new.feel.feedback(heavy: true)
        }
        .onChange(of: game.moveCount) { _, _ in
            guard let played = game.lastPlayed else { return }
            let feel = MoveFeel(of: game)
            let delay = SculptedBoardScene.landingDelay(for: played, in: game)
            landings += 1
            let landing = landings
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                touchdown = Touchdown(landing: landing, feel: feel)
            }
        }
    }

    /// The puzzle, copied for the scene.
    private var state: SculptedBoardState {
        var state = SculptedBoardState()
        state.pieces = game.pieces
        state.selected = game.selected
        state.targets = game.targets
        state.lastMove = game.lastMove
        state.checkedKing = game.checkedKing
        state.flipped = flipped
        state.lastCapture = game.captureEvents.last
        state.framing = framing
        state.coachMarks = Self.coachMarks(marks, theme: theme)
        state.coachArrows = Self.coachArrows(arrows, theme: theme)
        return state
    }

    /// The coach's squares in the colors the flat board gives them on this look.
    static func coachMarks(_ marks: [SquareMark], theme: BoardTheme) -> [SculptedCoachMark] {
        marks.compactMap { mark in
            square(named: mark.square).map { SculptedCoachMark(square: $0, color: (mark.color ?? .yellow).hex(on: theme)) }
        }
    }

    /// The coach's arrows in the colors the flat board gives them on this look.
    static func coachArrows(_ arrows: [BoardArrow], theme: BoardTheme) -> [SculptedCoachArrow] {
        arrows.compactMap { arrow in
            guard let from = square(named: arrow.from), let to = square(named: arrow.to) else { return nil }
            return SculptedCoachArrow(from: from, to: to, color: (arrow.color ?? .green).hex(on: theme), dashed: arrow.dashed ?? false)
        }
    }

    /// A square from its name, or nil if the name isn't one.
    private static func square(named name: String) -> Square? {
        let files: ClosedRange<Character> = "a"..."h"
        let ranks: ClosedRange<Character> = "1"..."8"
        guard name.count == 2, let file = name.first, let rank = name.last,
              files.contains(file), ranks.contains(rank) else { return nil }
        return Square(name)
    }

    private func tap(at point: CGPoint) {
        guard let onTap, let square = stage.scene(for: look).square(at: point) else { return }
        withAnimation(.snappy(duration: 0.22)) { onTap(square) }
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
                .accessibilityAddTraits(onTap == nil ? [] : .isButton)
                .accessibilityAction {
                    guard let onTap else { return }
                    withAnimation(.snappy(duration: 0.22)) { onTap(square) }
                }
        }
        .allowsHitTesting(false)
    }

    private func accessibilityLabel(_ square: Square) -> String {
        let occupant = game.piece(at: square)
        var parts = [square.notation]
        if let occupant { parts.append(occupant.spokenName) }
        if game.targets.contains(square) { parts.append(occupant == nil ? "move here" : "capture") }
        if marks.contains(where: { $0.square == square.notation }) { parts.append("highlighted") }
        return parts.joined(separator: ", ")
    }
}
