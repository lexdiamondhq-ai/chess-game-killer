import ChessKit
import SwiftUI

/// The welcome's tour: one page for each thing the app does that others don't, each with its
/// own small scene that plays when the page opens. Pieces drop onto the board, a screenshot is
/// read, Leo answers out loud, the day's masterpiece plays itself out, Today's Move is solved,
/// the crowd's moves fill in and a knight earns its gold seams.
enum TourPage: Int, CaseIterable, Identifiable {
    case hello, analyze, leo, masterpiece, today, rivals, pieces

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .hello: return "Welcome"
        case .analyze: return "Analyze"
        case .leo: return "Train with Leo"
        case .masterpiece: return "Masterpiece of the day"
        case .today: return "Today's Move"
        case .rivals: return "Rivals"
        case .pieces: return "Your pieces"
        }
    }

    /// The title in two parts: plain, then the gold italic ending.
    var title: (plain: String, gold: String) {
        switch self {
        case .hello: return ("Beauty of", "Chess")
        case .analyze: return ("Snap any position.", "See the best move.")
        case .leo: return ("A coach who", "talks it through.")
        case .masterpiece: return ("History's great games,", "one a day.")
        case .today: return ("One puzzle.", "Everyone, today.")
        case .rivals: return ("Rivals who play", "like people.")
        case .pieces: return ("Every piece", "keeps its story.")
        }
    }

    var text: String {
        switch self {
        case .hello:
            return "A coach in your pocket, rivals who play like people, and a little masterpiece every day."
        case .analyze:
            return "A photo, a screenshot or a book diagram. The board is read for you and Stockfish answers in a second, right on your phone."
        case .leo:
            return "Ask why, out loud. Leo answers in his own voice, grades every move you play and shows you a better one."
        case .masterpiece:
            return "Each morning a famous finish plays itself out. Tap it to step through every move and test it against Stockfish."
        case .today:
            return "The same move for every player. Find it, keep your streak and see how the world did. It waits on your Lock Screen too."
        case .rivals:
            return "Crowd rivals choose moves the way real players at their rating do. Take the same piece three times and they hold a grudge."
        case .pieces:
            return "Your pieces earn names and experience game by game. Gold seams mark each comeback, the way a real set wears its years."
        }
    }

    /// The stage light behind the scene.
    var light: Color {
        switch self {
        case .hello, .pieces: return TourPalette.gold.opacity(0.26)
        case .analyze: return Color(hex: 0x7FBEE0).opacity(0.17)
        case .leo: return TourPalette.gold.opacity(0.2)
        case .masterpiece: return Color(hex: 0xC8965A).opacity(0.24)
        case .today: return TourPalette.green.opacity(0.14)
        case .rivals: return TourPalette.coral.opacity(0.17)
        }
    }

    @ViewBuilder
    var scene: some View {
        switch self {
        case .hello: TourHelloScene()
        case .analyze: TourAnalyzeScene()
        case .leo: TourLeoScene()
        case .masterpiece: TourMasterpieceScene()
        case .today: TourTodayScene()
        case .rivals: TourRivalsScene()
        case .pieces: TourPiecesScene()
        }
    }
}

/// The welcome's colors: a dark stage, gold light and ivory, like the dark home.
enum TourPalette {
    static let room = Color(hex: 0x0E0C0B)
    static let ink = Color(hex: 0xF3ECE0)
    static let gold = Color(hex: 0xD9B26A)
    static let goldHigh = Color(hex: 0xF4DDA4)
    static let ivory = Color(hex: 0xF4EDDF)
    static let onIvory = Color(hex: 0x15110C)
    static let glass = Color(hex: 0xFFF8EB).opacity(0.07)
    static let glassLine = Color(hex: 0xFFF8EB).opacity(0.13)
    static let coral = Color(hex: 0xEF7B6E)
    static let green = Color(hex: 0x7FE0A3)
    static let teal = Color(hex: 0x7FD8E0)
    static let flame = Color(hex: 0xF0AE5A)
    static let light = Color(hex: 0xE6D6B4)
    static let dark = Color(hex: 0x9C7A50)
    static let frame = Color(hex: 0x2A231B)

    /// The pieces every scene uses: the default Gilded set.
    static var theme: BoardTheme { .named(.gilded) }
}

// MARK: - The stage

/// The room behind every page: near black, a pool of colored light where the scene stands,
/// and a little gold dust drifting up.
struct TourStage: View {
    let light: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TourPalette.room
            RadialGradient(colors: [light, .clear], center: UnitPoint(x: 0.5, y: 0.32),
                           startRadius: 0, endRadius: 360)
            RadialGradient(colors: [TourPalette.gold.opacity(0.08), .clear], center: UnitPoint(x: 0.5, y: 1.1),
                           startRadius: 0, endRadius: 420)
            if !reduceMotion {
                TourDust()
            }
        }
        .animation(.easeInOut(duration: 0.9), value: light)
        .accessibilityHidden(true)
    }
}

