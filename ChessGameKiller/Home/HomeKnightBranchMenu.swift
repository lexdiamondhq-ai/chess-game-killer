import SwiftUI

/// What the gold Play knight offers (a tap since 2026-11-24, Analyze has its own button) (Alex, 2026-11-14): four round gold
/// doors that grow out toward the middle of the screen on living gold vines, each leaving the
/// knight's orb from its own spot (Alex, 2026-11-15). Rooms has its own tab, so it is not repeated.
enum HomeKnightDoor: String, CaseIterable, Identifiable {
    case quickPlay, todaysMove, puzzles, friend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickPlay: return "Quick play"
        case .todaysMove: return "Today's Move"
        case .puzzles: return "Puzzles"
        case .friend: return "A friend"
        }
    }

    /// The doors shown: A friend only when the app can reach other players.
    static func list(online: Bool) -> [HomeKnightDoor] {
        online ? allCases : allCases.filter { $0 != .friend }
    }

    /// Where each door sits, in points from the knight's center, on a 402-point-wide screen.
    /// They fan from low on the left up to just over the knight, like the paw-print trails.
    var spot: CGSize {
        switch self {
        case .quickPlay: return CGSize(width: -254, height: -82)
        case .todaysMove: return CGSize(width: -208, height: -199)
        case .puzzles: return CGSize(width: -118, height: -279)
        case .friend: return CGSize(width: -10, height: -309)
        }
    }
}

/// The ironwork menu itself, laid over the whole Home screen. `knight` is the gold knight's center
/// in this view's space.
struct HomeKnightBranchMenu: View {
    let knight: CGPoint
    let doors: [HomeKnightDoor]
    let pick: (HomeKnightDoor) -> Void
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("haptics") private var hapticsOn = true
    @State private var grown = false
    @State private var budded = 0

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, geo.size.width / 402)
            ZStack(alignment: .topLeading) {
                // The room dims and the knight glows, as in the picture Alex picked.
                Color(hex: 0x080502).opacity(0.72)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xE6C06A).opacity(0.22), Color(hex: 0xE6C06A).opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 140))
                    .frame(width: 280, height: 280)
                    .position(knight)
                    .allowsHitTesting(false)
                ForEach(Array(doors.enumerated()), id: \.element) { index, door in
                    let end = CGPoint(x: knight.x + door.spot.width * scale, y: knight.y + door.spot.height * scale)
                    let delay = reduceMotion ? 0 : Double(index) * 0.07
                    // Each vine leaves the orb from its own spot and grows out to its door
                    // (Alex, 2026-11-15: "coming out of the orb separately ... like actual vines").
                    LivingVineView(vine: LivingVine(index: index, knight: knight, to: end, scale: scale),
                                   progress: grown ? 1 : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.5).delay(delay), value: grown)
                        .allowsHitTesting(false)
                    doorButton(door)
                        .scaleEffect(grown ? 1 : 0.2, anchor: .center)
                        .opacity(grown ? 1 : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.7).delay(delay + 0.3), value: grown)
                        .position(end)
                }
                // The knight stays lit above the dimmed room, over the vines' roots; a tap on it
                // folds them away.
                knightCoin
                    .position(knight)
                    .onTapGesture(perform: close)
            }
        }
        .onAppear {
            grown = true
            budded += 1
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: budded) { (_: Int, _: Int) -> Bool in hapticsOn }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, close)
    }

    private var knightCoin: some View {
        VStack(spacing: 1) {
            AnalyzeKnightGlyph()
                .frame(width: 23, height: 28)
            Text("Play")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color(hex: 0x2A1C08))
        .frame(width: HomeAuroraTabBar.coin, height: HomeAuroraTabBar.coin)
        .background {
            Circle().fill(RadialGradient(stops: [.init(color: Color(hex: 0xFFF1CC), location: 0),
                                                 .init(color: Color(hex: 0xE8C27A), location: 0.45),
                                                 .init(color: Color(hex: 0xA66F25), location: 1)],
                                         center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: 37))
        }
        .overlay(Circle().strokeBorder(Color(hex: 0xF6DC93).opacity(0.8), lineWidth: 1.5).padding(-3))
        .shadow(color: Color(hex: 0xE6C06A).opacity(0.45), radius: 16)
        .contentShape(Circle())
        .accessibilityLabel("Close")
        .accessibilityAddTraits(.isButton)
    }

    private func doorButton(_ door: HomeKnightDoor) -> some View {
        Button { pick(door) } label: {
            VStack(spacing: 6) {
                icon(door)
                    .foregroundStyle(Color(hex: 0xE6C06A))
                    .frame(width: 54, height: 54)
                    .background {
                        Circle().fill(RadialGradient(colors: [Color(hex: 0x3A2A16), Color(hex: 0x140D06)],
                                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 40))
                    }
                    .overlay(Circle().strokeBorder(Color(hex: 0xE6C06A), lineWidth: 1.7))
                    .overlay(Circle().inset(by: 4).strokeBorder(Color(hex: 0xE6C06A).opacity(0.25), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                Text(door.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xF3E7CC))
                    .shadow(color: .black.opacity(0.9), radius: 3)
                    .fixedSize()
            }
            // The label hangs under the coin; the coin is what sits on the branch's end.
            .padding(.top, 26)
        }
        .buttonStyle(HomeStagePress())
        .accessibilityLabel(door.title)
    }

    @ViewBuilder
    private func icon(_ door: HomeKnightDoor) -> some View {
        switch door {
        case .quickPlay: Image(systemName: "bolt.fill").font(.system(size: 22, weight: .bold))
        case .todaysMove: Glyph(name: Glyphs.today, size: 26)
        case .puzzles: Glyph(name: Glyphs.puzzles, size: 26)
        case .friend: Glyph(name: Glyphs.challenge, size: 26)
        }
    }
}

