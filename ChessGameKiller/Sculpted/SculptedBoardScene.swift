import ChessKit
import SceneKit
import UIKit
import simd

/// One of the best-move arrows on the 3D board.
struct SculptedHint: Equatable {
    let from: Square
    let to: Square
    let isBest: Bool
}

/// The glow under a veteran of the player's army.
struct SculptedHalo: Equatable {
    enum Tone: Equatable {
        case ivory, platinum, gold
    }

    let tone: Tone
    /// A Legend's glow breathes.
    let breathing: Bool

    var color: UIColor {
        switch tone {
        case .ivory: return UIColor(red: 0.96, green: 0.91, blue: 0.82, alpha: 1)
        case .platinum: return UIColor(red: 0.8, green: 0.85, blue: 0.95, alpha: 1)
        case .gold: return UIColor(red: 1, green: 0.82, blue: 0.48, alpha: 1)
        }
    }
}

/// Everything the 3D board shows, copied out of the game so the scene can tell what changed.
struct SculptedBoardState: Equatable {
    var pieces: [PlacedPiece] = []
    var selected: Square?
    var targets: Set<Square> = []
    var lastMove: LastMove?
    var checkedKing: Square?
    var hints: [SculptedHint] = []
    var flipped = false
    /// The newest capture, so a piece that leaves the board can tip over rather than fade.
    var lastCapture: CaptureEvent?
    /// Veteran glows by piece id.
    var halos: [Int: SculptedHalo] = [:]
    /// The pieces come without lasting ids (an earlier position of the game, a preview):
    /// the scene matches them to the pieces on the board so each one moves rather than fades.
    var matchesPieces = false

    /// The parts that decide the marks on the stone.
    fileprivate var marks: [String] {
        let occupied = Set(pieces.map(\.square))
        return [
            lastMove.map { "\($0.from)\($0.to)" } ?? "-",
            selected.map { "\($0)" } ?? "-",
            checkedKing.map { "\($0)" } ?? "-",
            targets.map { "\($0)\(occupied.contains($0) ? "x" : "")" }.sorted().joined(),
        ]
    }
}

/// The SceneKit view, telling the scene its size whenever it is laid out.
final class SculptedSceneKitView: SCNView {
    var onLayout: ((CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(bounds.size)
    }
}

/// The real 3D board: the sculpted pieces on stone, lit like a studio, moving like objects.
///
/// It owns its SceneKit view. `apply(_:animated:)` takes a copy of the game and animates
/// whatever changed: moves glide (knights hop), captured pieces tip over and shrink away,
/// a promoted pawn turns into its new piece, and the camera walks around the board when it flips.
final class SculptedBoardScene {
    static let pieceCategory = 1 << 1

    let view: SculptedSceneKitView
    private let scene = SCNScene()
    private let assets: SculptedAssets
    private let look = SculptedLook.current

    /// The camera as it will be once any walk around the board is over.
    private(set) var camera = SculptedCamera()
    private let cameraNode = SCNNode()
    /// The lights, turned with the camera so the light always falls from the player's left.
    private let rig = SCNNode()
    private let piecesNode = SCNNode()
    private let marksNode = SCNNode()
    private let arrowsNode = SCNNode()
    private let labelsNode = SCNNode()

    private var nodes: [Int: PieceNode] = [:]
    private var state: SculptedBoardState?
    private var size: CGSize = .zero

    init(assets: SculptedAssets = .shared) {
        self.assets = assets
        view = SculptedSceneKitView(frame: CGRect(x: 0, y: 0, width: 320, height: 320), options: nil)
        view.scene = scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.isJitteringEnabled = true
        view.preferredFramesPerSecond = 120
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.autoenablesDefaultLighting = false

        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = assets.environment
        scene.lightingEnvironment.intensity = look.environment

        buildCamera()
        buildLights()
        buildBoard()
        for node in [piecesNode, marksNode, arrowsNode, labelsNode] {
            scene.rootNode.addChildNode(node)
        }
        buildLabels(flipped: false)
        view.onLayout = { [weak self] size in self?.layout(size) }
    }

    // MARK: Reading the view