/// Specks of gold that rise slowly and wrap around.
private struct TourDust: View {
    private struct Mote {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let speed: CGFloat
        let alpha: Double
    }

    private static let motes: [Mote] = (0..<26).map { index in
        // Fixed, scattered values: the same sky every launch.
        let seed = Double(index) * 12.9898
        func noise(_ shift: Double) -> Double { abs(sin(seed + shift) * 43_758.5453).truncatingRemainder(dividingBy: 1) }
        return Mote(x: CGFloat(noise(1)), y: CGFloat(noise(2)), radius: CGFloat(0.5 + noise(3) * 1.3),
                    speed: CGFloat(0.006 + noise(4) * 0.014), alpha: 0.15 + noise(5) * 0.45)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { canvas, size in
                let time = CGFloat(context.date.timeIntervalSinceReferenceDate)
                for mote in Self.motes {
                    var y = (mote.y - time * mote.speed).truncatingRemainder(dividingBy: 1)
                    if y < 0 { y += 1 }
                    let rect = CGRect(x: mote.x * size.width, y: y * size.height,
                                      width: mote.radius * 2, height: mote.radius * 2)
                    canvas.fill(Path(ellipseIn: rect), with: .color(TourPalette.goldHigh.opacity(mote.alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Runs a scene's beats: after each pause, the next step, in its own animation. With Reduce
/// Motion the scene opens on its last step.
struct TourBeat {
    let pause: Double
    let animation: Animation

    init(_ pause: Double, _ animation: Animation = .spring(response: 0.55, dampingFraction: 0.82)) {
        self.pause = pause
        self.animation = animation
    }

    @MainActor
    static func play(_ beats: [TourBeat], reduceMotion: Bool, step: Binding<Int>) async {
        if reduceMotion {
            step.wrappedValue = beats.count
            return
        }
        for (index, beat) in beats.enumerated() {
            try? await Task.sleep(for: .seconds(beat.pause))
            if Task.isCancelled { return }
            withAnimation(beat.animation) { step.wrappedValue = index + 1 }
        }
    }
}

// MARK: - The tour's board

/// A piece on a tour board, with an identity that follows it from square to square, so a move
/// slides rather than fades.
struct TourPiece: Identifiable, Equatable {
    let id: Int
    let kind: Piece.Kind
    let color: Piece.Color
    var square: Square
}

/// A position as the tour shows it: pieces that move, and are taken.
struct TourPosition: Equatable {
    var pieces: [TourPiece]

    init(fen: String) {
        let placed: [Piece] = Position(fen: fen)?.pieces ?? []
        pieces = placed.enumerated().map { index, piece in
            TourPiece(id: index, kind: piece.kind, color: piece.color, square: piece.square)
        }
    }

    /// The piece on `from` goes to `to`, taking whatever stood there.
    mutating func move(_ from: String, _ to: String) {
        let start = Square(from)
        let end = Square(to)
        pieces.removeAll { $0.square == end }
        if let index = pieces.firstIndex(where: { $0.square == start }) {
            pieces[index].square = end
        }
    }

    /// This position after the first `count` of `moves`.
    func after(_ moves: [(String, String)], count: Int) -> TourPosition {
        var position = self
        for move in moves.prefix(max(0, count)) { position.move(move.0, move.1) }
        return position
    }
}

/// Where a tour board's squares fall on screen: flat, or leaning back like a board on a table,
/// with the far rank narrower and closer together.
struct TourBoardGeometry {
    let width: CGFloat
    /// 0 is flat; 0.5 makes the far rank two thirds as wide as the near one.
    let tilt: CGFloat

    var height: CGFloat { tilt == 0 ? width : width * 0.58 }

    private func depth(_ v: CGFloat) -> CGFloat { 1 + tilt * (1 - v) }

    /// `u` runs left to right and `v` far to near, both 0 to 1.
    func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
        let z = depth(v)
        let x = width / 2 + (u - 0.5) * width / z
        if tilt == 0 { return CGPoint(x: x, y: v * width) }
        let y = height - height * (1 - 1 / z) * (1 + tilt) / tilt
        return CGPoint(x: x, y: y)
    }

    /// How large things are drawn on this row, against the near rank.
    func scale(row: Int) -> CGFloat { 1 / depth((CGFloat(row) + 0.5) / 8) }

    func center(_ square: Square) -> CGPoint {
        let row = 7 - square.rankIndex
        return point((CGFloat(square.fileIndex) + 0.5) / 8, (CGFloat(row) + 0.5) / 8)
    }

    func quad(file: Int, row: Int, inset: CGFloat = 0) -> Path {
        let u0 = CGFloat(file) / 8 - inset
        let u1 = CGFloat(file + 1) / 8 + inset
        let v0 = CGFloat(row) / 8 - inset
        let v1 = CGFloat(row + 1) / 8 + inset
        var path = Path()
        path.move(to: point(u0, v0))
        path.addLine(to: point(u1, v0))
        path.addLine(to: point(u1, v1))
        path.addLine(to: point(u0, v1))
        path.closeSubpath()
        return path
    }

    /// The whole board, reaching `inset` (in boards) past its edges.
    func outline(inset: CGFloat) -> Path {
        var path = Path()
        path.move(to: point(-inset, -inset))
        path.addLine(to: point(1 + inset, -inset))
        path.addLine(to: point(1 + inset, 1 + inset))
        path.addLine(to: point(-inset, 1 + inset))
        path.closeSubpath()
        return path
    }
}

/// The tour's board: wooden squares in a dark frame, the Gilded pieces standing on them, a move's
/// two squares lit, and a gold arrow that draws itself.
struct TourBoard: View {
    let position: TourPosition
    var width: CGFloat = 240
    var tilt: CGFloat = 0
    var lit: [Square] = []
    var arrow: (from: Square, to: Square)?
    /// How much of the arrow is drawn, 0 to 1.
    var arrowDrawn: CGFloat = 1
    /// Pieces in this list have not landed yet: they wait above the board, unseen.
    var waiting: Set<Int> = []
    var grey = false

    private var geometry: TourBoardGeometry { TourBoardGeometry(width: width, tilt: tilt) }

    var body: some View {
        let geometry = self.geometry
        ZStack(alignment: .topLeading) {
            squares(geometry)
            if let arrow {
                TourArrow(from: geometry.center(arrow.from), to: geometry.center(arrow.to),
                          head: width / 30)
                    .trim(from: 0, to: arrowDrawn)
                    .stroke(TourPalette.goldHigh, style: StrokeStyle(lineWidth: width / 90, lineCap: .round, lineJoin: .round))
                    .shadow(color: TourPalette.goldHigh.opacity(0.8), radius: 3)
            }
            pieces(geometry)
        }
        .frame(width: width, height: geometry.height)
        .saturation(grey ? 0 : 1)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private func squares(_ geometry: TourBoardGeometry) -> some View {
        Canvas { canvas, _ in
            canvas.fill(geometry.outline(inset: 0.035),
                        with: .linearGradient(Gradient(colors: [Color(hex: 0x3A3026), TourPalette.frame, Color(hex: 0x16120D)]),
                                              startPoint: .zero, endPoint: CGPoint(x: width, y: geometry.height)))
            canvas.stroke(geometry.outline(inset: 0.035), with: .color(TourPalette.goldHigh.opacity(0.18)), lineWidth: 1)
            for row in 0..<8 {
                for file in 0..<8 {
                    let light = (row + file) % 2 == 0
                    let path = geometry.quad(file: file, row: row, inset: 0.0008)
                    canvas.fill(path, with: .color(light ? TourPalette.light : TourPalette.dark))
                    let square = Square(file: file, rank: 7 - row)
                    if lit.contains(square) {
                        canvas.fill(path, with: .color(TourPalette.goldHigh.opacity(0.5)))
                    }
                }
            }
        }
        .frame(width: width, height: geometry.height)
    }

    private func pieces(_ geometry: TourBoardGeometry) -> some View {
        let square = width / 8
        return ZStack(alignment: .topLeading) {
            ForEach(position.pieces) { piece in
                let row = 7 - piece.square.rankIndex
                let scale = geometry.scale(row: row)
                let waits = waiting.contains(piece.id)
                PieceImage(piece: Piece(piece.kind, color: piece.color, square: piece.square),
                           theme: TourPalette.theme, size: square * scale, onBoard: true)
                    .position(geometry.center(piece.square))
                    .offset(y: waits ? -square * 2.5 : 0)
                    .opacity(waits ? 0 : 1)
                    .zIndex(Double(row * 8 + piece.square.fileIndex))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: width, height: geometry.height, alignment: .topLeading)
    }
}

/// A straight arrow with an open head, from one square's center to another's.
struct TourArrow: Shape {
    let from: CGPoint
    let to: CGPoint
    let head: CGFloat

    func path(in rect: CGRect) -> Path {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let tip = CGPoint(x: to.x - cos(angle) * head * 0.4, y: to.y - sin(angle) * head * 0.4)
        var path = Path()
        path.move(to: from)
        path.addLine(to: tip)
        path.move(to: CGPoint(x: tip.x - head * cos(angle - 0.5), y: tip.y - head * sin(angle - 0.5)))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x - head * cos(angle + 0.5), y: tip.y - head * sin(angle + 0.5)))
        return path
    }
}

/// A small pane of smoked glass with a hairline edge.
private struct TourGlass: ViewModifier {
    var radius: CGFloat = 16
    var tint: Color = TourPalette.glass
    var line: Color = TourPalette.glassLine

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(.ultraThinMaterial.opacity(0.35), in: shape)
            .background(tint, in: shape)
            .overlay { shape.strokeBorder(line, lineWidth: 1) }
    }
}

private extension View {
    func tourGlass(radius: CGFloat = 16, tint: Color = TourPalette.glass, line: Color = TourPalette.glassLine) -> some View {
        modifier(TourGlass(radius: radius, tint: tint, line: line))
    }

    /// Hidden and a little low until `shown`, then in place.
    func tourReveal(_ shown: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .scaleEffect(shown ? 1 : 0.96)
    }
}

/// The soft pool of light a board stands in.
private struct TourGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Ellipse()
            .fill(RadialGradient(colors: [TourPalette.goldHigh.opacity(0.42), TourPalette.gold.opacity(0.12), .clear],
                                 center: .center, startRadius: 0, endRadius: 150))
            .frame(width: 300, height: 90)
            .blur(radius: 6)
            .phaseAnimator(reduceMotion ? [false] : [false, true]) { glow, dim in
                glow.opacity(dim ? 0.6 : 1).scaleEffect(dim ? 0.94 : 1)
            } animation: { _ in .easeInOut(duration: 2.2) }
    }
}

// MARK: - 1 Welcome

/// The pieces drop onto a tilted board, back ranks first, then White plays e4.
struct TourHelloScene: View {
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let start = TourPosition(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    /// Back ranks, then pawns, each side left to right.
    private static let order: [Int] = start.pieces.sorted { a, b in
        let edge = { (piece: TourPiece) in piece.square.rankIndex == 0 || piece.square.rankIndex == 7 ? 0 : 1 }
        if edge(a) != edge(b) { return edge(a) < edge(b) }
        return a.square.fileIndex < b.square.fileIndex
    }.map(\.id)

    private var landed: Int { min(step, Self.order.count) }
    private var drop: Int { Self.order.count }

    private var beats: [TourBeat] {
        var beats = [TourBeat(0.25, .spring(response: 0.45, dampingFraction: 0.7))]
        beats += Array(repeating: TourBeat(0.045, .spring(response: 0.45, dampingFraction: 0.7)), count: drop - 1)
        beats.append(TourBeat(0.5, .easeInOut(duration: 0.7)))
        beats.append(TourBeat(1.0))
        return beats
    }

    var body: some View {
        let position = step > drop + 1 ? Self.start.after([("e2", "e4")], count: 1) : Self.start
        ZStack {
            TourGlow().offset(y: 92)
            TourBoard(position: position, width: 300, tilt: 0.5,
                      lit: step > drop + 1 ? [.e2, .e4] : [],
                      arrow: step > drop && step <= drop + 1 ? (from: Square.e2, to: Square.e4) : nil,
                      arrowDrawn: step > drop ? 1 : 0,
                      waiting: Set(Self.order.dropFirst(landed)))
        }
        .task { await TourBeat.play(beats, reduceMotion: reduceMotion, step: $step) }
    }
}

// MARK: - 2 Analyze

/// A grey screenshot is scanned, turns into a clean board, the evaluation fills, and the best
/// move draws itself and is played: Qxf7, mate.
struct TourAnalyzeScene: View {
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let position = TourPosition(fen: "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4")

    private let beats: [TourBeat] = [
        TourBeat(0.3),                                  // 1 the source chip
        TourBeat(0.4, .linear(duration: 1.4)),          // 2 the scan
        TourBeat(1.5, .easeInOut(duration: 0.7)),       // 3 read: the clean board
        TourBeat(0.5, .easeOut(duration: 1.1)),         // 4 the evaluation
        TourBeat(0.3, .easeInOut(duration: 0.8)),       // 5 the arrow
        TourBeat(0.6),                                  // 6 the best move
        TourBeat(1.4)                                   // 7 played
    ]

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                Image(systemName: "camera")
                Text("Screenshot from a game")
            }
            .font(.app(.footnote, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .tourGlass(radius: 14)
            .tourReveal(step >= 1)

            HStack(alignment: .center, spacing: 14) {
                evaluation
                ZStack {
                    photo
                        .opacity(step >= 3 ? 0 : 1)
                        .scaleEffect(step >= 3 ? 1.08 : 1)
                        .rotationEffect(.degrees(step >= 3 ? 0 : -6))
                    TourBoard(position: Self.position.after([("h5", "f7")], count: step >= 7 ? 1 : 0),
                              width: 232, lit: step >= 7 ? [.h5, .f7] : [],
                              arrow: step >= 5 && step < 7 ? (from: Square.h5, to: Square.f7) : nil,
                              arrowDrawn: step >= 5 ? 1 : 0)
                        .opacity(step >= 3 ? 1 : 0)
                        .scaleEffect(step >= 3 ? 1 : 0.92)
                }
                .frame(width: 240, height: 240)
            }

            HStack(spacing: 6) {
                Text("Best").foregroundStyle(TourPalette.goldHigh)
                Text("Qxf7#")
                Text("mate in 1").foregroundStyle(TourPalette.ink.opacity(0.4)).fontWeight(.medium)
            }
            .font(.app(.subheadline, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .tourGlass(radius: 14)
            .tourReveal(step >= 6)
        }
        .task { await TourBeat.play(beats, reduceMotion: reduceMotion, step: $step) }
    }

    /// The photo before it is read: grey, a white border, and a line of light sweeping down it.
    private var photo: some View {
        TourBoard(position: Self.position, width: 204, grey: true)
            .contrast(0.85)
            .blur(radius: 0.4)
            .padding(8)
            .background(Color(hex: 0xDDD6C8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .top) {
                LinearGradient(colors: [.clear, TourPalette.goldHigh, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 3)
                    .shadow(color: TourPalette.goldHigh.opacity(0.7), radius: 8)
                    .padding(.horizontal, 6)
                    .offset(y: step >= 2 ? 212 : 6)
                    .opacity(step == 2 ? 1 : 0)
            }
            .shadow(color: .black.opacity(0.6), radius: 20, y: 12)
    }

    /// White's share, filling from the middle once the board is read.
    private var evaluation: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(Color(hex: 0x1C1713))
            Capsule()
                .fill(LinearGradient(colors: [.white, TourPalette.ivory], startPoint: .top, endPoint: .bottom))
                .frame(height: step >= 4 ? 210 : 110)
        }
        .frame(width: 8, height: 220)
        .overlay { Capsule().strokeBorder(TourPalette.glassLine, lineWidth: 1) }
        .opacity(step >= 4 ? 1 : 0)
    }
}

// MARK: - 3 Leo

/// You ask a question, Leo's voice ripples while his answer writes itself, and the grades of
/// three moves come up.
struct TourLeoScene: View {
    @State private var step = 0
    @State private var typed = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let answer = "It loosens your king. Bring your last piece in first: Rae1, then h4 works."

    private var speaking: Bool { step == 2 && typed < Self.answer.count }

    var body: some View {
        VStack(spacing: 14) {
            bubble(label: "You", text: "Why is h4 bad here?", mine: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .tourReveal(step >= 1)
            orb
            TourWave(active: speaking)
                .frame(height: 26)
            bubble(label: "Leo", text: String(Self.answer.prefix(typed)), mine: false)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tourReveal(step >= 2)
            HStack(spacing: 6) {
                grade("14. Nf5 !! Brilliant", color: TourPalette.teal).tourReveal(step >= 3)
                grade("15. Qg4 Good", color: TourPalette.green).tourReveal(step >= 4)
                grade("16. h4 ? Mistake", color: TourPalette.coral).tourReveal(step >= 5)
            }
        }
        .padding(.horizontal, 4)
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            typed = Self.answer.count
            step = 5
            return
        }
        try? await Task.sleep(for: .seconds(0.3))
        withAnimation(.spring) { step = 1 }
        try? await Task.sleep(for: .seconds(0.9))
        withAnimation(.spring) { step = 2 }
        for count in 1...Self.answer.count {
            try? await Task.sleep(for: .milliseconds(32))
            if Task.isCancelled { return }
            typed = count
        }
        for next in 3...5 {
            try? await Task.sleep(for: .seconds(next == 3 ? 0.4 : 0.26))
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { step = next }
        }
    }

    private var orb: some View {
        ZStack {
            if speaking {
                TourRings()
            }
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF7E7C2), Color(hex: 0xC9A060), Color(hex: 0x5A4224)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 60))
                .shadow(color: TourPalette.gold.opacity(0.5), radius: 25)
            Glyph(name: Glyphs.coach, size: 40)
                .foregroundStyle(Color(hex: 0x2A1F12))
        }
        .frame(width: 92, height: 92)
    }

    private func bubble(label: String, text: String, mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.app(.caption2, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(TourPalette.gold)
            Text(text)
                .font(.app(.subheadline))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: mine ? nil : 38, alignment: .topLeading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(maxWidth: mine ? nil : .infinity, alignment: .leading)
        .tourGlass(radius: 16, tint: mine ? TourPalette.goldHigh.opacity(0.14) : TourPalette.glass,
                   line: mine ? TourPalette.goldHigh.opacity(0.25) : TourPalette.glassLine)
    }

    private func grade(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.4), lineWidth: 1) }
    }
}