/// One living vine: it leaves the orb's rim at its own angle, heading outward, then bends to its
/// door. Thick at the root and thin at the tip, gently wavy, with leaves on short stalks and two
/// coiled tendrils (Alex picked "Living vines", 2026-11-15).
struct LivingVine: Equatable {
    /// Where on the orb's rim each vine starts, in degrees (0 is right, 90 is down): spread from
    /// due left round to straight up, so no two leave from the same place.
    static let startAngles: [Double] = [172, 207, 240, 272]
    static let samples = 120

    let points: [CGPoint]
    let scale: CGFloat

    init(index: Int, knight: CGPoint, to door: CGPoint, scale: CGFloat, orbRadius: CGFloat = 32) {
        self.scale = scale
        let degrees: Double = Self.startAngles[min(max(index, 0), Self.startAngles.count - 1)]
        let angle = CGFloat(degrees * Double.pi / 180)
        let rim: CGFloat = orbRadius * 0.95
        let start = CGPoint(x: knight.x + cos(angle) * rim, y: knight.y + sin(angle) * rim)
        let toDoor = atan2(door.y - start.y, door.x - start.x)
        // It stops just inside the door's coin, which sits on top of it.
        let end = CGPoint(x: door.x - cos(toDoor) * 22 * scale, y: door.y - sin(toDoor) * 22 * scale)
        let dx = end.x - start.x, dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        let nx = -dy / length, ny = dx / length
        let c1 = CGPoint(x: start.x + cos(angle) * length * 0.35, y: start.y + sin(angle) * length * 0.35)
        let c2 = CGPoint(x: start.x + dx * 0.7, y: start.y + dy * 0.7)
        let wave: CGFloat = 5.3 * scale
        let phase: Double = Double(index) * 1.3
        var sampled: [CGPoint] = []
        for k in 0...Self.samples {
            let u: CGFloat = CGFloat(k) / CGFloat(Self.samples)
            let v: CGFloat = 1 - u
            let a: CGFloat = v * v * v
            let b: CGFloat = 3 * v * v * u
            let c: CGFloat = 3 * v * u * u
            let d: CGFloat = u * u * u
            let x: CGFloat = a * start.x + b * c1.x + c * c2.x + d * end.x
            let y: CGFloat = a * start.y + b * c1.y + c * c2.y + d * end.y
            let ud = Double(u)
            let sway: Double = sin(ud * Double.pi * 2.4 + phase) * sin(ud * Double.pi)
            let w: CGFloat = wave * CGFloat(sway)
            sampled.append(CGPoint(x: x + nx * w, y: y + ny * w))
        }
        points = sampled
    }

