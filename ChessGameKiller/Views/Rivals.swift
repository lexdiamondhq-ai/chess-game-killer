import SwiftUI

/// A computer opponent's personality: a name, a look and a rough rating for each level.
struct Rival: Identifiable {
    let level: MatchController.Level
    let name: String
    /// Rough Elo, like "~1500" or "3000+".
    let elo: String
    let blurb: String
    let hue: Color
    let hue2: Color
    /// The board that matches the portrait, used in games when "Match rival" is on.
    let boardTheme: BoardTheme.ID

    var id: MatchController.Level { level }

    /// 1 to 5, for the strength bars.
    var strength: Int { level.rawValue + 1 }

    /// The rating as VoiceOver should say it: "about 1500 Elo", "over 3000 Elo".
    var spokenElo: String {
        if elo.hasPrefix("~") { return "about \(elo.dropFirst()) Elo" }
        if elo.hasSuffix("+") { return "over \(elo.dropLast()) Elo" }
        return "\(elo) Elo"
    }

    /// The rival's portrait in Assets.xcassets/Rivals.
    var portraitName: String { "rival-" + name.lowercased() }

    static let all: [Rival] = MatchController.Level.allCases.map(\.rival)
}

extension MatchController.Level {
    var rival: Rival {
        switch self {
        case .beginner:
            return Rival(level: self, name: "Spark", elo: "~800",
                         blurb: "Misses a lot. Perfect for learning the moves.",
                         hue: Color(hex: 0xFFD54A), hue2: Color(hex: 0xFF9E3D),
                         boardTheme: .spark)
        case .casual:
            return Rival(level: self, name: "Drift", elo: "~1100",
                         blurb: "Plays for fun and takes chances.",
                         hue: Color(hex: 0x5BE0B0), hue2: Color(hex: 0x3DD6C8),
                         boardTheme: .drift)
        case .club:
            return Rival(level: self, name: "Pulse", elo: "~1500",
                         blurb: "Solid and patient. Punishes loose pawns.",
                         hue: Color(hex: 0x7CF7FF), hue2: Color(hex: 0x4C7BE8),
                         boardTheme: .pulse)
        case .expert:
            return Rival(level: self, name: "Vector", elo: "~2000",
                         blurb: "Sharp and precise. Attacks the moment you slip.",
                         hue: Color(hex: 0xA66BFF), hue2: Color(hex: 0x7C4DFF),
                         boardTheme: .vector)
        case .grandmaster:
            return Rival(level: self, name: "Singularity", elo: "3000+",
                         blurb: "Full engine strength. The ultimate test.",
                         hue: Color(hex: 0xFF5AC8), hue2: Color(hex: 0xFF3B6B),
                         boardTheme: .singularity)
        }
    }
}

/// A rival's sigil: a small glowing emblem drawn in code, one per level.
/// Everything is laid out in a 100-point space and scaled to `size`.
struct RivalSigil: View {
    let rival: Rival
    var size: CGFloat = 84
    var glows = true

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [rival.hue.opacity(0.28), rival.hue.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 48))
                .frame(width: 96, height: 96)
            switch rival.level {
            case .beginner: spark
            case .casual: drift
            case .club: pulse
            case .expert: vector
            case .grandmaster: singularity
            }
        }
        .frame(width: 100, height: 100)
        .scaleEffect(size / 100)
        .frame(width: size, height: size)
        .shadow(color: glows ? rival.hue.opacity(0.8) : .clear, radius: size * 0.08)
        .accessibilityHidden(true)
    }

    private func core(radius: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [.white, rival.hue, rival.hue2],
                                 center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
    }

    private func dot(_ radius: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(rival.hue)
            .frame(width: radius * 2, height: radius * 2)
            .position(x: x, y: y)
    }

    private var spark: some View {
        ZStack {
            core(radius: 12)
            dot(3, x: 78, y: 34)
            dot(2.2, x: 30, y: 72)
            dot(1.8, x: 70, y: 74)
            dot(1.6, x: 26, y: 36)
        }
        .frame(width: 100, height: 100)
    }

    private var drift: some View {
        ZStack {
            core(radius: 9)
            Circle()
                .trim(from: 0, to: 0.29)
                .stroke(rival.hue, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-30))
                .opacity(0.7)
            Circle()
                .trim(from: 0, to: 0.35)
                .stroke(rival.hue2, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(120))
                .opacity(0.55)
        }
    }

    private var pulse: some View {
        ZStack {
            core(radius: 8)
            Circle().stroke(rival.hue, lineWidth: 2).frame(width: 38, height: 38).opacity(0.85)
            Circle().stroke(rival.hue, lineWidth: 1.5).frame(width: 58, height: 58).opacity(0.5)
            Circle().stroke(rival.hue2, lineWidth: 1).frame(width: 76, height: 76).opacity(0.3)
        }
    }

    private var vector: some View {
        let hexagon = Polygon(points: [
            CGPoint(x: 50, y: 14), CGPoint(x: 81, y: 32), CGPoint(x: 81, y: 68),
            CGPoint(x: 50, y: 86), CGPoint(x: 19, y: 68), CGPoint(x: 19, y: 32),
        ])
        let triangle = Polygon(points: [CGPoint(x: 50, y: 30), CGPoint(x: 68, y: 60), CGPoint(x: 32, y: 60)])
        return ZStack {
            hexagon
                .stroke(rival.hue2, style: StrokeStyle(lineWidth: 6, lineJoin: .round))
                .opacity(0.18)
            hexagon
                .stroke(rival.hue, style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                .opacity(0.9)
            triangle
                .fill(RadialGradient(colors: [.white, rival.hue, rival.hue2],
                                     center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 22))
                .opacity(0.95)
        }
        .frame(width: 100, height: 100)
    }

    private var singularity: some View {
        ZStack {
            Circle().fill(Color(hex: 0x07030C)).frame(width: 28, height: 28)
            Circle()
                .stroke(LinearGradient(colors: [.white, rival.hue, rival.hue2],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 3.5)
                .frame(width: 30, height: 30)
            Ellipse()
                .trim(from: 0, to: 0.67)
                .stroke(rival.hue, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 72, height: 24)
                .rotationEffect(.degrees(-28))
                .opacity(0.7)
            Ellipse()
                .trim(from: 0, to: 0.17)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 72, height: 24)
                .rotationEffect(.degrees(-28))
                .opacity(0.25)
        }
    }
}

/// A rival's portrait: a rounded square photo with a glowing edge in the rival's color.
struct RivalPortrait: View {
    let rival: Rival
    var size: CGFloat = 92
    var glows = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        Image(rival.portraitName)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay { shape.strokeBorder(rival.hue.opacity(0.7), lineWidth: 1) }
            .shadow(color: glows ? rival.hue.opacity(0.55) : .black.opacity(0.2), radius: size * 0.12)
            .accessibilityHidden(true)
    }
}

/// A closed shape through points given in a 100-by-100 space.
private struct Polygon: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width, rect.height) / 100
        for (index, point) in points.enumerated() {
            let scaled = CGPoint(x: rect.minX + point.x * scale, y: rect.minY + point.y * scale)
            if index == 0 {
                path.move(to: scaled)
            } else {
                path.addLine(to: scaled)
            }
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Sigils") {
    HStack(spacing: 16) {
        ForEach(Rival.all) { rival in
            RivalSigil(rival: rival, size: 64)
        }
    }
    .padding(30)
    .background(NeonBackdrop())
}