    /// The square under a point of the view: the piece there when a piece is in the way
    /// (its head can stand in front of the square behind it), otherwise the stone.
    func square(at point: CGPoint) -> Square? {
        let hits = view.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .categoryBitMask: Self.pieceCategory,
            .ignoreHiddenNodes: true,
        ])
        if let hit = hits.first, let id = Self.pieceID(of: hit.node),
           let placed = state?.pieces.first(where: { $0.id == id }) {
            return placed.square
        }
        return camera.square(at: point, in: view.bounds.size)
    }

    /// The picture as it is now, for tests and screenshots.
    func snapshot() -> UIImage {
        view.snapshot()
    }

    private static func pieceID(of node: SCNNode) -> Int? {
        var current: SCNNode? = node
        while let candidate = current {
            if let name = candidate.name, name.hasPrefix("piece-") {
                return Int(name.dropFirst(6))
            }
            current = candidate.parent
        }
        return nil
    }

    // MARK: Updating

    func apply(_ incoming: SculptedBoardState, animated: Bool) {
        var new = incoming
        if new.matchesPieces {
            new.pieces = Self.carryIdentity(new.pieces.map(\.piece), from: state?.pieces ?? [], nextID: &nextLooseID)
        }
        let animate = animated && state != nil
        let old = state ?? SculptedBoardState()
        guard state != new else { return }
        state = new

        if old.flipped != new.flipped {
            orbit(flipped: new.flipped, animated: animate && old.flipped != new.flipped)
        }
        updatePieces(from: old, to: new, animated: animate)
        if old.marks != new.marks || old.pieces.isEmpty {
            updateMarks(new)
        }
        if old.hints != new.hints {
            updateArrows(new.hints)
        }
        if old.halos != new.halos || old.pieces != new.pieces {
            updateHalos(new)
        }
    }

    /// Stretches every move, so a test can photograph one in flight. 1 in the app.
    static var motionScale: Double = 1

    private var nextLooseID = 1_000_000

    /// Gives each piece the id of the piece it most likely is: the same piece on the same
    /// square first, then the nearest one of its kind and color, else a new id.
    static func carryIdentity(_ pieces: [Piece], from current: [PlacedPiece], nextID: inout Int) -> [PlacedPiece] {
        var unmatched = current
        var result: [PlacedPiece] = []
        var moved: [Piece] = []
        for piece in pieces {
            if let i = unmatched.firstIndex(where: { $0.piece == piece }) {
                result.append(PlacedPiece(id: unmatched[i].id, piece: piece))
                unmatched.remove(at: i)
            } else {
                moved.append(piece)
            }
        }
        for piece in moved {
            let candidates = unmatched.indices.filter {
                unmatched[$0].piece.kind == piece.kind && unmatched[$0].piece.color == piece.color
            }
            let distance = { (i: Int) -> Int in
                let other = unmatched[i].square
                let dx = other.fileIndex - piece.square.fileIndex
                let dz = other.rankIndex - piece.square.rankIndex
                return dx * dx + dz * dz
            }
            if let i = candidates.min(by: { distance($0) < distance($1) }) {
                result.append(PlacedPiece(id: unmatched[i].id, piece: piece))
                unmatched.remove(at: i)
            } else {
                result.append(PlacedPiece(id: nextID, piece: piece))
                nextID += 1
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    private func layout(_ newSize: CGSize) {
        guard newSize.width > 1, newSize.height > 1, newSize != size else { return }
        size = newSize
        let flipped = state?.flipped ?? false
        camera = .fitted(aspect: Float(newSize.width / newSize.height), flipped: flipped)
        cameraNode.removeAction(forKey: "orbit")
        place(camera)
    }

    // MARK: Pieces

    private final class PieceNode {
        let id: Int
        var piece: Piece
        /// Stands on the square, turned to face the player.
        let root = SCNNode()
        /// The sculpture itself: lifted, leaned and tipped by the animations.
        let model: SCNNode
        /// A soft shadow on the stone, darkest right under the foot.
        let contact: SCNNode
        var halo: SCNNode?
        let yaw: Float
        let baseRadius: Float
        /// Raised for the selection.
        var lifted = false

        init(id: Int, piece: Piece, model: SCNNode, contact: SCNNode) {
            self.id = id
            self.piece = piece
            self.model = model
            self.contact = contact
            switch piece.kind {
            // Nearly side-on, so the head reads as a horse at a glance.
            case .knight: yaw = 6 * .pi / 180
            case .bishop: yaw = -112 * .pi / 180
            default: yaw = 0
            }
            switch piece.kind {
            case .king: baseRadius = 0.36
            case .queen: baseRadius = 0.35
            case .pawn: baseRadius = 0.3
            default: baseRadius = 0.33
            }
        }
    }

    private static let selectionLift: Float = 0.12
    private static let travelLift: Float = 0.16

    private func makeNode(for placed: PlacedPiece) -> PieceNode {
        let model = assets.makePiece(placed.piece.kind, color: placed.piece.color)
        let contact = SCNNode(geometry: Self.contactGeometry)
        contact.simdPosition = SIMD3(0, 0.0012, 0)
        contact.simdOrientation = Self.flat
        contact.renderingOrder = 5
        contact.castsShadow = false
        let node = PieceNode(id: placed.id, piece: placed.piece, model: model, contact: contact)
        node.root.name = "piece-\(placed.id)"
        node.root.addChildNode(contact)
        node.root.addChildNode(model)
        node.root.simdPosition = SculptedCamera.position(of: placed.square)
        node.root.simdOrientation = simd_quatf(angle: (state?.flipped ?? false) ? .pi : 0, axis: SculptedCamera.up)
        // The blob is a plane laid flat, so its own x and y are the board's x and z.
        node.contact.scale = SCNVector3(node.baseRadius / 0.33, node.baseRadius / 0.33, 1)
        setPose(node, y: 0)
        piecesNode.addChildNode(node.root)
        nodes[placed.id] = node
        return node
    }

    private func updatePieces(from old: SculptedBoardState, to new: SculptedBoardState, animated: Bool) {
        let oldByID = Dictionary(old.pieces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newIDs = Set(new.pieces.map(\.id))

        let moved = new.pieces.filter { placed in oldByID[placed.id].map { $0.square != placed.square } ?? false }
        let added = new.pieces.filter { oldByID[$0.id] == nil }
        let removed = old.pieces.filter { !newIDs.contains($0.id) }

        guard animated else {
            snap(to: new)
            return
        }

        // A new game or a position set up by hand: everything glides home together.
        let bulk = moved.count > 2 || added.count + removed.count > 2
        let lead = moved.first { $0.square == new.lastMove?.to } ?? moved.first
        let leadOrigin = lead.flatMap { oldByID[$0.id] }.map { SculptedCamera.position(of: $0.square) }
        var leadTiming = MoveTiming.quick

        for placed in moved {
            guard let node = nodes[placed.id], let before = oldByID[placed.id] else { continue }
            let capturing = placed.id == lead?.id && removed.contains { isCapture($0, in: new, old: old) }
            let timing = bulk ? MoveTiming.bulk : MoveTiming(
                from: before.square, to: placed.square, knight: placed.piece.kind == .knight,
                capturing: capturing, lifted: node.lifted
            )
            if placed.id == lead?.id { leadTiming = timing }
            node.piece = placed.piece
            node.lifted = false
            animateMove(node, to: placed.square, timing: timing)
        }

        for gone in removed {
            guard let node = nodes[gone.id] else { continue }
            nodes[gone.id] = nil
            if let successor = added.first(where: { $0.square == gone.square && $0.piece.color == gone.piece.color }), !bulk {
                // Promotion: the pawn sinks away and its new piece rises in its place.
                vanish(node, after: 0, duration: 0.18)
                appear(makeNode(for: successor), after: 0.14)
            } else if !bulk, isCapture(gone, in: new, old: old) {
                let origin = leadOrigin ?? SculptedCamera.position(of: gone.square) + SIMD3(0, 0, 1)
                topple(node, awayFrom: origin, timing: leadTiming)
            } else {
                vanish(node, after: 0, duration: 0.2)
            }
        }

        for placed in added where nodes[placed.id] == nil {
            // A piece brought back by an undo waits for the piece leaving its square.
            appear(makeNode(for: placed), after: bulk ? 0.1 : 0.22)
        }

        // The selected piece rises a little; the one let go of settles back.
        for placed in new.pieces {
            guard let node = nodes[placed.id], !moved.contains(where: { $0.id == placed.id }),
                  !added.contains(where: { $0.id == placed.id }) else { continue }
            let wantsLift = new.selected == placed.square
            if wantsLift != node.lifted {
                node.lifted = wantsLift
                settle(node, lifted: wantsLift)
            }
        }
    }

    /// Whether a piece left the board because it was taken in the move just played.
    private func isCapture(_ gone: PlacedPiece, in new: SculptedBoardState, old: SculptedBoardState) -> Bool {
        guard let capture = new.lastCapture, capture.id != old.lastCapture?.id else { return false }
        return capture.piece == gone.piece
    }

    /// Puts every piece where it belongs at once.
    private func snap(to new: SculptedBoardState) {
        let keep = Set(new.pieces.map(\.id))
        for (id, node) in nodes where !keep.contains(id) {
            node.root.removeFromParentNode()
            nodes[id] = nil
        }
        for placed in new.pieces {
            let node = nodes[placed.id] ?? makeNode(for: placed)
            node.root.removeAllActions()
            node.piece = placed.piece
            node.root.simdPosition = SculptedCamera.position(of: placed.square)
            node.root.opacity = 1
            node.lifted = new.selected == placed.square
            setPose(node, y: node.lifted ? Self.selectionLift : 0)
        }
    }

    /// How long each part of a move takes, in seconds.
    private struct MoveTiming {
        var lift: Double
        var travel: Double
        var land: Double
        var wobble: Double
        var hop: Float
        var lean: Float

        static let quick = MoveTiming(lift: 0.1, travel: 0.25, land: 0.08, wobble: 0.34, hop: 0, lean: 0)
        static let bulk = MoveTiming(lift: 0.06, travel: 0.42, land: 0.08, wobble: 0, hop: 0.12, lean: 0)

        init(lift: Double, travel: Double, land: Double, wobble: Double, hop: Float, lean: Float) {
            self.lift = lift
            self.travel = travel
            self.land = land
            self.wobble = wobble
            self.hop = hop
            self.lean = lean
        }

        /// Longer moves take a little longer, growing with the square root of the distance.
        /// Knights hop in an arc. A capture slows the move so the taken piece can fall first.
        init(from: Square, to: Square, knight: Bool, capturing: Bool, lifted: Bool) {
            let dx = Double(to.fileIndex - from.fileIndex)
            let dz = Double(to.rankIndex - from.rankIndex)
            let distance = (dx * dx + dz * dz).squareRoot()
            lift = lifted ? 0.06 : 0.1
            travel = (0.16 + 0.075 * distance.squareRoot()) * (capturing ? 1.35 : 1)
            land = 0.08
            wobble = 0.34
            hop = knight ? 0.42 : 0
            lean = (knight ? 5 : 2) * .pi / 180
            if UIAccessibility.isReduceMotionEnabled {
                hop = 0
                lean = 0
                wobble = 0
            }
            let stretch = SculptedBoardScene.motionScale
            lift *= stretch
            travel *= stretch
            land *= stretch
            wobble *= stretch
        }

        var total: Double { lift + travel + land + wobble }
    }

    private func animateMove(_ node: PieceNode, to square: Square, timing: MoveTiming) {
        let start = node.root.simdPosition
        let end = SculptedCamera.position(of: square)
        let startY = node.model.simdPosition.y
        let offset = end - start
        let flat = SIMD3<Float>(offset.x, 0, offset.z)
        let direction = simd_length(flat) > 0.001 ? simd_normalize(flat) : SIMD3<Float>(0, 0, -1)
        // Leaning into the move: the top runs ahead along the way it travels.
        let axis = local(simd_cross(SculptedCamera.up, direction), in: node)
        let yaw = node.yaw
        let model = node.model
        let lift = Self.travelLift
        let t = timing

        let action = SCNAction.customAction(duration: t.total) { root, elapsed in
            let time = Double(elapsed)
            var position = start
            var y: Float = 0
            var tilt: Float = 0
            if time < t.lift {
                y = startY + (lift - startY) * Ease.slowEnd(Float(time / t.lift))
            } else if time < t.lift + t.travel {
                let u = Float((time - t.lift) / t.travel)
                let e = Ease.smooth(u)
                position = start + offset * e
                y = lift + (0.03 - lift) * e + t.hop * 4 * e * (1 - e)
                tilt = t.lean * sin(.pi * u)
            } else if time < t.lift + t.travel + t.land {
                position = end
                y = 0.03 * (1 - Ease.slowStart(Float((time - t.lift - t.travel) / t.land)))
            } else {
                position = end
                let u = Float((time - t.lift - t.travel - t.land) / max(t.wobble, 0.001))
                tilt = 2.2 * .pi / 180 * exp(-4 * u) * sin(3 * .pi * u)
            }
            root.simdPosition = position
            model.simdTransform = Self.pose(y: y, axis: axis, angle: tilt, scale: 1, yaw: yaw)
        }
        node.root.runAction(action, forKey: "pose")
        node.contact.runAction(.sequence([
            .fadeOpacity(to: 0.45, duration: t.lift),
            .wait(duration: t.travel * 0.7),
            .fadeOpacity(to: 1, duration: t.travel * 0.3 + t.land),
        ]), forKey: "contact")
    }

    /// The taken piece tips away from the attacker about the far edge of its foot,
    /// slides a little and shrinks to nothing before the attacker lands.
    private func topple(_ node: PieceNode, awayFrom origin: SIMD3<Float>, timing: MoveTiming) {
        let offset = node.root.simdPosition - origin
        let flat = SIMD3<Float>(offset.x, 0, offset.z)
        let away = simd_length(flat) > 0.001 ? simd_normalize(flat) : SIMD3<Float>(0, 0, -1)
        let direction = local(away, in: node)
        let axis = local(simd_cross(SculptedCamera.up, away), in: node)
        let pivot = direction * node.baseRadius
        let yaw = node.yaw
        let model = node.model
        let start = timing.lift + timing.travel * 0.12
        let tip = max(timing.travel * 0.55, 0.16)
        let shrinkFrom = timing.travel * 0.3
        let shrink = max(timing.travel * 0.55, 0.16)
        let total = max(tip, shrinkFrom + shrink)

        let fall = SCNAction.customAction(duration: total) { _, elapsed in
            let time = Double(elapsed)
            let u = Ease.slowStart(Float(min(time / tip, 1)))
            let angle = 70 * .pi / 180 * u
            let slide = 0.12 * u
            let s = 1 - Ease.smooth(Float(min(max((time - shrinkFrom) / shrink, 0), 1)))
            let turn = simd_quatf(angle: angle, axis: axis)
            var transform = matrix_identity_float4x4
            transform = Self.translation(pivot) * simd_float4x4(turn) * Self.translation(-pivot)
            transform = transform * Self.translation(direction * slide)
            transform = transform * Self.scale(max(s, 0.0001)) * simd_float4x4(simd_quatf(angle: yaw, axis: SculptedCamera.up))
            model.simdTransform = transform
        }
        node.root.runAction(.sequence([.wait(duration: start), fall, .removeFromParentNode()]), forKey: "pose")
        node.contact.runAction(.sequence([.wait(duration: start), .fadeOut(duration: tip * 0.8)]))
        node.halo?.runAction(.fadeOut(duration: 0.15))
    }

    /// Fades a piece out where it stands, sinking a touch.
    private func vanish(_ node: PieceNode, after delay: Double, duration: Double) {
        let model = node.model
        let yaw = node.yaw
        let sink = SCNAction.customAction(duration: duration) { _, elapsed in
            let u = Ease.smooth(Float(Double(elapsed) / duration))
            model.simdTransform = Self.pose(y: 0, axis: SIMD3(1, 0, 0), angle: 0, scale: 1 - 0.35 * u, yaw: yaw)
        }
        node.root.runAction(.sequence([
            .wait(duration: delay),
            .group([sink, .fadeOut(duration: duration)]),
            .removeFromParentNode(),
        ]), forKey: "pose")
    }

    /// A piece arriving on the board: it rises out of the stone and settles.
    private func appear(_ node: PieceNode, after delay: Double) {
        let model = node.model
        let yaw = node.yaw
        node.root.opacity = 0
        setPose(node, y: 0, scale: 0.6)
        let grow = SCNAction.customAction(duration: 0.3) { _, elapsed in
            let u = Float(Double(elapsed) / 0.3)
            // A little overshoot, then rest.
            let s = 0.6 + 0.4 * Ease.slowEnd(u) + 0.04 * sin(.pi * u)
            model.simdTransform = Self.pose(y: 0, axis: SIMD3(1, 0, 0), angle: 0, scale: s, yaw: yaw)
        }
        node.root.runAction(.sequence([
            .wait(duration: delay),
            .group([grow, .fadeIn(duration: 0.2)]),
            .run { _ in model.simdTransform = Self.pose(y: 0, axis: SIMD3(1, 0, 0), angle: 0, scale: 1, yaw: yaw) },
        ]), forKey: "pose")
    }

    /// Raises the selected piece or sets it back down.
    private func settle(_ node: PieceNode, lifted: Bool) {
        let from = node.model.simdPosition.y
        let to = lifted ? Self.selectionLift : 0
        let model = node.model
        let yaw = node.yaw
        let duration = lifted ? 0.14 : 0.12
        let action = SCNAction.customAction(duration: duration) { _, elapsed in
            let u = Float(Double(elapsed) / duration)
            let e = lifted ? Ease.slowEnd(u) : Ease.smooth(u)
            model.simdTransform = Self.pose(y: from + (to - from) * e, axis: SIMD3(1, 0, 0), angle: 0, scale: 1, yaw: yaw)
        }
        node.root.runAction(action, forKey: "pose")
        node.contact.runAction(.fadeOpacity(to: lifted ? 0.55 : 1, duration: duration), forKey: "contact")
    }

    private func setPose(_ node: PieceNode, y: Float, scale: Float = 1) {
        node.model.simdTransform = Self.pose(y: y, axis: SIMD3(1, 0, 0), angle: 0, scale: scale, yaw: node.yaw)
    }

    /// A direction on the board turned into the piece's own frame.
    private func local(_ vector: SIMD3<Float>, in node: PieceNode) -> SIMD3<Float> {
        node.root.simdWorldOrientation.inverse.act(vector)
    }

    private static func pose(y: Float, axis: SIMD3<Float>, angle: Float, scale s: Float, yaw: Float) -> simd_float4x4 {
        translation(SIMD3(0, y, 0))
            * simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(axis)))
            * scale(s)
            * simd_float4x4(simd_quatf(angle: yaw, axis: SculptedCamera.up))
    }

    private static func translation(_ v: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(v.x, v.y, v.z, 1)
        return m
    }

    private static func scale(_ s: Float) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(s, s, s, 1))
    }

    // MARK: Halos

    private func updateHalos(_ new: SculptedBoardState) {
        for (id, node) in nodes {
            let wanted = new.halos[id]
            node.halo?.removeFromParentNode()
            node.halo = nil
            guard let wanted else { continue }
            let halo = SCNNode(geometry: Self.mark(size: 1.2, color: wanted.color, alpha: 0.75, mask: Self.haloMask))
            halo.simdPosition = SIMD3(0, 0.0021, 0)
            halo.simdOrientation = Self.flat
            halo.renderingOrder = 6
            halo.castsShadow = false
            if wanted.breathing {
                halo.runAction(.repeatForever(.sequence([
                    .fadeOpacity(to: 0.4, duration: 0.8),
                    .fadeOpacity(to: 1, duration: 0.8),
                ])))
            }
            node.root.addChildNode(halo)
            node.halo = halo
        }
    }

    // MARK: Marks on the stone

    private func updateMarks(_ new: SculptedBoardState) {
        marksNode.childNodes.forEach { $0.removeFromParentNode() }
        let occupied = Set(new.pieces.map(\.square))
        if let last = new.lastMove {
            for square in [last.from, last.to] {
                addMark(lastMoveMark, at: square, height: 0.0015)
            }
        }
        if let selected = new.selected {
            addMark(selectedMark, at: selected, height: 0.0017)
        }
        if let king = new.checkedKing {
            addMark(checkMark, at: king, height: 0.0019)
        }
        for target in new.targets {
            addMark(occupied.contains(target) ? captureMark : dotMark, at: target, height: 0.0023, fade: true)
        }
    }

    private func addMark(_ geometry: SCNGeometry, at square: Square, height: Float, fade: Bool = false) {
        let node = SCNNode(geometry: geometry)
        node.simdPosition = SculptedCamera.position(of: square) + SIMD3(0, height, 0)
        node.simdOrientation = Self.flat
        node.renderingOrder = 10
        node.castsShadow = false
        if fade {
            node.opacity = 0
            node.runAction(.fadeIn(duration: 0.14))
        }
        marksNode.addChildNode(node)
    }

    private static let flat = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))

    private static func mark(size: CGFloat, color: UIColor, alpha: CGFloat, mask: UIImage?) -> SCNGeometry {
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        if let mask { material.transparent.contents = mask }
        material.transparencyMode = .aOne
        material.transparency = alpha
        material.writesToDepthBuffer = false
        material.blendMode = .alpha
        plane.materials = [material]
        return plane
    }

    private lazy var lastMoveMark = Self.mark(size: 1, color: look.lastMove, alpha: look.lastMoveAlpha, mask: nil)
    private lazy var selectedMark = Self.mark(size: 1, color: look.accent, alpha: 0.3, mask: nil)
    private lazy var checkMark = Self.mark(size: 1.5, color: look.check, alpha: 0.9, mask: MarkImages.glow)
    private lazy var dotMark = Self.mark(size: 1, color: look.accent, alpha: 0.92, mask: MarkImages.dot)
    private lazy var captureMark = Self.mark(size: 1, color: look.accent, alpha: 0.92, mask: MarkImages.ring)
    private static let contactGeometry = mark(size: 1, color: .black, alpha: 0.5, mask: MarkImages.contact)
    private static let haloMask = MarkImages.halo

    // MARK: Best-move arrows

    private func updateArrows(_ hints: [SculptedHint]) {
        for old in arrowsNode.childNodes {
            old.runAction(.sequence([.fadeOut(duration: 0.15), .removeFromParentNode()]))
        }
        // The runner-up first, so the best arrow lies on top where they cross.
        for (index, hint) in hints.sorted(by: { !$0.isBest && $1.isBest }).enumerated() {
            let node = SCNNode(geometry: Self.arrow(hint, color: look.accent))
            node.simdOrientation = Self.flat
            node.simdPosition = SIMD3(0, 0.003 + 0.0004 * Float(index), 0)
            node.renderingOrder = 12 + index
            node.castsShadow = false
            node.opacity = 0
            node.runAction(.fadeIn(duration: 0.25))
            arrowsNode.addChildNode(node)
        }
    }

    /// A flat arrow lying on the stone: solid with a round tail for the best move,
    /// dashed for the second best. Sizes match the flat board's arrows.
    private static func arrow(_ hint: SculptedHint, color: UIColor) -> SCNGeometry {
        // Path coordinates are (x, -z): the shape is drawn upright, then laid flat.
        func point(_ v: SIMD3<Float>) -> CGPoint { CGPoint(x: CGFloat(v.x), y: CGFloat(-v.z)) }
        let from = point(SculptedCamera.position(of: hint.from))
        let to = point(SculptedCamera.position(of: hint.to))
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(hypot(dx, dy), 0.001)
        let ux = dx / length
        let uy = dy / length
        let nx = -uy
        let ny = ux
        let headLength: CGFloat = hint.isBest ? 0.42 : 0.36
        let headHalf: CGFloat = hint.isBest ? 0.25 : 0.21
        let shaftHalf: CGFloat = hint.isBest ? 0.085 : 0.055
        let start = CGPoint(x: from.x + ux * 0.18, y: from.y + uy * 0.18)
        let tip = CGPoint(x: to.x - ux * 0.08, y: to.y - uy * 0.08)
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
        func offset(_ p: CGPoint, _ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: p.x + ux * along + nx * across, y: p.y + uy * along + ny * across)
        }

        let path = UIBezierPath()
        if hint.isBest {
            path.move(to: offset(start, 0, shaftHalf))
            path.addLine(to: offset(base, 0, shaftHalf))
            path.addLine(to: offset(base, 0, headHalf))
            path.addLine(to: tip)
            path.addLine(to: offset(base, 0, -headHalf))
            path.addLine(to: offset(base, 0, -shaftHalf))
            path.addLine(to: offset(start, 0, -shaftHalf))
            // The round tail.
            let angle = atan2(ny, nx)
            path.addArc(withCenter: start, radius: shaftHalf, startAngle: angle + .pi, endAngle: angle, clockwise: false)
            path.close()
        } else {
            let shaft = hypot(base.x - start.x, base.y - start.y)
            let dash = shaftHalf * 2 * 1.6
            let gap = shaftHalf * 2 * 1.1
            var along: CGFloat = 0
            while along < shaft - 0.01 {
                let end = min(along + dash, shaft)
                path.move(to: offset(start, along, shaftHalf))
                path.addLine(to: offset(start, end, shaftHalf))
                path.addLine(to: offset(start, end, -shaftHalf))
                path.addLine(to: offset(start, along, -shaftHalf))
                path.close()
                along = end + gap
            }
            path.move(to: tip)
            path.addLine(to: offset(base, 0, -headHalf))
            path.addLine(to: offset(base, 0, headHalf))
            path.close()
        }
        path.flatness = 0.004
        let shape = SCNShape(path: path, extrusionDepth: 0)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.transparency = hint.isBest ? 0.95 : 0.75
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        shape.materials = [material]
        return shape
    }

    // MARK: Camera and light

    private func buildCamera() {
        let lens = SCNCamera()
        lens.fieldOfView = CGFloat(camera.fieldOfView * 180 / .pi)
        lens.projectionDirection = .horizontal
        lens.zNear = 6
        lens.zFar = 80
        cameraNode.camera = lens
        scene.rootNode.addChildNode(cameraNode)
        view.pointOfView = cameraNode
        camera = .fitted(aspect: 1, flipped: false)
        place(camera)
    }

    private func place(_ camera: SculptedCamera) {
        cameraNode.simdPosition = camera.eye
        cameraNode.simdLook(at: camera.target, up: SculptedCamera.up, localFront: SCNNode.simdLocalFront)
        rig.simdOrientation = simd_quatf(angle: camera.azimuth, axis: SculptedCamera.up)
    }

    /// Walks the camera around to the other side, and turns the pieces and labels with it
    /// so they keep facing the player.
    private func orbit(flipped: Bool, animated: Bool) {
        let target = SculptedCamera.fitted(aspect: camera.aspect, flipped: flipped)
        let turn: Float = flipped ? .pi : 0
        camera = target
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            cameraNode.removeAction(forKey: "orbit")
            place(target)
            for node in nodes.values {
                node.root.simdOrientation = simd_quatf(angle: turn, axis: SculptedCamera.up)
            }
            buildLabels(flipped: flipped)
            return
        }
        let duration = 0.85
        let from = flipped ? Float(0) : .pi
        let rig = rig
        let walk = SCNAction.customAction(duration: duration) { node, elapsed in
            var step = target
            step.azimuth = from + (turn - from) * Ease.smooth(Float(Double(elapsed) / duration))
            node.simdPosition = step.eye
            node.simdLook(at: step.target, up: SculptedCamera.up, localFront: SCNNode.simdLocalFront)
            rig.simdOrientation = simd_quatf(angle: step.azimuth, axis: SculptedCamera.up)
        }
        cameraNode.runAction(walk, forKey: "orbit")
        for node in nodes.values {
            let spin = SCNAction.rotateTo(x: 0, y: CGFloat(turn), z: 0, duration: duration, usesShortestUnitArc: false)
            spin.timingMode = .easeInEaseOut
            node.root.runAction(spin, forKey: "turn")
        }
        labelsNode.runAction(.sequence([
            .fadeOut(duration: duration * 0.3),
            .run { [weak self] _ in DispatchQueue.main.async { self?.buildLabels(flipped: flipped) } },
            .wait(duration: duration * 0.5),
            .fadeIn(duration: duration * 0.3),
        ]))
    }

    private func buildLights() {
        scene.rootNode.addChildNode(rig)

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
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = UIColor(white: 0, alpha: 0.62)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = SIMD3(-6, 9, 5)
        keyNode.simdLook(at: .zero, up: SculptedCamera.up, localFront: SCNNode.simdLocalFront)
        rig.addChildNode(keyNode)

        // A cool light from behind on the right, for a bright edge down the far side of each piece.
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = look.rim
        rim.color = look.rimColor
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.simdPosition = SIMD3(7, 4, -6)
        rimNode.simdLook(at: .zero, up: SculptedCamera.up, localFront: SCNNode.simdLocalFront)
        rig.addChildNode(rimNode)

        // The board's own shadow on whatever is behind the view.
        let floor = SCNNode(geometry: SCNPlane(width: 40, height: 40))
        let catcher = SCNMaterial()
        catcher.lightingModel = .shadowOnly
        floor.geometry?.materials = [catcher]
        floor.simdOrientation = Self.flat
        floor.simdPosition = SIMD3(0, -0.14, 0)
        floor.castsShadow = false
        scene.rootNode.addChildNode(floor)

        let ground = SCNNode(geometry: Self.mark(size: 10.2, color: .black, alpha: 0.55, mask: MarkImages.boardShadow))
        ground.simdOrientation = Self.flat
        ground.simdPosition = SIMD3(0, -0.139, 0)
        ground.castsShadow = false
        ground.renderingOrder = -5
        scene.rootNode.addChildNode(ground)
    }

    // MARK: The board

    private func buildBoard() {
        let board = SCNNode()
        let squares = SCNNode(geometry: SCNPlane(width: 8, height: 8))
        squares.geometry?.materials = [assets.squaresMaterial()]
        squares.simdOrientation = Self.flat
        board.addChildNode(squares)

        // Four lacquered rails with softened edges, standing a hair above the stone.
        let frame = assets.frameMaterial()
        let width: Float = 0.55
        let height: Float = 0.14
        let rails: [(x: Float, z: Float, width: Float, length: Float)] = [
            (0, -4 - width / 2, 8 + 2 * width, width),
            (0, 4 + width / 2, 8 + 2 * width, width),
            (4 + width / 2, 0, width, 8),
            (-4 - width / 2, 0, width, 8),
        ]
        for rail in rails {
            let box = SCNBox(width: CGFloat(rail.width), height: CGFloat(height), length: CGFloat(rail.length), chamferRadius: 0.012)
            box.materials = [frame]
            let node = SCNNode(geometry: box)
            node.simdPosition = SIMD3(rail.x, 0.005 - height / 2, rail.z)
            board.addChildNode(node)
        }

        // A fine metal line around the squares.
        let metal = assets.inlayMaterial()
        let gap: Float = 0.09
        let line: Float = 0.012
        let span = 8 + 2 * gap + line
        let inlay: [(x: Float, z: Float, width: Float, length: Float)] = [
            (0, -4 - gap, span, line), (0, 4 + gap, span, line),
            (4 + gap, 0, line, span), (-4 - gap, 0, line, span),
        ]
        for strip in inlay {
            let box = SCNBox(width: CGFloat(strip.width), height: 0.003, length: CGFloat(strip.length), chamferRadius: 0)
            box.materials = [metal]
            let node = SCNNode(geometry: box)
            node.simdPosition = SIMD3(strip.x, 0.0062, strip.z)
            node.castsShadow = false
            board.addChildNode(node)
        }
        scene.rootNode.addChildNode(board)
    }

    /// Files and ranks engraved along the player's side of the frame, upright for the player.
    private func buildLabels(flipped: Bool) {
        labelsNode.childNodes.forEach { $0.removeFromParentNode() }
        let side: Float = flipped ? -1 : 1
        let turn = simd_quatf(angle: flipped ? .pi : 0, axis: SculptedCamera.up) * Self.flat
        let files = Array("abcdefgh")
        for index in 0..<8 {
            addLabel(String(files[index]), at: SIMD3(Float(index) - 3.5, 0.0064, 4.3 * side), orientation: turn)
            addLabel("\(index + 1)", at: SIMD3(-4.3 * side, 0.0064, 3.5 - Float(index)), orientation: turn)
        }
    }

    private func addLabel(_ text: String, at position: SIMD3<Float>, orientation: simd_quatf) {
        let node = SCNNode(geometry: Self.mark(size: 0.24, color: look.platinumMark, alpha: 0.8, mask: MarkImages.label(text)))
        node.simdPosition = position
        node.simdOrientation = orientation
        node.castsShadow = false
        node.renderingOrder = 8
        labelsNode.addChildNode(node)
    }
}