    func tangent(_ k: Int) -> CGVector {
        let a = points[max(0, k - 1)], b = points[min(points.count - 1, k + 1)]
        let length = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
        return CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
    }

    /// Leaves: where along the vine (a sample), which side, and how long.
    var leaves: [(k: Int, side: CGFloat, size: CGFloat)] {
        [(k: 22, side: -1, size: 12.7 * scale), (k: 46, side: 1, size: 12.7 * scale),
         (k: 70, side: -1, size: 10 * scale), (k: 94, side: 1, size: 10 * scale)]
    }

    /// Tendrils: where they leave the vine, which way they coil, and how big.
    var tendrils: [(k: Int, side: CGFloat, radius: CGFloat)] {
        [(k: 34, side: 1, radius: 3 * scale), (k: 82, side: -1, radius: 2.3 * scale)]
    }

    /// How grown a leaf or tendril at sample `k` is, when the vine has grown to `progress`.
    func bloom(_ k: Int, progress: CGFloat) -> CGFloat {
        let u = CGFloat(k) / CGFloat(Self.samples)
        return min(max((progress - u) * 6, 0), 1)
    }

    /// The tapered stem, as far as it has grown.
    func stem(progress: CGFloat) -> Path {
        let last = Int((CGFloat(Self.samples) * min(max(progress, 0), 1)).rounded(.down))
        guard last >= 1 else { return Path() }
        var left: [CGPoint] = [], right: [CGPoint] = []
        let w0 = 6.3 * scale, w1 = 1.3 * scale
        for k in 0...last {
            let t = tangent(k), u = CGFloat(k) / CGFloat(Self.samples)
            let taper: CGFloat = pow(u, 0.8)
            let half: CGFloat = (w0 + (w1 - w0) * taper) / 2
            let p = points[k]
            left.append(CGPoint(x: p.x - t.dy * half, y: p.y + t.dx * half))
            right.append(CGPoint(x: p.x + t.dy * half, y: p.y - t.dx * half))
        }
        var path = Path()
        path.addLines(left + right.reversed())
        path.closeSubpath()
        return path
    }

    private func leafBase(_ k: Int, side: CGFloat) -> (stalkEnd: CGPoint, angle: CGFloat) {
        let p = points[k], t = tangent(k)
        let nx = -t.dy * side, ny = t.dx * side
        let end = CGPoint(x: p.x + nx * 3.3 * scale, y: p.y + ny * 3.3 * scale)
        let ay: CGFloat = ny * 0.8 + t.dy * 0.6
        let ax: CGFloat = nx * 0.8 + t.dx * 0.6
        return (end, atan2(ay, ax))
    }

    /// The leaves' blades, pointed at the tip.
    func leafBlades(progress: CGFloat) -> Path {
        var path = Path()
        for leaf in leaves {
            let grow = bloom(leaf.k, progress: progress)
            guard grow > 0 else { continue }
            let s = leaf.size * grow
            let (base, angle) = leafBase(leaf.k, side: leaf.side)
            var blade = Path()
            blade.move(to: .zero)
            blade.addCurve(to: CGPoint(x: s, y: 0), control1: CGPoint(x: s * 0.25, y: -s * 0.45), control2: CGPoint(x: s * 0.75, y: -s * 0.42))
            blade.addCurve(to: .zero, control1: CGPoint(x: s * 0.75, y: s * 0.38), control2: CGPoint(x: s * 0.25, y: s * 0.42))
            blade.closeSubpath()
            path.addPath(blade, transform: CGAffineTransform(translationX: base.x, y: base.y).rotated(by: angle))
        }
        return path
    }