/// Leo's voice: bars that move while he speaks and rest as dots when he stops.
private struct TourWave: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !active)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<22, id: \.self) { index in
                    Capsule()
                        .fill(TourPalette.gold)
                        .frame(width: 3, height: active ? Self.height(index, time) : 4)
                }
            }
            .animation(.easeOut(duration: 0.12), value: time)
        }
    }

    private static func height(_ index: Int, _ time: TimeInterval) -> CGFloat {
        let a = abs(sin(time * 5.5 + Double(index) * 0.7))
        let b = abs(sin(time * 9.1 + Double(index) * 1.9))
        return 4 + CGFloat(a * b) * 22
    }
}

/// Rings that spread from Leo while he talks.
private struct TourRings: View {
    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { index in
                    let phase = (time / 2.4 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(TourPalette.goldHigh.opacity(0.4), lineWidth: 1)
                        .scaleEffect(1.1 + phase * 0.6)
                        .opacity(1 - phase)
                }
            }
        }
    }
}

// MARK: - 4 Masterpiece

/// The Opera Game's last seven moves play out in a gilt frame, then again.
struct TourMasterpieceScene: View {
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Morphy v Duke Karl & Count Isouard, Paris 1858, after 13...Rxd7.
    private static let start = TourPosition(fen: "4kb1r/p2rqppp/5n2/1B2p1B1/4P3/1Q6/PPP2PPP/2K4R w k - 0 14")
    private static let moves: [(String, String)] = [
        ("h1", "d1"), ("e7", "e6"), ("b5", "d7"), ("f6", "d7"), ("b3", "b8"), ("d7", "b8"), ("d1", "d8")
    ]
    private static let notation = ["14. Rd1", "Qe6", "15. Bxd7+", "Nxd7", "16. Qb8+", "Nxb8", "17. Rd8#"]

