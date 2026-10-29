import ChessKit
import SwiftUI

/// Ghost Vision on the game board: hold the board and the engine's best line appears a few
/// moves ahead as see-through pieces, fainter the further ahead. Slide the thumb left to take
/// the later moves away, right to bring them back. Let go and it fades.
///
/// It uses the line the coach's hint search already found, so it costs the engine nothing.
/// Seeing it is help, like a hint or an undo.
@MainActor
@Observable
final class GhostVision {
    /// The Settings switch, on unless the player turns it off.
    nonisolated static let storageKey = "ghostVision"

    /// Set while the person holds the board.
    private(set) var isHolding = false
    /// The last step shown; nil shows the whole line.
    private(set) var focus: Int?
    /// A tap that ends a hold isn't a move: taps are ignored until just after it.
    @ObservationIgnored private var quietUntil = Date.distantPast

    /// Whether a tap on the board now belongs to the hold rather than the game.
    var swallowsTap: Bool { isHolding || Date() < quietUntil }

    init() {}

    /// Already held, for the screenshots CI takes and for tests: the whole line, or up to `focus`.
    init(holding: Bool, focus: Int? = nil) {
        isHolding = holding
        self.focus = focus
    }

    func begin() {
        isHolding = true
        focus = nil
    }

    /// The thumb has slid `dx` points sideways since the hold began.
    func scrub(dx: CGFloat, steps: Int) {
        let next = Self.focus(forDrag: dx, steps: steps)
        if next != focus { focus = next }
    }

    func end() {
        guard isHolding else { return }
        isHolding = false
        focus = nil
        quietUntil = Date().addingTimeInterval(0.3)
    }

    /// Points of sideways slide per step of the line.
    static let stepWidth: CGFloat = 34

    /// The last step shown for a slide of `dx`: the whole line until the thumb has gone half a
    /// step left; each step further left takes one more move away, down to the first.
    static func focus(forDrag dx: CGFloat, steps: Int) -> Int? {
        guard steps > 1 else { return nil }
        let shift = Int((dx / stepWidth).rounded())
        guard shift < 0 else { return nil }
        return max(0, steps - 1 + shift)
    }

    /// The last step shown of a line `steps` long.
    func shownFocus(steps: Int) -> Int {
        min(focus ?? steps - 1, steps - 1)
    }
}

extension MatchController {
    /// The Ghost Vision line for the position on the board, once the engine has found it.
    var ghostLine: GhostLine? {
        guard let line = lookahead, line.fen == game.fen else { return nil }
        return line
    }
}

/// The hold-and-slide gesture for Ghost Vision, laid over a board alongside its taps.
struct GhostVisionGesture: ViewModifier {
    let vision: GhostVision?
    let match: MatchController
    /// False while the board shows something else (an earlier position).
    var enabled = true

    @AppStorage("haptics") private var hapticsOn = true
    @GestureState private var held = false
    /// Free players see ahead 3 times a day; past that the hold opens the Premium offer.
    @State private var offer: PremiumFeature?
    /// This hold already asked, so it doesn't ask again while the thumb stays down.
    @State private var refused = false

    func body(content: Content) -> some View {
        let active: Bool = vision != nil && enabled
        content
            // Always attached, so the board never changes identity; masked off when it can't be used.
            .simultaneousGesture(gesture, including: active ? .all : .subviews)
            .onChange(of: held) { _, isHeld in
                if !isHeld {
                    vision?.end()
                    refused = false
                }
            }
            .premiumOffer($offer)
            .onChange(of: match.canPeekAhead) { _, can in
                if !can { vision?.end() }
            }
            .onChange(of: match.ghostLine) { _, line in
                if line != nil, vision?.isHolding == true { match.markAssisted() }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: vision?.isHolding ?? false) { _, new in hapticsOn && new }
            .sensoryFeedback(.selection, trigger: vision?.focus) { _, _ in hapticsOn && vision?.isHolding == true }
    }

