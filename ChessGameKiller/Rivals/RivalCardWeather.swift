import SwiftUI

// The rival's card above the board comes alive (Alex, 2026-11-11): its coin turns now and then,
// flips when the rival takes a piece and dulls and cracks when the rival is losing, and behind
// the card is a dark slice of the rival's own film with that film's weather moving over it.
// The Cub's birch woods drop leaves by lantern light, the Hunter's night forest snows, the
// Berserker's battlefield storms with lightning, the Lionheart's hall flickers with torches and
// sparks, and the Ashen King's throne burns with falling ash and rising embers.

/// The weather of a rival's film.
enum RivalWeather {
    case leaves, snow, storm, torches, ash

    init(_ level: MatchController.Level) {
        switch level {
        case .beginner: self = .leaves
        case .casual: self = .snow
        case .club: self = .storm
        case .expert: self = .torches
        case .grandmaster: self = .ash
        }
    }
}

/// Behind the rival's card: the film's slice, a veil that keeps the words readable, and the
/// weather. With Reduce Motion on, the weather holds still.
struct RivalCardBackdrop: View {
    let rival: Rival

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var weather: RivalWeather { RivalWeather(rival.level) }

    var body: some View {
        ZStack {
            Image("rival-" + rival.slug + "-card")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
            // Darker on the left, where the coin and the words are.
            LinearGradient(colors: [.black.opacity(0.58), .black.opacity(0.32), .black.opacity(0.12)],
                           startPoint: .leading, endPoint: .trailing)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    let time = reduceMotion ? 3.2 : timeline.date.timeIntervalSinceReferenceDate
                    WeatherPainter(weather: weather, time: time, size: size).paint(&context)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Draws one frame of a rival's weather. Every flake, drop, leaf and spark comes from its index,
/// so the weather runs on its own without any state.
private struct WeatherPainter {
    let weather: RivalWeather
    let time: Double
    let size: CGSize

    private var w: Double { size.width }
    private var h: Double { size.height }

    /// A steady random number in 0..<1 for particle `i`, `salt` telling its numbers apart.
    private func noise(_ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    /// `value` wrapped into 0..<length.
    private func wrap(_ value: Double, _ length: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: length)
        return r < 0 ? r + length : r
    }

    /// A soft flicker in about 0...1, like a flame.
    private func flicker(_ seed: Double) -> Double {
        0.5 + 0.22 * sin(time * 7.3 + seed) + 0.16 * sin(time * 12.1 + seed * 2) + 0.12 * sin(time * 3.1 + seed * 3)
    }

    func paint(_ context: inout GraphicsContext) {
        switch weather {
        case .leaves: leaves(&context)
        case .snow: snow(&context)
        case .storm: storm(&context)
        case .torches: torches(&context)
        case .ash: ash(&context)
        }
    }

    private func glow(_ context: inout GraphicsContext, at center: CGPoint, radius: Double, color: Color, opacity: Double) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
            center: center, startRadius: 0, endRadius: radius))
    }

    // MARK: The Cub: autumn leaves in the birch woods, and his lantern.

