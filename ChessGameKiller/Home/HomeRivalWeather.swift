import SwiftUI

// The rival's picture on Home's Next game card has weather moving in it (Alex, 2026-11-28:
// "add backgrounds that are moving in each of the rivals pictures"): leaves fall around the
// Cub, snow around the Hunter, rain around the Berserker, embers rise around the Lionheart
// and lightning strikes around the Ashen King. Alex picked the weather behind the rival, so
// it is drawn through the rival's cut-out (rival-<slug>-cut.png) and never crosses a face.

/// What moves behind each rival.
enum HomeRivalSky: Equatable {
    case leaves, snow, rain, embers, lightning

    init(_ level: MatchController.Level) {
        switch level {
        case .beginner: self = .leaves
        case .casual: self = .snow
        case .club: self = .rain
        case .expert: self = .embers
        case .grandmaster: self = .lightning
        }
    }

    /// The Lionheart's torch and the Ashen King's lightning also light the rival a little.
    var lightsTheRival: Bool { self == .embers || self == .lightning }
}

/// The weather over a rival's square picture, behind the rival. `side` and `top` are the
/// picture's own: its side, and where the square starts down the 9:16 still. With Reduce
/// Motion on, or when the card is out of sight, the weather holds still.
struct HomeRivalWeather: View {
    let rival: Rival
    let side: CGFloat
    let top: CGFloat
    var moves: Bool = true
    /// A moment to hold the weather at, for pictures in tests.
    var at: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.weatherRests) private var rests

    private var sky: HomeRivalSky { HomeRivalSky(rival.level) }
    /// Nothing is drawn thirty times a second for a picture nobody can see.
    private var paused: Bool { at != nil || reduceMotion || rests || !moves || scenePhase != .active }

    var body: some View {
        // Without the cut-out there is no telling the rival from the sky, so nothing falls.
        if let cut = RivalFilm.of(rival.level).cutImage {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
                let time: Double = at ?? (reduceMotion ? HomeRivalWeatherPainter.restTime
                                                       : timeline.date.timeIntervalSinceReferenceDate)
                ZStack {
                    Canvas { context, size in
                        HomeRivalWeatherPainter(sky: sky, time: time, size: size).paintBehind(&context)
                    }
                    .mask { cutOut(cut) }
                    if sky.lightsTheRival {
                        Canvas { context, size in
                            HomeRivalWeatherPainter(sky: sky, time: time, size: size).paintLight(&context)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The cut-out, laid exactly as HomeRivalFrame lays the still.
    private func cutOut(_ cut: UIImage) -> some View {
        Image(uiImage: cut)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side * 16 / 9)
            .offset(y: -top * side * 16 / 9)
            .frame(width: side, height: side, alignment: .top)
            .clipped()
    }
}

/// Draws one frame of a rival's weather on a 100 by 100 sheet stretched over the picture, so
/// it looks the same at any size. Every leaf, flake, drop and spark comes from its index, so
/// the weather runs on its own without any state.
struct HomeRivalWeatherPainter {
    let sky: HomeRivalSky
    let time: Double
    let size: CGSize

    /// Where the weather stands with Reduce Motion on.
    static let restTime: Double = 3.2
    /// One lightning strike in each stretch this long, in seconds.
    static let strikeEvery: Double = 4.5
    /// How long a strike's light lasts.
    static let strikeLasts: Double = 0.6

    private var w: Double { 100 }
    private var h: Double { 100 }

    /// A steady random number in 0..<1 for particle `i`, `salt` telling its numbers apart.
    static func noise(_ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    /// When the strike of stretch `cycle` begins: at a different moment in each stretch.
    static func strike(_ cycle: Int) -> Double {
        Double(cycle) * strikeEvery + 0.5 + noise(cycle, 7) * (strikeEvery - strikeLasts - 1)
    }

    private func noise(_ i: Int, _ salt: Int) -> Double { Self.noise(i, salt) }

    /// `value` wrapped into 0..<length.
    private func wrap(_ value: Double, _ length: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: length)
        return r < 0 ? r + length : r
    }

    /// A soft flicker in about 0...1, like a flame.
    private func flicker(_ seed: Double) -> Double {
        0.5 + 0.22 * sin(time * 7.3 + seed) + 0.16 * sin(time * 12.1 + seed * 2) + 0.12 * sin(time * 3.1 + seed * 3)
    }

    private var cycle: Int { Int((time / Self.strikeEvery).rounded(.down)) }

    /// How bright the lightning is right now, 0...1: two quick flashes, the second the
    /// brighter, then fading.
    private var flash: Double {
        let at = time - Self.strike(cycle)
        guard at >= 0, at < Self.strikeLasts else { return 0 }
        if at < 0.08 { return at / 0.08 * 0.6 }
        if at < 0.16 { return 0.25 }
        if at < 0.24 { return 1 }
        return max(0, 1 - (at - 0.24) / (Self.strikeLasts - 0.24))
    }

    private func fit(_ context: inout GraphicsContext) {
        context.scaleBy(x: size.width / w, y: size.height / h)
    }

    /// The weather itself, which the rival's cut-out then hides wherever the rival is.
    func paintBehind(_ context: inout GraphicsContext) {
        fit(&context)
        switch sky {
        case .leaves: leaves(&context)
        case .snow: snow(&context)
        case .rain: rain(&context)
        case .embers: embers(&context)
        case .lightning: lightning(&context)
        }
    }

    /// What is drawn over the rival: the faint light the weather throws on them, and the
    /// Lionheart's few low sparks.
    func paintLight(_ context: inout GraphicsContext) {
        fit(&context)
        context.blendMode = .plusLighter
        switch sky {
        case .embers:
            // The torch at the Lionheart's shoulder, low on the left.
            let center = CGPoint(x: 4, y: 76)
            let radius: Double = 58
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.6, blue: 0.2).opacity(0.1 + 0.12 * flicker(0)),
                                                                 Color(red: 1, green: 0.6, blue: 0.2).opacity(0)]),
                                               center: center, startRadius: 0, endRadius: radius))
            // He fills almost the whole picture, so a few sparks also drift up in front of
            // his armor. They go out below his jaw and never cross his face.
            var sparks = context
            sparks.addFilter(.shadow(color: Color(red: 1, green: 0.55, blue: 0.16), radius: 1.6))
            for i in 0..<9 {
                let rise = 7 + noise(i, 21) * 8
                let span = h * 0.42
                let y = h + 2 - wrap(time * rise + noise(i, 22) * span, span)
                let x = noise(i, 23) * w + sin(time * 1.1 + Double(i) * 2) * 4
                let r = 0.45 + noise(i, 24) * 0.6
                sparks.opacity = max(0, min(1, (y - h * 0.6) / (h * 0.2))) * (0.55 + 0.45 * flicker(Double(i + 40)))
                sparks.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(Color(red: 1, green: 0.84, blue: 0.49)))
            }
        case .lightning:
            let lit = flash
            guard lit > 0 else { return }
            context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.8, green: 0.87, blue: 1).opacity(0.16 * lit),
                                  Color(red: 0.8, green: 0.87, blue: 1).opacity(0.04 * lit)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        case .leaves, .snow, .rain:
            break
        }
    }

    // MARK: The Cub: autumn leaves turning as they fall through the birches.

    private func leaves(_ context: inout GraphicsContext) {
        let colors = [Color(red: 0.79, green: 0.4, blue: 0.16), Color(red: 0.88, green: 0.54, blue: 0.18),
                      Color(red: 0.66, green: 0.27, blue: 0.11), Color(red: 0.85, green: 0.63, blue: 0.23)]
        var shape = Path()
        shape.move(to: CGPoint(x: 0, y: -5))
        shape.addCurve(to: CGPoint(x: 0, y: 5), control1: CGPoint(x: 4, y: -2.5), control2: CGPoint(x: 4, y: 2.5))
        shape.addCurve(to: CGPoint(x: 0, y: -5), control1: CGPoint(x: -4, y: 2.5), control2: CGPoint(x: -4, y: -2.5))
        for i in 0..<16 {
            let fall = 9 + noise(i, 1) * 9
            let span = h + 16
            let y = wrap(time * fall + noise(i, 2) * span, span) - 8
            let x = wrap(noise(i, 3) * w + time * 5 + sin(time * 0.9 + Double(i)) * 10, w + 16) - 8
            let spin = Angle.degrees(time * (40 + noise(i, 4) * 80) + Double(i) * 47)
            let scale = (0.75 + noise(i, 5) * 0.6) * 0.9
            var leaf = context
            leaf.translateBy(x: x, y: y)
            leaf.rotate(by: spin)
            // The leaf turns over as it falls, so it thins and fills out again.
            leaf.scaleBy(x: scale * (0.55 + 0.45 * abs(cos(time * 1.7 + Double(i)))), y: scale)
            leaf.opacity = 0.75 + noise(i, 6) * 0.25
            leaf.fill(shape, with: .color(colors[i % colors.count]))
        }
    }

    // MARK: The Hunter: snow drifting down over the night forest.

    private func snow(_ context: inout GraphicsContext) {
        for i in 0..<46 {
            let fall = 7 + noise(i, 1) * 12
            let span = h + 8
            let y = wrap(time * fall + noise(i, 2) * span, span) - 4
            let x = wrap(noise(i, 3) * w + sin(time * 0.7 + Double(i)) * 6 - time * 3, w)
            let r = 0.5 + noise(i, 4) * 1.2
            context.opacity = 0.35 + noise(i, 5) * 0.55
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white))
        }
        context.opacity = 1
    }

    // MARK: The Berserker: hard rain slanting across the battlefield.

    private func rain(_ context: inout GraphicsContext) {
        for i in 0..<60 {
            let fall = 150 + noise(i, 1) * 70
            let length = 7 + noise(i, 2) * 9
            let span = h + length
            let y = wrap(time * fall + noise(i, 3) * span, span) - length
            let x = wrap(noise(i, 4) * w * 1.2 - (y + length) * 0.3, w * 1.2)
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - length * 0.3, y: y + length))
            context.stroke(drop, with: .color(Color(red: 0.8, green: 0.86, blue: 0.94).opacity(0.25 + noise(i, 5) * 0.35)),
                           lineWidth: 0.55)
        }
    }

    // MARK: The Lionheart: embers rising from the fires behind him (a few more in paintLight).

    private func embers(_ context: inout GraphicsContext) {
        var sparks = context
        sparks.addFilter(.shadow(color: Color(red: 1, green: 0.55, blue: 0.16), radius: 1.6))
        for i in 0..<40 {
            let rise = 9 + noise(i, 1) * 12
            let span = h + 6
            let y = h - wrap(time * rise + noise(i, 2) * span, span) + 3
            let x = noise(i, 3) * w + sin(time * 1.3 + Double(i) * 2) * 5
            let r = 0.6 + noise(i, 4) * 1.0
            // He fills his picture, and what sky there is lies at the top: they glow all the
            // way up and go out only as they leave.
            sparks.opacity = max(0, min(1, (y + 2) / 14)) * (0.6 + 0.4 * flicker(Double(i)))
            sparks.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                        with: .color(Color(red: 1, green: 0.84, blue: 0.49)))
        }
    }

    // MARK: The Ashen King: thin rain, and lightning behind the throne.

    private func lightning(_ context: inout GraphicsContext) {
        for i in 0..<22 {
            let fall = 120 + noise(i, 1) * 60
            let length = 6 + noise(i, 2) * 7
            let span = h + length
            let y = wrap(time * fall + noise(i, 3) * span, span) - length
            let x = noise(i, 4) * w
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - length * 0.12, y: y + length))
            context.stroke(drop, with: .color(Color(red: 0.78, green: 0.82, blue: 0.9).opacity(0.14 + noise(i, 5) * 0.2)),
                           lineWidth: 0.5)
        }
        let lit = flash
        guard lit > 0 else { return }
        // The sky goes white-blue, brightest at the top.
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .linearGradient(
            Gradient(colors: [Color(red: 0.8, green: 0.86, blue: 1).opacity(0.42 * lit),
                              Color(red: 0.8, green: 0.86, blue: 1).opacity(0.14 * lit)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        // The throne hides the middle of the sky, so the bolt comes down one side of it or
        // the other, in a new place each time, with one fork.
        let strike = cycle
        let left: Bool = noise(strike, 12) < 0.5
        let band: ClosedRange<Double> = left ? 1.5...10.5 : 89.5...98.5
        var bolt = Path()
        var fork = Path()
        var point = CGPoint(x: band.lowerBound + noise(strike, 8) * 9, y: -2)
        bolt.move(to: point)
        for step in 1...7 {
            let x: Double = point.x + (noise(strike * 7 + step, 9) - 0.5) * 7
            point = CGPoint(x: min(band.upperBound, max(band.lowerBound, x)), y: h * 0.74 * Double(step) / 7)
            bolt.addLine(to: point)
            if step == 3 {
                // The fork leans in behind the throne.
                var tip = point
                fork.move(to: tip)
                for part in 1...3 {
                    tip = CGPoint(x: tip.x + (left ? 1 : -1) * (2 + noise(strike * 5 + part, 11) * 5), y: tip.y + 7)
                    fork.addLine(to: tip)
                }
            }
        }
        var glow = context
        glow.opacity = lit
        glow.addFilter(.shadow(color: Color(red: 0.74, green: 0.82, blue: 1), radius: 3))
        glow.stroke(fork, with: .color(Color(red: 0.92, green: 0.95, blue: 1).opacity(0.8)),
                    style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
        glow.stroke(bolt, with: .color(Color(red: 0.95, green: 0.97, blue: 1)),
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
    }
}