    private var gesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($held) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value, let vision else { return }
                if !vision.isHolding {
                    guard enabled, match.canPeekAhead, !refused else { return }
                    // Holding again on the same position doesn't count twice.
                    guard Premium.shared.use(.ghostVision, key: match.game.fen) else {
                        refused = true
                        offer = .ghostVision
                        return
                    }
                    withAnimation(.easeOut(duration: 0.18)) { vision.begin() }
                    if match.ghostLine != nil { match.markAssisted() }
                }
                if let drag {
                    let steps: Int = match.ghostLine?.steps.count ?? 0
                    withAnimation(.easeOut(duration: 0.12)) {
                        vision.scrub(dx: drag.translation.width, steps: steps)
                    }
                }
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.25)) { vision?.end() }
            }
    }
}

/// The strip of moves over the board while Ghost Vision is up: the line, the step the thumb
/// has reached in the board's hint color, and the score at its end.
struct GhostStrip: View {
    let line: GhostLine?
    let focus: Int?
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 7) {
            Text("GHOST")
                .font(.app(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            if let line {
                moves(line)
                Text(line.evaluation.label)
                    .font(.app(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.mini)
                Text("Reading ahead…")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.app(size: 14, weight: .semibold))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassPane(Capsule())
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func moves(_ line: GhostLine) -> some View {
        let words: [String] = line.notation()
        let shown: Int = min(focus ?? words.count - 1, words.count - 1)
        return HStack(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { (index: Int, word: String) in
                Text(word)
                    .foregroundStyle(index == shown ? theme.hint : Color.primary)
                    .opacity(index <= shown ? 1 : 0.3)
            }
        }
    }

    private var accessibilityText: String {
        guard let line else { return "Ghost Vision, reading ahead" }
        return "Ghost Vision: " + line.notation(upTo: focus).joined(separator: ", ")
    }
}

/// The flat board's ghosts: each step's pieces see-through on the squares they move to,
/// a dotted trail from where they set out, and red corners on a piece the line takes.
struct GhostLayer: View {
    let line: GhostLine
    let focus: Int
    let theme: BoardTheme
    /// One square's width.
    let size: CGFloat
    let center: (Square) -> CGPoint

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(line.steps.filter { $0.index <= focus }) { step in
                stepView(step)
            }
        }
        .frame(width: size * 8, height: size * 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stepView(_ step: GhostLine.Step) -> some View {
        let opacity: Double = GhostLine.opacity(of: step.index, focus: focus)
        let main: GhostLine.Move = step.main
        return ZStack(alignment: .topLeading) {
            GhostTrail(from: center(main.from), to: center(main.to), squareSize: size)
                .fill(theme.hint)
                .opacity(min(1, opacity * 1.5))
            if let taken = step.captured {
                CaptureCorners(leg: size * 0.26)
                    .fill(theme.check)
                    .frame(width: size, height: size)
                    .position(center(taken.square))
                    .opacity(min(1, opacity * 1.6))
            }
            ForEach(Array(step.moves.enumerated()), id: \.offset) { (_: Int, move: GhostLine.Move) in
                PieceImage(piece: move.piece, theme: theme, size: size, onBoard: true)
                    .position(center(move.to))
                    .opacity(opacity)
            }
        }
        .frame(width: size * 8, height: size * 8)
        .transition(.opacity)
    }
}

/// Small dots from one square's center towards another's, clear of both ends: the path a ghost took.
struct GhostTrail: Shape {
    let from: CGPoint
    let to: CGPoint
    let squareSize: CGFloat

    func path(in rect: CGRect) -> Path {
        let dx: CGFloat = to.x - from.x
        let dy: CGFloat = to.y - from.y
        let length: CGFloat = (dx * dx + dy * dy).squareRoot()
        let gap: CGFloat = squareSize * 0.3
        let clear: CGFloat = squareSize * 0.36
        let radius: CGFloat = squareSize * 0.05
        var path = Path()
        guard length > clear * 2 else { return path }
        let count: Int = max(1, Int(((length - clear * 2) / gap).rounded()))
        for index in 0...count {
            let t: CGFloat = (clear + (length - clear * 2) * CGFloat(index) / CGFloat(count)) / length
            let point = CGPoint(x: from.x + dx * t, y: from.y + dy * t)
            path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }
}