    private var played: Int { min(step, Self.moves.count) }
    private var mated: Bool { step > Self.moves.count }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 6) {
                ForEach(Array(Self.notation.enumerated()), id: \.offset) { index, move in
                    Text(move)
                        .foregroundStyle(index == played - 1 ? TourPalette.goldHigh : TourPalette.ink.opacity(0.36))
                }
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            ZStack(alignment: .bottom) {
                TourBoard(position: Self.start.after(Self.moves, count: played), width: 228,
                          lit: lastMove)
                    .overlay {
                        Text("Checkmate")
                            .font(.system(size: 30, weight: .medium, design: .serif).italic())
                            .foregroundStyle(TourPalette.goldHigh)
                            .shadow(color: TourPalette.goldHigh.opacity(0.8), radius: 12)
                            .opacity(mated ? 1 : 0)
                            .scaleEffect(mated ? 1 : 0.8)
                    }
                    .padding(14)
                    .background(gilt, in: RoundedRectangle(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(TourPalette.goldHigh.opacity(0.25), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.8), radius: 24, y: 18)
                Text("THE OPERA GAME · MORPHY · 1858")
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .tracking(0.9)
                    .foregroundStyle(Color(hex: 0x2A1D0C))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(LinearGradient(colors: [Color(hex: 0xE9CF93), Color(hex: 0xB48C4C)],
                                               startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 3))
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
                    .offset(y: 16)
            }
        }
        .task { await loop() }
    }

    private var lastMove: [Square] {
        guard played > 0 else { return [] }
        let move = Self.moves[played - 1]
        return [Square(move.0), Square(move.1)]
    }

    private var gilt: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x6B5233), Color(hex: 0x3A2C1B), Color(hex: 0x7A5F3A), Color(hex: 0x3A2C1B)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func loop() async {
        let beats = Array(repeating: TourBeat(0.9, .spring(response: 0.6, dampingFraction: 0.85)), count: Self.moves.count)
            + [TourBeat(0.3, .spring(response: 0.5, dampingFraction: 0.6))]
        while !Task.isCancelled {
            await TourBeat.play(beats, reduceMotion: reduceMotion, step: $step)
            if reduceMotion { return }
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.5)) { step = 0 }
        }
    }
}