/// Easing curves for the motion, from 0 to 1.
enum Ease {
    static func slowEnd(_ t: Float) -> Float {
        let c = min(max(t, 0), 1)
        return 1 - (1 - c) * (1 - c) * (1 - c)
    }

    static func slowStart(_ t: Float) -> Float {
        let c = min(max(t, 0), 1)
        return c * c * c
    }

    static func smooth(_ t: Float) -> Float {
        let c = min(max(t, 0), 1)
        return c * c * (3 - 2 * c)
    }
}

/// The soft shapes drawn on the stone, as white-on-clear masks.
enum MarkImages {
    static let dot = draw(128) { context, size in
        let r = size * 0.15
        context.fillEllipse(in: CGRect(x: size / 2 - r, y: size / 2 - r, width: r * 2, height: r * 2))
    }

    static let ring = draw(256) { context, size in
        let line = size * 0.055
        let r = size * 0.45 - line / 2
        context.setLineWidth(line)
        context.strokeEllipse(in: CGRect(x: size / 2 - r, y: size / 2 - r, width: r * 2, height: r * 2))
    }

    static let glow = radial(256, stops: [(0, 1), (0.35, 0.75), (1, 0)])
    static let contact = radial(128, stops: [(0, 1), (0.42, 0.7), (0.62, 0.25), (1, 0)])

