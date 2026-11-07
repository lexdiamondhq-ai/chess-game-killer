import SwiftUI
import UIKit

/// Who the person plays against the computer: The Crowd at one rating, or their Grudge.
///
/// The Crowd is real people. Its moves come from games real players at that rating played in
/// the same position (Lichess's database, see `CrowdBook`), and Maia, a network trained on
/// players of that rating (see `Maia`), takes over once the position is one nobody has reached. The Grudge is one rival that
/// remembers every game against you (`GrudgeStore`).
struct Rival: Identifiable {
    enum Kind: Equatable {
        case crowd
        case grudge
    }

    let level: MatchController.Level
    let kind: Kind
    /// "The 1600s", "The Masters", "Your Grudge".
    let name: String
    /// A short name for tight places, like the home's ladder: "1600s", "Masters".
    let shortName: String
    /// Names the rival's pictures: "1600s", "masters", "grudge".
    let slug: String
    /// Rough Elo, like "~1600" or "2500+".
    let elo: String
    let blurb: String
    let hue: Color
    let hue2: Color
    /// The color its light casts: Someone at the Table, the Lock Screen game.
    let lightHex: UInt32

    var id: String { slug }

    var isGrudge: Bool { kind == .grudge }

    /// 1 to 5, for the strength bars.
    var strength: Int { level.rawValue + 1 }

    /// The rating as VoiceOver should say it: "about 1600 Elo", "over 2500 Elo".
    var spokenElo: String {
        if elo.hasPrefix("~") { return "about \(elo.dropFirst()) Elo" }
        if elo.hasSuffix("+") { return "over \(elo.dropLast()) Elo" }
        return "\(elo) Elo"
    }

    /// The rival's portrait in Assets.xcassets/Rivals (scripts/make_rival_portraits.py).
    var portraitName: String { "rival-" + slug }

    /// The portrait as light with no backdrop (scripts/make_rival_glows.py), to lay over the board.
    var glowName: String { portraitName + "-glow" }

    var light: Color { Color(hex: lightHex) }

    var lightUI: UIColor {
        UIColor(red: CGFloat((lightHex >> 16) & 0xFF) / 255, green: CGFloat((lightHex >> 8) & 0xFF) / 255,
                blue: CGFloat(lightHex & 0xFF) / 255, alpha: 1)
    }

    /// The Crowd, weakest first.
    static let all: [Rival] = MatchController.Level.allCases.map(\.rival)

    /// The Grudge, playing at about `level`'s strength.
    static func grudge(_ level: MatchController.Level) -> Rival {
        Rival(level: level, kind: .grudge, name: "Your Grudge", shortName: "Grudge", slug: "grudge",
              elo: "~\(level.rating)",
              blurb: "Remembers every game you've played it. Plays at your weak spots.",
              hue: Color(hex: 0xE0313F), hue2: Color(hex: 0x7A0E1A), lightHex: 0xE0313F)
    }

    /// Whether a saved game's opponent was your Grudge.
    static func isGrudge(opponent: String) -> Bool {
        opponent == grudge(.club).name
    }

    /// Who a saved game was against, from its opponent and level. Nil for games with people.
    static func of(saved game: SavedGame) -> Rival? {
        guard let level = game.level.flatMap(MatchController.Level.init(rawValue:)) else { return nil }
        return isGrudge(opponent: game.opponent) ? grudge(level) : level.rival
    }

    /// The rival a saved name stands for: a crowd's slug or name, or "grudge".
    static func named(_ text: String) -> Rival? {
        let key = text.lowercased()
        if key == "grudge" || key == "your grudge" { return grudge(.club) }
        return all.first { $0.slug == key || $0.name.lowercased() == key || $0.shortName.lowercased() == key }
    }
}

extension MatchController.Level {
    /// The Crowd at this level.
    var rival: Rival {
        switch self {
        case .beginner:
            return Rival(level: self, kind: .crowd, name: "The 1000s", shortName: "1000s", slug: "1000s", elo: "~1000",
                         blurb: "Real players finding their feet. They leave pieces hanging, like people do.",
                         hue: Color(hex: 0xEBD3A0), hue2: Color(hex: 0xC9A35E), lightHex: 0xF0C987)
        case .casual:
            return Rival(level: self, kind: .crowd, name: "The 1200s", shortName: "1200s", slug: "1200s", elo: "~1200",
                         blurb: "Weekend players. They know an opening or two, then wander.",
                         hue: Color(hex: 0xE6C483), hue2: Color(hex: 0xBF9448), lightHex: 0xF2C27A)
        case .club:
            return Rival(level: self, kind: .crowd, name: "The 1600s", shortName: "1600s", slug: "1600s", elo: "~1600",
                         blurb: "Club players. Solid openings, then the slips real people make.",
                         hue: Color(hex: 0xDDB46A), hue2: Color(hex: 0xB0823A), lightHex: 0xF0B862)
        case .expert:
            return Rival(level: self, kind: .crowd, name: "The 2000s", shortName: "2000s", slug: "2000s", elo: "~2000",
                         blurb: "Strong players. Sharp, patient, and they rarely hand you a piece.",
                         hue: Color(hex: 0xD6A24A), hue2: Color(hex: 0xA6722C), lightHex: 0xEDA94E)
        case .grandmaster:
            return Rival(level: self, kind: .crowd, name: "The Masters", shortName: "Masters", slug: "masters", elo: "2500+",
                         blurb: "Grandmasters' games, then full Stockfish when the book runs out.",
                         hue: Color(hex: 0xF2DCA8), hue2: Color(hex: 0xD6B26A), lightHex: 0xF6DDA6)
        }
    }
}

/// A rival's small emblem: for The Crowd a ring of gold dots (more players, more dots), for the
/// Grudge its onyx king in red light. Drawn in a 100-point space and scaled to `size`.
struct RivalSigil: View {
    let rival: Rival
    var size: CGFloat = 84
    var glows = true

    var body: some View {
        Group {
            if rival.isGrudge {
                GrudgeKing(scars: 3, size: size, light: 0.8)
            } else {
                CrowdRing(dots: 26 + rival.strength * 12, hue: rival.hue)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: glows ? rival.hue.opacity(0.6) : .clear, radius: size * 0.06)
        .accessibilityHidden(true)
    }
}

/// A still ring of dots, scattered the same way every time.
struct CrowdRing: View {
    let dots: Int
    let hue: Color

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var seed: UInt64 = 0x9E37_79B9
            for _ in 0..<dots {
                let angle = CrowdRing.next(&seed) * .pi * 2
                let reach = 0.27 + pow(CrowdRing.next(&seed), 0.7) * 0.2
                let radius = side * (0.8 + CrowdRing.next(&seed) * 0.9) / 100
                let point = CGPoint(x: center.x + cos(angle) * side * reach, y: center.y + sin(angle) * side * reach)
                let dot = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: dot), with: .color(hue.opacity(0.45 + CrowdRing.next(&seed) * 0.55)))
            }
        }
    }

    /// A number in 0..<1 from a small fixed generator, so the ring never shimmers between draws.
    static func next(_ state: inout UInt64) -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

/// A rival's portrait: a rounded square picture with a soft edge in the rival's color.
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

#Preview("Sigils") {
    HStack(spacing: 16) {
        ForEach(Rival.all) { rival in
            RivalSigil(rival: rival, size: 64)
        }
        RivalSigil(rival: .grudge(.club), size: 64)
    }
    .padding(30)
    .background(Color.black)
}

extension String {
    /// The name as an owner: "Your Grudge's", "The 1600s'".
    var possessive: String { hasSuffix("s") ? self + "'" : self + "'s" }
}