// MARK: - 5 Today's Move

/// The calendar turns to today, the puzzle is solved with a rook on the back rank, then the
/// world's score fills and the streak ticks up.
struct TourTodayScene: View {
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let puzzle = TourPosition(fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1")

    private let beats: [TourBeat] = [
        TourBeat(0.3, .easeInOut(duration: 0.8)),        // 1 the page turns
        TourBeat(1.0, .easeInOut(duration: 0.8)),        // 2 the arrow
        TourBeat(0.9, .spring(response: 0.6, dampingFraction: 0.85)), // 3 Rd8#
        TourBeat(0.6, .spring(response: 0.45, dampingFraction: 0.6)), // 4 solved
        TourBeat(0.5),                                   // 5 the world
        TourBeat(0.2, .easeOut(duration: 1.3)),          // 6 its bar
        TourBeat(0.6, .spring(response: 0.35, dampingFraction: 0.5))  // 7 the streak
    ]

    private var day: Date { step >= 1 ? .now : Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                TourBoard(position: Self.puzzle.after([("d1", "d8")], count: step >= 3 ? 1 : 0), width: 214,
                          lit: step >= 3 ? [.d1, .d8] : [],
                          arrow: step >= 2 && step < 3 ? (from: Square.d1, to: Square.d8) : nil,
                          arrowDrawn: step >= 2 ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0B2015))
                    .frame(width: 62, height: 62)
                    .background(TourPalette.green.opacity(0.92), in: Circle())
                    .shadow(color: TourPalette.green.opacity(0.6), radius: 20)
                    .scaleEffect(step >= 4 ? 1 : 0.4)
                    .opacity(step >= 4 ? 1 : 0)
            }
            .overlay(alignment: .topLeading) { calendar.offset(x: -30, y: -28) }
            .overlay(alignment: .topTrailing) { streak.offset(x: 32, y: -22) }

