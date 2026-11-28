import SceneKit
import SwiftUI
import UIKit
import ChessKit

/// One piece set on show in Settings > Pieces (Alex, 2026-11-27: "make these boxes bigger so you
/// just see one at a time and you swipe through to select"; pick A, slowly turning, the whole
/// family). The six pieces of each side stand back to back on a round of the board's own stone,
/// which turns slowly so the light side and the dark side come round in turn.
final class PieceSetShowcaseScene {
    /// The order along each row, seen from the front: the tall pair in the middle.
    static let family: [Piece.Kind] = [.rook, .knight, .queen, .king, .bishop, .pawn]
    /// One full turn, in seconds: slow enough to read as a display, not a spin.
    static let turnTime: TimeInterval = 26

    let view: SCNView
    let look: SculptedLook
    private let scene = SCNScene()
    private let turntable = SCNNode()

    init(look: SculptedLook, assets: SculptedAssets = .shared) {
        self.look = look
        view = SCNView(frame: CGRect(x: 0, y: 0, width: 300, height: 300), options: nil)
        view.scene = scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isJitteringEnabled = false
        view.antialiasingMode = PowerPolicy.systemConstrained() ? .multisampling2X : .multisampling4X
        view.preferredFramesPerSecond = 30
        // Swipes go to the carousel around it.
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.autoenablesDefaultLighting = false

        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = assets.environment(look)
        scene.lightingEnvironment.intensity = look.environment
        scene.rootNode.addChildNode(turntable)

        buildCamera()
        buildLights()
        buildStand(assets)
        buildPieces(assets)
        turntable.simdOrientation = simd_quatf(angle: -0.35, axis: SculptedCamera.up)
        turntable.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: Self.turnTime)), forKey: "turn")
        setTurning(false)
    }

    /// Only the set in the middle turns; the ones peeking in at the sides hold still and draw nothing new.
    func setTurning(_ turning: Bool) {
        scene.isPaused = !turning
        view.isPlaying = turning
    }

    /// The picture as it is now, for tests.
    func snapshot() -> UIImage { view.snapshot() }

    private static let radius: Float = 2.35
    private static let spacing: Float = 0.74
    private static let rowOffset: Float = 0.5

    private func buildCamera() {
        let lens = SCNCamera()
        lens.fieldOfView = 36
        lens.projectionDirection = .horizontal
        lens.zNear = 1
        lens.zFar = 60
        lens.wantsHDR = false
        let node = SCNNode()
        node.camera = lens
        let elevation: Float = 20 * .pi / 180
        let distance: Float = 8
        let target = SIMD3<Float>(0, 0.6, 0)
        node.simdPosition = target + distance * SIMD3(0, sin(elevation), cos(elevation))
        node.simdLook(at: target, up: SculptedCamera.up, localFront: SCNNode.simdLocalFront)
        scene.rootNode.addChildNode(node)
        view.pointOfView = node
    }

    /// The board's own studio light, fixed while the pieces turn under it.
    private func buildLights() {
        let key = SCNLight()
        if let spot = look.spot {
            key.type = .spot
            key.spotInnerAngle = spot.inner
            key.spotOuterAngle = spot.outer
        } else {
            key.type = .directional
        }
        key.intensity = look.key
        key.color = look.keyColor
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowSampleCount = 16
        key.shadowRadius = 3
        key.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.shadowColor = UIColor(white: 0, alpha: look.shadowAlpha)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = SculptedBoardScene.keyPosition
        keyNode.simdLook(at: .zero, up: SculptedCamera.up, localFront: SCNNode.simdLocalFront)
        scene.rootNode.addChildNode(keyNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = look.rim
        rim.color = look.rimColor
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.simdPosition = SIMD3(7, 4, -6)
        rimNode.simdLook(at: .zero, up: SculptedCamera.up, localFront: SCNNode.simdLocalFront)
        scene.rootNode.addChildNode(rimNode)
    }

    /// A round of the board's stone, squares the same size as the game's, rimmed in its metal.
    private func buildStand(_ assets: SculptedAssets) {
        let height: CGFloat = 0.16
        let disc = SCNCylinder(radius: CGFloat(Self.radius), height: height)
        disc.radialSegmentCount = 96
        let stone = assets.squaresMaterial(look).copy() as? SCNMaterial ?? assets.squaresMaterial(look)
        // The baked picture is the whole 8x8 board; the round shows the middle of it at full size.
        let share = Self.radius * 2 / 8
        stone.diffuse.contentsTransform = SCNMatrix4Mult(
            SCNMatrix4MakeScale(share, share, 1),
            SCNMatrix4MakeTranslation((1 - share) / 2, (1 - share) / 2, 0))
        let metal = assets.inlayMaterial(look)
        disc.materials = [metal, stone, metal]
        let node = SCNNode(geometry: disc)
        node.simdPosition = SIMD3(0, -Float(height) / 2, 0)
        turntable.addChildNode(node)
    }

    /// Each side's six pieces in a row, back to back, so a half turn brings the other side round.
    private func buildPieces(_ assets: SculptedAssets) {
        let count = Float(Self.family.count)
        for (index, kind) in Self.family.enumerated() {
            let x = (Float(index) - (count - 1) / 2) * Self.spacing
            for color in [Piece.Color.white, .black] {
                let piece = assets.makePiece(kind, color: color, look: look)
                let front = color == .white
                // Turned as the board turns them, so the knight reads as a horse and the bishop's cut shows.
                let yaw: Float
                switch kind {
                case .knight: yaw = 6 * .pi / 180
                case .bishop: yaw = -112 * .pi / 180
                default: yaw = 0
                }
                let holder = SCNNode()
                holder.addChildNode(piece)
                piece.simdOrientation = simd_quatf(angle: yaw, axis: SculptedCamera.up)
                holder.simdPosition = front ? SIMD3(x, 0, Self.rowOffset) : SIMD3(-x, 0, -Self.rowOffset)
                holder.simdOrientation = simd_quatf(angle: front ? 0 : .pi, axis: SculptedCamera.up)
                turntable.addChildNode(holder)
            }
        }
    }
}

/// The showcase as a SwiftUI view. A new look (another set, or another board under it) makes a new scene.
struct PieceSetShowcaseView: UIViewRepresentable {
    let look: SculptedLook
    var turning: Bool

    final class Coordinator {
        var scene: PieceSetShowcaseScene?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        host.isUserInteractionEnabled = false
        install(in: host, context: context)
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        if context.coordinator.scene?.look.name != look.name {
            host.subviews.forEach { $0.removeFromSuperview() }
            install(in: host, context: context)
        }
        context.coordinator.scene?.setTurning(turning)
    }

    static func dismantleUIView(_ host: UIView, coordinator: Coordinator) {
        coordinator.scene?.setTurning(false)
        coordinator.scene = nil
    }

    private func install(in host: UIView, context: Context) {
        let scene = PieceSetShowcaseScene(look: look)
        scene.view.frame = host.bounds
        scene.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(scene.view)
        scene.setTurning(turning)
        context.coordinator.scene = scene
    }
}
