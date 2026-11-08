import SwiftUI

// MARK: - The king

/// Where the gold scars cut across the onyx king, in the king picture's own 0...1 space.
/// Your first win carves the first one, and so on up to ten, when it is rebuilt.
enum GrudgeScars {
    private static let raw: [[(CGFloat, CGFloat)]] = [
        [(205, 455), (240, 428), (258, 444), (292, 414)],
        [(340, 505), (315, 528), (325, 548), (300, 574)],
        [(225, 575), (268, 563), (284, 582)],
        [(352, 395), (335, 430), (350, 442)],
        [(200, 640), (232, 618), (255, 630), (283, 610)],
        [(300, 610), (322, 636), (310, 660)],
        [(250, 365), (290, 372), (302, 350)],
        [(275, 690), (300, 705), (330, 690)],
        [(230, 520), (262, 503)],
        [(320, 470), (345, 480), (338, 500)],
    ]

    static let all: [[CGPoint]] = raw.map { scar in
        scar.map { point in CGPoint(x: point.0 / 560, y: point.1 / 760) }
    }
}

/// The scars, drawn up to `count`: every scar whole except the newest, which is drawn as far
/// as `count`'s fraction, so animating `count` from 6 to 7 carves the seventh.
struct ScarsShape: Shape {
    var count: Double

    var animatableData: Double {
        get { count }
        set { count = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scars = GrudgeScars.all
        let whole = Int(count.rounded(.down))
        let part = count - Double(whole)
        for index in 0..<min(scars.count, Int(count.rounded(.up))) {
            let points = scars[index].map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
            let share = index < whole ? 1 : part
            add(points, upTo: share, to: &path)
        }
        return path
    }

    /// A broken line through `points`, cut off at `share` of its length.
    private func add(_ points: [CGPoint], upTo share: Double, to path: inout Path) {
        guard points.count > 1, share > 0 else { return }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var left = lengths.reduce(0, +) * min(share, 1)
        path.move(to: points[0])
        for (index, length) in lengths.enumerated() {
            let from = points[index]
            let to = points[index + 1]
            if left >= length {
                path.addLine(to: to)
                left -= length
            } else {
                let t = length > 0 ? left / length : 0
                path.addLine(to: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
                return
            }
        }
    }
}

/// Your Grudge: the onyx king from the Gilded set, lit red from behind, with a gold scar for each
/// of your wins. `light` is how strongly the red light burns, 0 to 1.2 or so.
struct GrudgeKing: View {
    var scars: Double
    var size: CGFloat
    var light: Double = 1

    init(scars: Int, size: CGFloat, light: Double = 1) {
        self.scars = Double(scars)
        self.size = size
        self.light = light
    }

    init(carved scars: Double, size: CGFloat, light: Double = 1) {
        self.scars = scars
        self.size = size
        self.light = light
    }

    static let red = Color(hex: 0xE0313F)
    static let scarGold = Color(hex: 0xF3D59A)

    var body: some View {
        let width = size * 560 / 760
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Self.red.opacity(0.75 * light), Self.red.opacity(0.18 * light), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.55))
                .frame(width: size * 1.2, height: size * 1.2)
                .offset(y: size * 0.08)
            Image("gilded-bK")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: width, height: size)
                .shadow(color: Self.red.opacity(0.9 * min(light, 1)), radius: size * 0.02)
                .shadow(color: Self.red.opacity(0.7 * min(light, 1)), radius: size * 0.08)
                .overlay {
                    ScarsShape(count: scars)
                        .stroke(Self.scarGold, style: StrokeStyle(lineWidth: max(1, size / 110), lineCap: .round, lineJoin: .round))
                        .shadow(color: Self.scarGold.opacity(0.9), radius: size / 90)
                        .frame(width: width, height: size)
                }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - The summons

/// Your Grudge, picked. A red light wakes in the dark, the onyx king rises out of it, your
/// wins carve in as gold scars one tick at a time, the score rolls up and it speaks. After a
/// game since you last met, the newest scar cuts in with a flash (you won) or its light swells
/// (it won). The first time ever, the crowd that beat you falls away and the king forms where
/// they stood. With Reduce Motion on, it is simply there.
struct GrudgeStage: View {
    let record: GrudgeRecord
    /// The first time you meet it.
    var born = false
    /// The score when you last saw it, so what changed since plays out.
    var lastSeen: (you: Int, it: Int)? = nil
    /// Changes to play it again.
    var replay = 0

    @AppStorage("haptics") private var hapticsOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lightLevel = 0.0
    @State private var risen = false
    @State private var carved = 0.0
    @State private var yourScore = 0
    @State private var itsScore = 0
    @State private var spoken = ""
    @State private var showInfo = false
    @State private var crowdAway = false
    @State private var flash = 0.0
    @State private var shake = 0.0
    @State private var tick = 0
    @State private var thud = 0
    @State private var slam = 0
    @State private var swell = 0