            VStack(spacing: 6) {
                HStack {
                    Text("How the world did")
                    Spacer()
                    Text("64% found it").fontWeight(.bold).foregroundStyle(TourPalette.ink)
                }
                .font(.app(.caption))
                .foregroundStyle(TourPalette.ink.opacity(0.64))
                TourBar(fill: step >= 6 ? 0.64 : 0)
            }
            .frame(width: 236)
            .tourReveal(step >= 5)
        }
        .padding(.top, 20)
        .task { await TourBeat.play(beats, reduceMotion: reduceMotion, step: $step) }
    }

    private var calendar: some View {
        VStack(spacing: 0) {
            Text(day, format: .dateTime.month(.abbreviated))
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(TourPalette.coral)
            Text(day, format: .dateTime.day())
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(TourPalette.onIvory)
                .contentTransition(.numericText())
                .padding(.vertical, 2)
        }
        .frame(width: 62)
        .background(Color(hex: 0xF7F0E2))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.6), radius: 13, y: 8)
        .rotation3DEffect(.degrees(step >= 1 ? 360 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top)
        .rotationEffect(.degrees(-8))
    }

    private var streak: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill").foregroundStyle(TourPalette.flame)
            Text("\(step >= 7 ? 7 : 6)")
                .contentTransition(.numericText(countsDown: false))
                .scaleEffect(step >= 7 ? 1.15 : 1)
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .tourGlass(radius: 14)
    }
}