    static let halo = draw(256) { context, size in
        let r = size * 0.36
        context.setShadow(offset: .zero, blur: size * 0.06, color: UIColor.white.cgColor)
        context.setLineWidth(size * 0.035)
        context.strokeEllipse(in: CGRect(x: size / 2 - r, y: size / 2 - r, width: r * 2, height: r * 2))
    }

    /// A dark rectangle with soft edges, under the whole board.
    static let boardShadow = draw(256) { context, size in
        let inset = size * 0.05
        context.setShadow(offset: .zero, blur: size * 0.035, color: UIColor.white.cgColor)
        context.fill(CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2))
    }

    static func label(_ text: String) -> UIImage {
        if let cached = labels[text] { return cached }
        let image = draw(96) { _, size in
            let font = UIFont.systemFont(ofSize: size * 0.62, weight: .semibold)
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.white])
            let bounds = string.size()
            string.draw(at: CGPoint(x: (size - bounds.width) / 2, y: (size - bounds.height) / 2))
        }
        labels[text] = image
        return image
    }

    private static var labels: [String: UIImage] = [:]

    private static func draw(_ pixels: CGFloat, _ body: (CGContext, CGFloat) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: pixels, height: pixels), format: format).image { renderer in
            let context = renderer.cgContext
            context.setFillColor(UIColor.white.cgColor)
            context.setStrokeColor(UIColor.white.cgColor)
            body(context, pixels)
        }
    }

    private static func radial(_ pixels: CGFloat, stops: [(CGFloat, CGFloat)]) -> UIImage {
        draw(pixels) { context, size in
            let colors = stops.map { UIColor(white: 1, alpha: $0.1).cgColor } as CFArray
            let locations = stops.map(\.0)
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
            let center = CGPoint(x: size / 2, y: size / 2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size / 2, options: [])
        }
    }
}