    /// The leaves' stalks, midribs and two side veins.
    func leafVeins(progress: CGFloat) -> Path {
        var path = Path()
        for leaf in leaves {
            let grow = bloom(leaf.k, progress: progress)
            guard grow > 0 else { continue }
            let s = leaf.size * grow
            let (base, angle) = leafBase(leaf.k, side: leaf.side)
            path.move(to: points[leaf.k])
            path.addLine(to: base)
            var veins = Path()
            veins.move(to: CGPoint(x: s * 0.05, y: 0)); veins.addLine(to: CGPoint(x: s * 0.9, y: 0))
            veins.move(to: CGPoint(x: s * 0.4, y: 0)); veins.addLine(to: CGPoint(x: s * 0.58, y: -s * 0.2))
            veins.move(to: CGPoint(x: s * 0.55, y: 0)); veins.addLine(to: CGPoint(x: s * 0.72, y: s * 0.17))
            path.addPath(veins, transform: CGAffineTransform(translationX: base.x, y: base.y).rotated(by: angle))
        }
        return path
    }

    /// The tendrils, each a coil that winds in on itself.
    func tendrilCoils(progress: CGFloat) -> Path {
        var path = Path()
        for tendril in tendrils {
            let grow = bloom(tendril.k, progress: progress)
            guard grow > 0 else { continue }
            let p = points[tendril.k], t = tangent(tendril.k), r = tendril.radius, side = tendril.side
            let nx = -t.dy * side, ny = t.dx * side
            let cx: CGFloat = p.x + nx * r * 1.6 + t.dx * r * 0.6
            let cy: CGFloat = p.y + ny * r * 1.6 + t.dy * r * 0.6
            let center = CGPoint(x: cx, y: cy)
            let a0 = atan2(p.y - center.y, p.x - center.x)
            let reach = hypot(p.x - center.x, p.y - center.y)
            path.move(to: p)
            let steps = Int(50 * grow)
            guard steps > 0 else { continue }
            for i in 1...steps {
                let f = CGFloat(i) / 50
                let a: CGFloat = a0 + side * f * CGFloat.pi * 3.2
                let rr = reach * (1 - f * 0.85)
                path.addLine(to: CGPoint(x: center.x + cos(a) * rr, y: center.y + sin(a) * rr))
            }
        }
        return path
    }
}

/// Draws one vine grown to `progress`, so it can grow out of the orb in an animation.
struct LivingVineView: View, Animatable {
    let vine: LivingVine
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let ink = Color(hex: 0x2A1C08)

    var body: some View {
        let s = vine.scale
        Canvas { gc, _ in
            let stem = vine.stem(progress: progress)
            let tendrils = vine.tendrilCoils(progress: progress)
            let veins = vine.leafVeins(progress: progress)
            let blades = vine.leafBlades(progress: progress)
            let round = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
            gc.stroke(tendrils, with: .color(Self.ink.opacity(0.55)), style: round.with(width: 1.7 * s))
            gc.stroke(tendrils, with: .color(Color(hex: 0xE2B963)), style: round.with(width: 0.8 * s))
            gc.stroke(stem, with: .color(Self.ink), style: round.with(width: 1.4 * s))
            gc.fill(stem, with: .linearGradient(Gradient(colors: [Color(hex: 0xF6DC93), Color(hex: 0xC99436), Color(hex: 0xF0CF7A)]),
                                                 startPoint: vine.points.first ?? .zero, endPoint: vine.points.last ?? .zero))
            gc.stroke(blades, with: .color(Self.ink), style: round.with(width: 1.1 * s))
            gc.fill(blades, with: .color(Color(hex: 0xE2B963)))
            gc.stroke(veins, with: .color(Color(hex: 0x6B4A18)), style: round.with(width: 0.6 * s))
        }
    }
}

private extension StrokeStyle {
    func with(width: CGFloat) -> StrokeStyle {
        var copy = self
        copy.lineWidth = width
        return copy
    }
}