    private func leaves(_ context: inout GraphicsContext) {
        glow(&context, at: CGPoint(x: 34, y: h * 0.78), radius: h * 0.75,
             color: Color(red: 1, green: 0.62, blue: 0.22), opacity: 0.26 + 0.1 * flicker(1))
        let colors = [Color(red: 0.79, green: 0.4, blue: 0.16), Color(red: 0.88, green: 0.54, blue: 0.18),
                      Color(red: 0.66, green: 0.27, blue: 0.11), Color(red: 0.85, green: 0.63, blue: 0.23)]
        for i in 0..<11 {
            let fall = 9 + noise(i, 1) * 9
            let span = h + 24
            let y = wrap(time * fall + noise(i, 2) * span, span) - 12
            let x = wrap(noise(i, 3) * w + time * 5 + sin(time * 0.9 + Double(i)) * 14, w + 24) - 12
            let spin = Angle.degrees(time * (40 + noise(i, 4) * 80) + Double(i) * 47)
            let scale = 0.75 + noise(i, 5) * 0.6
            var leaf = context
            leaf.translateBy(x: x, y: y)
            leaf.rotate(by: spin)
            leaf.scaleBy(x: scale * (0.55 + 0.45 * abs(cos(time * 1.7 + Double(i)))), y: scale)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: -5))
            path.addCurve(to: CGPoint(x: 0, y: 5), control1: CGPoint(x: 4, y: -2.5), control2: CGPoint(x: 4, y: 2.5))
            path.addCurve(to: CGPoint(x: 0, y: -5), control1: CGPoint(x: -4, y: 2.5), control2: CGPoint(x: -4, y: -2.5))
            leaf.opacity = 0.7 + noise(i, 6) * 0.3
            leaf.fill(path, with: .color(colors[i % colors.count]))
        }
    }

    // MARK: The Hunter: snow over the night forest.

    private func snow(_ context: inout GraphicsContext) {
        for i in 0..<60 {
            let fall = 7 + noise(i, 1) * 12
            let span = h + 8
            let y = wrap(time * fall + noise(i, 2) * span, span) - 4
            let x = wrap(noise(i, 3) * w + sin(time * 0.7 + Double(i)) * 8 - time * 3, w)
            let r = 0.6 + noise(i, 4) * 1.6
            context.opacity = 0.35 + noise(i, 5) * 0.55
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white))
        }
        context.opacity = 1
    }

    // MARK: The Berserker: slanting rain, and lightning now and then.

    private func storm(_ context: inout GraphicsContext) {
        // Lightning: once in each 11-second stretch, at a different moment and place each time.
        let period = 11.0
        let cycle = Int((time / period).rounded(.down))
        let at = time - Double(cycle) * period - (2 + noise(cycle, 7) * 6)
        if at >= 0, at < 0.55 {
            // Two quick flashes, the second the brighter, then fading.
            let flash = at < 0.08 ? at / 0.08 * 0.6 : at < 0.16 ? 0.25 : at < 0.24 ? 1 : max(0, 1 - (at - 0.24) / 0.31)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.8, green: 0.86, blue: 1).opacity(0.05 * flash),
                                  Color(red: 0.8, green: 0.86, blue: 1).opacity(0.42 * flash)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w, y: h)))
            var bolt = Path()
            var point = CGPoint(x: w * (0.62 + noise(cycle, 8) * 0.3), y: -2)
            bolt.move(to: point)
            for step in 1...6 {
                point = CGPoint(x: point.x + (noise(cycle * 7 + step, 9) - 0.55) * 26, y: h * Double(step) / 6 + 2)
                bolt.addLine(to: point)
            }
            var lit = context
            lit.opacity = flash
            lit.addFilter(.shadow(color: Color(red: 0.74, green: 0.82, blue: 1), radius: 5))
            lit.stroke(bolt, with: .color(Color(red: 0.94, green: 0.96, blue: 1)), lineWidth: 1.6)
        }
        for i in 0..<55 {
            let fall = 230 + noise(i, 1) * 90
            let length = 9 + noise(i, 2) * 10
            let span = h + length
            let y = wrap(time * fall + noise(i, 3) * span, span) - length
            let x = wrap(noise(i, 4) * w * 1.2 - (y + length) * 0.3, w * 1.2)
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - length * 0.3, y: y + length))
            context.stroke(drop, with: .color(Color(red: 0.78, green: 0.84, blue: 0.92).opacity(0.22 + noise(i, 5) * 0.32)), lineWidth: 0.8)
        }
    }

    // MARK: The Lionheart: torchlight in the throne hall, and sparks rising.

    private func torches(_ context: inout GraphicsContext) {
        let ember = Color(red: 1, green: 0.62, blue: 0.2)
        glow(&context, at: CGPoint(x: w * 0.84, y: h * 0.8), radius: h * 1.0, color: ember, opacity: 0.3 + 0.16 * flicker(0))
        glow(&context, at: CGPoint(x: w * 0.16, y: h * 0.85), radius: h * 0.7, color: ember, opacity: 0.12 + 0.08 * flicker(2.4))
        var sparks = context
        sparks.addFilter(.shadow(color: Color(red: 1, green: 0.68, blue: 0.23), radius: 2))
        for i in 0..<20 {
            let rise = 9 + noise(i, 1) * 12
            let span = h + 6
            let y = h - wrap(time * rise + noise(i, 2) * span, span) + 3
            let x = w * (0.45 + noise(i, 3) * 0.55) + sin(time * 1.3 + Double(i) * 2) * 6
            let r = 0.6 + noise(i, 4) * 1.1
            // Brightest low down, gone by the top.
            sparks.opacity = max(0, min(1, y / h * 1.4)) * (0.55 + 0.45 * flicker(Double(i)))
            sparks.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(Color(red: 1, green: 0.83, blue: 0.48)))
        }
    }

    // MARK: The Ashen King: a fire breathing from below, grey ash falling, embers rising.

    private func ash(_ context: inout GraphicsContext) {
        let breath = 0.5 + 0.5 * sin(time * 1.1)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
            Gradient(colors: [Color(red: 0.9, green: 0.24, blue: 0.08).opacity(0.38 + 0.18 * breath),
                              Color(red: 0.63, green: 0.1, blue: 0.04).opacity(0.14 + 0.08 * breath),
                              Color(red: 0.47, green: 0.04, blue: 0.02).opacity(0)]),
            center: CGPoint(x: w * 0.55, y: h * 1.25), startRadius: 0, endRadius: w * 0.55))
        for i in 0..<30 {
            let fall = 6 + noise(i, 1) * 9
            let span = h + 8
            let y = wrap(time * fall + noise(i, 2) * span, span) - 4
            let x = wrap(noise(i, 3) * w + sin(time * 0.6 + Double(i)) * 10 + time * 2, w)
            let s = 0.8 + noise(i, 4) * 1.6
            var flake = context
            flake.translateBy(x: x, y: y)
            flake.rotate(by: .degrees(time * 50 * (noise(i, 5) - 0.5) + Double(i) * 30))
            flake.opacity = 0.35 + noise(i, 6) * 0.4
            flake.fill(Path(CGRect(x: -s * 0.8, y: -s * 0.5, width: s * 1.6, height: s)), with: .color(Color(white: 0.68)))
        }
        var embers = context
        embers.addFilter(.shadow(color: Color(red: 1, green: 0.23, blue: 0.06), radius: 3))
        for i in 0..<12 {
            let rise = 10 + noise(i, 7) * 14
            let span = h * 0.8
            let y = h - wrap(time * rise + noise(i, 8) * span, span)
            let x = noise(i, 9) * w + sin(time * 1.5 + Double(i)) * 7
            let r = 0.6 + noise(i, 10) * 1.0
            embers.opacity = max(0, min(1, (y - h * 0.2) / (h * 0.5)))
            embers.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(Color(red: 1, green: 0.42, blue: 0.16)))
        }
    }
}