/// A thin track and a gold fill.
private struct TourBar: View {
    let fill: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(TourPalette.ink.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [TourPalette.gold, TourPalette.goldHigh], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * fill)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - 6 Rivals

/// What the 1600s answer to 1. e4 fills in from their real games, the favourite lights, and then
/// a grudge shows up.
struct TourRivalsScene: View {
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// An example of a crowd's answers, as shares of its games.
    private static let answers: [(move: String, share: Int)] = [("c5", 38), ("e5", 27), ("e6", 12), ("c6", 9)]

    private let beats: [TourBeat] = [
        TourBeat(0.3),
        TourBeat(0.4, .easeOut(duration: 1)), TourBeat(0.18, .easeOut(duration: 1)),
        TourBeat(0.18, .easeOut(duration: 1)), TourBeat(0.18, .easeOut(duration: 1)),
        TourBeat(0.9),
        TourBeat(0.5)
    ]

    var body: some View {
        VStack(spacing: 12) {
            crowd.tourReveal(step >= 1)
            grudge.tourReveal(step >= 7)
        }
        .frame(width: 292)
        .task { await TourBeat.play(beats, reduceMotion: reduceMotion, step: $step) }
    }

    private var crowd: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("The 1600s answer 1. e4").font(.app(.subheadline, weight: .semibold))
                Text("From real games played at their rating")
                    .font(.app(.caption))
                    .foregroundStyle(TourPalette.ink.opacity(0.4))
            }
            .padding(.bottom, 4)
            ForEach(Array(Self.answers.enumerated()), id: \.offset) { index, answer in
                let picked = index == 0 && step >= 6
                HStack(spacing: 10) {
                    Text(answer.move)
                        .frame(width: 30, alignment: .leading)
                        .foregroundStyle(picked ? TourPalette.goldHigh : TourPalette.ink)
                    TourBar(fill: step >= index + 2 ? CGFloat(answer.share) / 45 : 0)
                        .overlay { if picked { Capsule().strokeBorder(TourPalette.goldHigh.opacity(0.6), lineWidth: 1) } }
                    Text("\(answer.share)%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                        .foregroundStyle(TourPalette.ink.opacity(0.4))
                }
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
            }
        }
        .padding(14)
        .tourGlass(radius: 20)
    }

    private var grudge: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 26))
                .foregroundStyle(TourPalette.coral)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { flame, high in
                    flame.scaleEffect(x: high ? 0.94 : 1, y: high ? 1.1 : 1, anchor: .bottom)
                } animation: { _ in .easeInOut(duration: 0.55) }
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("The 1600s hold a grudge").font(.app(.subheadline, weight: .semibold))
                Text("They've taken your queen three times. Win with it for bonus XP.")
                    .font(.app(.caption))
                    .foregroundStyle(TourPalette.ink.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .tourGlass(radius: 20, tint: TourPalette.coral.opacity(0.12), line: TourPalette.coral.opacity(0.3))
    }
}

