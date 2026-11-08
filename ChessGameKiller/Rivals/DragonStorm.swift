import SwiftUI

/// The Dragonlord's storm behind the board (Alex, 2026-11-08: "when playing the Dragon Lord,
/// see the rain and lightning in the background"). It lies over the look's backdrop and under
/// the board: a darker sky at the top, rain falling in three depths, and now and then lightning
/// far off in the clouds, a forked bolt with a cold flash that fades. The board stays clear:
/// the flash is strongest at the top and the bolts never reach past the upper part of the screen.
/// Reduce Motion keeps the sky and a still veil of rain, with no flashes.
struct DragonStorm: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var still: Bool { reduceMotion || Welcome.isUnderTest }

    var body: some View {
        ZStack {
            // The storm sky: slate and deep blue at the top, gone by the middle.
            LinearGradient(stops: [
                .init(color: Color(hex: 0x0B1220).opacity(0.75), location: 0),
                .init(color: Color(hex: 0x111A2C).opacity(0.4), location: 0.32),
                .init(color: .clear, location: 0.62),
            ], startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still || scenePhase != .active)) { timeline in
                let time = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    DragonStorm.drawLightning(in: &context, size: size, time: time, flashes: !still)
                    DragonStorm.drawRain(in: &context, size: size, time: time)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Rain

    private struct Layer {
        let count: Int
        let speed: Double
        let length: CGFloat
        let width: CGFloat
        let opacity: Double
    }

    /// Far, middle and near rain: the near drops fall faster, longer and brighter.
    private static let layers: [Layer] = [
        Layer(count: 70, speed: 520, length: 10, width: 0.6, opacity: 0.10),
        Layer(count: 46, speed: 820, length: 18, width: 0.9, opacity: 0.15),
        Layer(count: 22, speed: 1250, length: 30, width: 1.3, opacity: 0.2),
    ]

    /// The wind leans the rain a little to the left.
    private static let lean: CGFloat = -0.16

    static func drawRain(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let span = size.height + 60
        for (index, layer) in layers.enumerated() {
            var seed = UInt64(0xD2A6_0000 + index * 7919)
            var path = Path()
            for _ in 0..<layer.count {
                let x0 = CrowdRing.next(&seed) * Double(size.width + 80) - 40
                let phase = CrowdRing.next(&seed) * Double(span)
                let jitter = 0.85 + CrowdRing.next(&seed) * 0.3
                let fallen = (phase + time * layer.speed * jitter).truncatingRemainder(dividingBy: Double(span))
                let y = CGFloat(fallen) - 30
                let x = CGFloat(x0) + lean * y
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + lean * layer.length, y: y + layer.length))
            }
            context.stroke(path, with: .color(Color(hex: 0xC9D6E8).opacity(layer.opacity)),
                           style: StrokeStyle(lineWidth: layer.width, lineCap: .round))
        }
    }

    // MARK: Lightning

    /// A strike may come once in each window of this many seconds.
    private static let window = 8.0

    /// How bright the strike in this window is at `time`: a flash, a dip, a second flash, a fade.
    static func flash(at time: Double) -> (strength: Double, strike: Int) {
        let strike = Int((time / window).rounded(.down))
        var seed = UInt64(truncatingIfNeeded: strike &* 2_654_435_761) ^ 0x5DEE_CE66
        // Some windows stay quiet, so the storm never keeps a beat.
        guard CrowdRing.next(&seed) > 0.3 else { return (0, strike) }
        let at = Double(strike) * window + 1 + CrowdRing.next(&seed) * (window - 3)
        let since = time - at
        guard since >= 0, since < 1.4 else { return (0, strike) }
        let strength: Double
        switch since {
        case ..<0.07: strength = 1
        case ..<0.15: strength = 0.25
        case ..<0.24: strength = 0.8
        default: strength = 0.8 * exp(-(since - 0.24) * 4.5)
        }
        return (strength, strike)
    }

    static func drawLightning(in context: inout GraphicsContext, size: CGSize, time: Double, flashes: Bool) {
        guard flashes else { return }
        let (strength, strike) = flash(at: time)
        guard strength > 0.02 else { return }
        // The cold light in the clouds, strongest at the top.
        let sky = Path(CGRect(origin: .zero, size: size))
        context.fill(sky, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(hex: 0xBFD3FF).opacity(0.22 * strength), location: 0),
                .init(color: Color(hex: 0x8FA8E0).opacity(0.08 * strength), location: 0.35),
                .init(color: .clear, location: 0.6),
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        // The bolt, far off on one side.
        let bolt = boltPath(strike: strike, size: size)
        var glow = context
        glow.addFilter(.blur(radius: 6))
        glow.stroke(bolt, with: .color(Color(hex: 0xAFC6FF).opacity(0.55 * strength)),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        context.stroke(bolt, with: .color(Color.white.opacity(0.9 * strength)),
                       style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
    }

    /// A forked bolt from above the top edge down into the upper third, the same for the whole strike.
    static func boltPath(strike: Int, size: CGSize) -> Path {
        var seed = UInt64(truncatingIfNeeded: strike &* 40_503) ^ 0xB01D_FACE
        let left = CrowdRing.next(&seed) < 0.5
        let side: Double = left ? 0.12 : 0.66
        let across: Double = side + CrowdRing.next(&seed) * 0.22
        let startX: CGFloat = size.width * CGFloat(across)
        let bottom = size.height * CGFloat(0.22 + CrowdRing.next(&seed) * 0.12)
        var path = Path()
        var point = CGPoint(x: startX, y: -8)
        path.move(to: point)
        let steps = 11
        var forks: [CGPoint] = []
        for step in 1...steps {
            let dx = CGFloat(CrowdRing.next(&seed) - 0.5) * 26
            point = CGPoint(x: point.x + dx, y: -8 + (bottom + 8) * CGFloat(step) / CGFloat(steps))
            path.addLine(to: point)
            if step > 2, step < steps - 1, CrowdRing.next(&seed) < 0.28 { forks.append(point) }
        }
        for fork in forks.prefix(3) {
            var branch = fork
            path.move(to: branch)
            let lean: CGFloat = CrowdRing.next(&seed) < 0.5 ? -1 : 1
            for _ in 0..<4 {
                branch = CGPoint(x: branch.x + lean * CGFloat(6 + CrowdRing.next(&seed) * 12),
                                 y: branch.y + CGFloat(8 + CrowdRing.next(&seed) * 12))
                path.addLine(to: branch)
            }
        }
        return path
    }
}

#Preview("Dragon storm") {
    ZStack {
        Color(hex: 0x0A0A0D)
        DragonStorm()
    }
}