    private var line: String {
        if born { return "Someone took that personally." }
        return GrudgeVoice.line(for: .greeting, record: record, pick: 0) ?? "I remember you."
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                if born {
                    CrowdRing(dots: 90, hue: Color(hex: 0xDDB46A))
                        .frame(width: 210, height: 210)
                        .scaleEffect(crowdAway ? 1.25 : 1)
                        .offset(y: crowdAway ? 50 : 0)
                        .opacity(crowdAway ? 0 : 0.9)
                }
                GrudgeKing(carved: carved, size: 190, light: lightLevel)
                    .offset(y: risen ? 0 : 46)
                    .brightness(risen ? 0 : -0.9)
                    .blur(radius: risen ? 0 : 6)
                    .opacity(risen ? 1 : 0)
                Rectangle()
                    .fill(.white)
                    .opacity(flash)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            }
            .frame(height: 210)
            .offset(x: shake)

            Text(spoken.isEmpty ? " " : spoken)
                .font(.app(.callout, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.88))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                Text("\(yourScore) – \(itsScore)")
                    .font(.app(.title, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text("you – it")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(record.mood.title.uppercased())
                    .font(.app(.caption2, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(GrudgeKing.red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .overlay { Capsule().strokeBorder(GrudgeKing.red.opacity(0.6), lineWidth: 1) }
            }
            .opacity(showInfo ? 1 : 0)
            .offset(y: showInfo ? 0 : 8)
        }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.5), trigger: tick) { _, _ in hapticsOn }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.7), trigger: thud) { _, _ in hapticsOn }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1), trigger: slam) { _, _ in hapticsOn }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.8), trigger: swell) { _, _ in hapticsOn }
        .task(id: replay) { await summon() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private var spokenSummary: String {
        "Your Grudge. You \(record.yourWins), it \(record.itsWins). \(record.mood.title). It says: \(line)"
    }

    /// Plays the whole entrance, start to finish.
    private func summon() async {
        let before: (you: Int, it: Int) = lastSeen ?? (you: record.yourWins, it: record.itsWins)
        let youWonSince = record.yourWins > before.you
        let itWonSince = record.itsWins > before.it
        // The scars it had before the game being told, so the new one can cut in after.
        let baseScars = Double(max(0, record.scars - (youWonSince ? 1 : 0)))

        if reduceMotion {
            lightLevel = 0.85
            risen = true
            carved = Double(record.scars)
            yourScore = record.yourWins
            itsScore = record.itsWins
            spoken = line
            showInfo = true
            crowdAway = true
            return
        }

        lightLevel = 0
        risen = false
        carved = 0
        yourScore = 0
        itsScore = 0
        spoken = ""
        showInfo = false
        crowdAway = false

        if born {
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeIn(duration: 1.1)) { crowdAway = true }
        }
        // The red light wakes.
        withAnimation(.easeOut(duration: 1.3)) { lightLevel = 0.85 }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        // The king rises out of the dark.
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.4)) { risen = true }
        thud += 1
        try? await Task.sleep(for: .milliseconds(1450))
        // Your wins, carved in one at a time.
        var scar = 0.0
        while scar < baseScars {
            guard !Task.isCancelled else { return }
            scar += 1
            withAnimation(.easeOut(duration: 0.26)) { carved = scar }
            tick += 1
            try? await Task.sleep(for: .milliseconds(140))
        }
        withAnimation(.easeOut(duration: 0.5)) { showInfo = true }
        withAnimation(.easeOut(duration: 0.8)) {
            yourScore = before.you
            itsScore = before.it
        }
        // What happened since you last met.
        if youWonSince {
            try? await Task.sleep(for: .milliseconds(450))
            await newScar()
        } else if itWonSince {
            try? await Task.sleep(for: .milliseconds(450))
            await grows()
        }
        withAnimation(.snappy) {
            yourScore = record.yourWins
            itsScore = record.itsWins
        }
        // Then it speaks.
        for character in line {
            guard !Task.isCancelled else { return }
            spoken.append(character)
            try? await Task.sleep(for: .milliseconds(character == "." ? 170 : 38))
        }
    }

    /// You won: a flash, a jolt, and the newest scar cuts in.
    private func newScar() async {
        withAnimation(.easeOut(duration: 0.05)) { flash = 0.5 }
        slam += 1
        withAnimation(.easeOut(duration: 0.26)) { carved = Double(record.scars) }
        for offset in [-5.0, 4, -2.5, 0] {
            withAnimation(.easeInOut(duration: 0.06)) { shake = offset }
            try? await Task.sleep(for: .milliseconds(60))
        }
        withAnimation(.easeOut(duration: 0.4)) { flash = 0 }
        if record.yourRun >= 2 {
            // Rattled: the light stutters.
            for level in [0.25, 0.7, 0.18, 0.75] {
                withAnimation(.easeInOut(duration: 0.12)) { lightLevel = level }
                try? await Task.sleep(for: .milliseconds(140))
            }
        }
    }

    /// It won: the red light swells and holds a beat.
    private func grows() async {
        withAnimation(.easeOut(duration: 0.4)) { lightLevel = 1.25 }
        swell += 1
        try? await Task.sleep(for: .milliseconds(260))
        swell += 1
        try? await Task.sleep(for: .milliseconds(600))
        withAnimation(.easeInOut(duration: 0.6)) { lightLevel = 1.0 }
    }
}

