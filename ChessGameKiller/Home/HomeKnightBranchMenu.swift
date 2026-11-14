import SwiftUI

/// What a press and hold on the gold Analyze knight offers (Alex, 2026-11-14): four round gold
/// doors that grow out toward the middle of the screen on gilded ironwork branches, like a castle
/// gate's scrollwork, each tied back to the knight. Rooms has its own tab, so it is not repeated.
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
                // The knight stays lit above the dimmed room; a tap on it folds the branches away.
                knightCoin
                    .position(knight)
                    .onTapGesture(perform: close)
                ForEach(Array(doors.enumerated()), id: \.element) { index, door in
                    let end = CGPoint(x: knight.x + door.spot.width * scale, y: knight.y + door.spot.height * scale)
                    let delay = reduceMotion ? 0 : Double(index) * 0.07
                    GildedBranch(from: knight, to: end, scale: scale)
                        .trim(from: 0, to: grown ? 1 : 0)
                        .stroke(Color(hex: 0x2A1C08).opacity(0.7), style: StrokeStyle(lineWidth: 4.5 * scale, lineCap: .round))
                        .overlay {
                            GildedBranch(from: knight, to: end, scale: scale)
                                .trim(from: 0, to: grown ? 1 : 0)
                                .stroke(Self.gold, style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))
                        }
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.42).delay(delay), value: grown)
                        .allowsHitTesting(false)
                    GildedCurls(from: knight, to: end, scale: scale)
                        .opacity(grown ? 1 : 0)
                        .scaleEffect(grown ? 1 : 0.6, anchor: UnitPoint(x: knight.x / max(geo.size.width, 1),
                                                                         y: knight.y / max(geo.size.height, 1)))
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.3).delay(delay + 0.22), value: grown)
                        .allowsHitTesting(false)
                    doorButton(door)
                        .scaleEffect(grown ? 1 : 0.2, anchor: .center)
                        .opacity(grown ? 1 : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.7).delay(delay + 0.3), value: grown)
                        .position(end)
                }
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
                .frame(width: 25, height: 30)
            Text("Analyze")
                .font(.system(size: 9.5, weight: .semibold))
        }
        .foregroundStyle(Color(hex: 0x2A1C08))
        .frame(width: 64, height: 64)
        .background {
            Circle().fill(RadialGradient(stops: [.init(color: Color(hex: 0xFFF1CC), location: 0),
                                                 .init(color: Color(hex: 0xE8C27A), location: 0.45),
                                                 .init(color: Color(hex: 0xA66F25), location: 1)],
                                         center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: 40))
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

    static let gold = LinearGradient(colors: [Color(hex: 0xF6DC93), Color(hex: 0xC99436), Color(hex: 0xF0CF7A)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// One gilded branch's spine: it leaves the knight's shoulder, sweeps out, and bends back in
/// to its door.
struct GildedBranch: Shape {
    let from: CGPoint
    let to: CGPoint
    var scale: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let c = Self.controls(from: from, to: to, scale: scale)
        var p = Path()
        p.move(to: c[0])
        p.addCurve(to: c[3], control1: c[1], control2: c[2])
        return p
    }

    /// The curve's four points, shared with its curls and leaves.
    static func controls(from: CGPoint, to: CGPoint, scale: CGFloat) -> [CGPoint] {
        let start = CGPoint(x: from.x - 13 * scale, y: from.y - 23 * scale)
        let dx = to.x - start.x, dy = to.y - start.y
        let length = max(hypot(dx, dy), 1)
        let nx = -dy / length, ny = dx / length
        let bend = length * 0.22
        return [start,
                CGPoint(x: start.x + dx * 0.25 + nx * bend, y: start.y + dy * 0.25 + ny * bend),
                CGPoint(x: start.x + dx * 0.75 - nx * bend * 0.6, y: start.y + dy * 0.75 - ny * bend * 0.6),
                to]
    }

    static func point(_ c: [CGPoint], _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, d = 3 * u * t * t, e = t * t * t
        return CGPoint(x: a * c[0].x + b * c[1].x + d * c[2].x + e * c[3].x,
                       y: a * c[0].y + b * c[1].y + d * c[2].y + e * c[3].y)
    }

    static func tangent(_ c: [CGPoint], _ t: CGFloat) -> CGVector {
        let a = point(c, max(0, t - 0.005)), b = point(c, min(1, t + 0.005))
        let length = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
        return CGVector(dx: (b.x - a.x) / length, dy: (b.y - a.y) / length)
    }
}

/// The scrollwork on a branch: four small curling tendrils, side to side, each with a leaf.
struct GildedCurls: View {
    let from: CGPoint
    let to: CGPoint
    var scale: CGFloat = 1

    var body: some View {
        Canvas { gc, _ in
            let c = GildedBranch.controls(from: from, to: to, scale: scale)
            let gold = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(hex: 0xF6DC93), Color(hex: 0xC99436), Color(hex: 0xF0CF7A)]),
                startPoint: c[0], endPoint: c[3])
            for (k, u) in [0.22, 0.42, 0.62, 0.8].enumerated() {
                let side: CGFloat = k % 2 == 0 ? -1 : 1
                let p = GildedBranch.point(c, u)
                let d = GildedBranch.tangent(c, u)
                let tendril = curl(at: p, along: d, side: side, length: 23 * scale)
                gc.stroke(tendril, with: .color(Color(hex: 0x2A1C08).opacity(0.6)),
                          style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))
                gc.stroke(tendril, with: gold, style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round))
                gc.fill(leaf(at: p, along: d, side: -side, size: 11 * scale), with: .color(Color(hex: 0xC99A3E)))
            }
        }
    }

    /// A tendril that leaves the branch to one side and rolls up into a small spiral.
    private func curl(at p: CGPoint, along d: CGVector, side: CGFloat, length: CGFloat) -> Path {
        let nx = -d.dy * side, ny = d.dx * side
        let base = atan2(ny, nx)
        var path = Path()
        for i in 0...30 {
            let t = CGFloat(i) / 30
            let reach = sin(min(t * 2, 1) * .pi / 2)
            var x = p.x + nx * length * 0.5 * reach + d.dx * length * 0.4 * t
            var y = p.y + ny * length * 0.5 * reach + d.dy * length * 0.4 * t
            if t > 0.5 {
                let a = t * .pi * 1.6
                let r = length * (1 - t * 0.7) * 0.35 * (t - 0.5) * 2
                x += cos(a * side + base) * r
                y += sin(a * side + base) * r
            }
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }

    /// A small almond leaf on the branch, leaning forward.
    private func leaf(at p: CGPoint, along d: CGVector, side: CGFloat, size: CGFloat) -> Path {
        let nx = -d.dy * side, ny = d.dx * side
        let angle = atan2(ny + d.dy * 0.6, nx + d.dx * 0.6)
        var leaf = Path()
        leaf.move(to: .zero)
        leaf.addQuadCurve(to: CGPoint(x: size, y: 0), control: CGPoint(x: size * 0.5, y: -size * 0.35))
        leaf.addQuadCurve(to: .zero, control: CGPoint(x: size * 0.5, y: size * 0.35))
        leaf.closeSubpath()
        return leaf.applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
    }
}