/// The rival's coin on its card, alive: every 16 to 24 seconds it turns once slowly, like a coin
/// spun on a table; when the rival takes a piece it flips quickly and light runs across it; when
/// the rival is 3 or more behind it goes dull and a crack runs through it.
struct LivingRivalCoin: View {
    let rival: Rival
    let size: CGFloat
    /// How many of the player's pieces the rival has taken.
    let captures: Int
    let losing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn: Double = 0
    @State private var glint: CGFloat = -1.3

    var body: some View {
        RivalCoin(rival: rival, size: size)
            .saturation(losing ? 0.15 : 1)
            .brightness(losing ? -0.14 : 0)
            .overlay {
                if losing {
                    crack.transition(.opacity)
                }
            }
            .overlay { shine }
            .modifier(CoinTurn(angle: turn, size: size))
            .animation(.easeInOut(duration: 0.8), value: losing)
            .task(id: reduceMotion) {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Double.random(in: 16...24)))
                    if Task.isCancelled { break }
                    withAnimation(.easeInOut(duration: 2.2)) { turn += 360 }
                }
            }
            .onChange(of: captures) { old, new in
                guard new > old else { return }
                if !reduceMotion {
                    withAnimation(.easeOut(duration: 0.6)) { turn += 360 }
                }
                glint = -1.3
                withAnimation(.easeInOut(duration: 0.7).delay(reduceMotion ? 0 : 0.4)) { glint = 1.3 }
            }
            .accessibilityHidden(true)
    }

    /// The coin's own shape, for keeping the crack and the light on the metal.
    private var coinMask: some View { RivalCoin(rival: rival, size: size) }

    private var crack: some View {
        let points: [CGPoint] = [
            CGPoint(x: 0.69, y: 0.07), CGPoint(x: 0.57, y: 0.31), CGPoint(x: 0.67, y: 0.42),
            CGPoint(x: 0.48, y: 0.61), CGPoint(x: 0.56, y: 0.75), CGPoint(x: 0.42, y: 0.94),
        ]
        let path = Path { p in
            p.addLines(points.map { CGPoint(x: $0.x * size, y: $0.y * size) })
            p.move(to: CGPoint(x: 0.57 * size, y: 0.31 * size))
            p.addLine(to: CGPoint(x: 0.44 * size, y: 0.26 * size))
        }
        return ZStack {
            path.stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: max(1, size * 0.035), lineJoin: .miter))
            path.stroke(Color.white.opacity(0.35), lineWidth: max(0.5, size * 0.012))
                .offset(x: size * 0.018)
        }
        .frame(width: size, height: size)
        .mask(coinMask)
        .allowsHitTesting(false)
    }

    private var shine: some View {
        Rectangle()
            .fill(LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: Color(red: 1, green: 0.98, blue: 0.88).opacity(0.9), location: 0.5),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing))
            .frame(width: size * 0.45, height: size * 1.8)
            .rotationEffect(.degrees(22))
            .offset(x: glint * size)
            .blendMode(.screen)
            .frame(width: size, height: size)
            .mask(coinMask)
            .allowsHitTesting(false)
    }
}

/// Turns the coin about its upright axis. Edge on, it darkens and its silver rim shows, so it
/// reads as a thick coin turning and not a picture squashing.
private struct CoinTurn: ViewModifier, Animatable {
    var angle: Double
    let size: CGFloat

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let facing = abs(cos(angle * .pi / 180))
        content
            .brightness(-0.22 * (1 - facing))
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.82), Color(white: 0.42)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: size * 0.09, height: size * 0.9)
                    .opacity(pow(1 - facing, 3))
            }
    }
}

#Preview("Rival weather") {
    VStack(spacing: 14) {
        ForEach(Rival.all) { rival in
            HStack(spacing: 12) {
                LivingRivalCoin(rival: rival, size: 40, captures: 0, losing: rival.level == .club)
                Text(rival.name).font(.headline).foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 96)
            .background { RivalCardBackdrop(rival: rival) }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
    .padding()
    .background(Color.black)
}