// MARK: - 7 Your pieces

/// A named knight turns slowly while gold seams appear on it and its record counts up.
struct TourPiecesScene: View {
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let beats: [TourBeat] = [
        TourBeat(0.4, .easeInOut(duration: 0.8)),   // 1 first seam
        TourBeat(0.5),                              // 2 the name
        TourBeat(0.4, .easeOut(duration: 1.0)),     // 3 the record
        TourBeat(0.5, .easeInOut(duration: 0.8)),   // 4 second seam
        TourBeat(0.3, .easeOut(duration: 1.2))      // 5 the experience bar
    ]

    private var heirloom: Heirloom {
        Heirloom(seams: step >= 4 ? 2 : (step >= 1 ? 1 : 0), notches: step >= 3 ? 3 : 0,
                 patina: step >= 3 ? 0.4 : 0.1, seed: 6)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                TourGlow().offset(y: 70).scaleEffect(0.7)
                PieceImage(piece: Piece(.knight, color: .white, square: .g1), theme: TourPalette.theme,
                           size: 170, heirloom: heirloom)
                    .shadow(color: .black.opacity(0.6), radius: 20, y: 18)
                    .phaseAnimator(reduceMotion ? [false] : [false, true]) { knight, turned in
                        knight
                            .rotation3DEffect(.degrees(turned ? 14 : -6), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                            .offset(y: turned ? -4 : 0)
                    } animation: { _ in .easeInOut(duration: 3) }
            }
            .frame(height: 190)

            VStack(spacing: 3) {
                Text("Bucephalus")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(TourPalette.goldHigh)
                Text("Your g1 knight · came back twice")
                    .font(.app(.caption))
                    .foregroundStyle(TourPalette.ink.opacity(0.4))
            }
            .tourReveal(step >= 2)

            HStack(spacing: 18) {
                stat(step >= 3 ? 23 : 0, "games")
                stat(step >= 3 ? 41 : 0, "captures")
                stat(step >= 4 ? 2 : 0, "comebacks")
            }
            .tourReveal(step >= 3)

            TourBar(fill: step >= 5 ? 0.72 : 0)
                .frame(width: 200)
                .tourReveal(step >= 3)
        }
        .task { await TourBeat.play(beats, reduceMotion: reduceMotion, step: $step) }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(label)
                .font(.app(.caption))
                .foregroundStyle(TourPalette.ink.opacity(0.4))
        }
    }
}

// MARK: - A page

/// One tour page: its scene on the stage, then the eyebrow, the two-part title and a line.
struct TourPageView: View {
    let page: TourPage
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The height each scene is drawn for; smaller phones scale it down to fit.
    private static let sceneHeight: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GeometryReader { geo in
                let scale = min(1, geo.size.height / Self.sceneHeight, geo.size.width / 330)
                page.scene
                    .frame(width: 330, height: Self.sceneHeight)
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(page.eyebrow.uppercased())
                    .font(.app(.caption2, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(TourPalette.gold)
                title
                Text(page.text)
                    .font(.app(.subheadline))
                    .foregroundStyle(TourPalette.ink.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .accessibilityElement(children: .combine)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.1)) { shown = true }
        }
    }

    private var title: some View {
        let words = page.title
        let size: CGFloat = page == .hello ? 44 : 34
        return (Text(words.plain + " ")
            + Text(words.gold).italic().foregroundColor(TourPalette.gold))
            .font(.system(size: size, weight: .medium, design: .serif))
            .foregroundStyle(TourPalette.ink)
            .lineSpacing(-4)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}
