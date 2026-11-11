import SwiftUI
import UIKit

/// Who the person plays against the computer: a rival at one rating.
///
/// The five rivals climb from the Cub to the Ashen King, each a warrior wearing the beast it
/// hunted, struck on a coin that darkens from bronze to onyx and gold (Alex, 2026-11-07). Behind
/// each one is a crowd of real people: its moves come from games real players at that rating
/// played in the same position (Lichess's database, see `CrowdBook`), and Stockfish takes over at the
/// same strength once the position is one nobody has reached.
struct Rival: Identifiable {
    let level: MatchController.Level
    /// "The Berserker", "The Ashen King".
    let name: String
    /// A short name for tight places, like the home's ladder: "Berserker", "Ashen King".
    let shortName: String
    /// What the rival was called before it had a face, "The 1600s": saved games from then
    /// still carry it.
    var formerName: String?
    /// Names it had since, for saved games and wins from then: the Ashen King was the
    /// Dragonlord until 2026-11-08.
    var laterFormerNames: [String] = []

    /// Every name this rival had before today's.
    var pastNames: [String] { (formerName.map { [$0] } ?? []) + laterFormerNames }
    /// Names the rival's pictures: "1600s", "masters".
    let slug: String
    /// Rough Elo, like "~1600" or "2500+".
    let elo: String
    let blurb: String
    let hue: Color
    let hue2: Color
    /// The color its light casts: Someone at the Table, the Lock Screen game.
    let lightHex: UInt32

    var id: String { slug }

    /// The rival's gold for words and small marks. The pale gold is made for a dark page; on a
    /// light one "Beginner" and the strength bars all but vanished, so there the pieces' deeper
    /// metal stands in.
    func ink(on theme: BoardTheme) -> Color {
        theme.screenIsDark ? hue : theme.trainingAccent
    }

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

    /// The rival's coin with no backdrop (Assets.xcassets/Rivals).
    var coinName: String { "rival-" + slug + "-coin" }

    /// The portrait as light with no backdrop (scripts/make_rival_glows.py), to lay over the board.
    var glowName: String { portraitName + "-glow" }

    var light: Color { Color(hex: lightHex) }

    var lightUI: UIColor {
        UIColor(red: CGFloat((lightHex >> 16) & 0xFF) / 255, green: CGFloat((lightHex >> 8) & 0xFF) / 255,
                blue: CGFloat(lightHex & 0xFF) / 255, alpha: 1)
    }

    /// The Crowd, weakest first.
    static let all: [Rival] = MatchController.Level.allCases.map(\.rival)

    /// The name to show for a saved game's opponent: a rival's name today, even for a game
    /// saved under its former name, and anyone else's as it was saved.
    static func shownName(of game: SavedGame) -> String {
        guard let rival = of(saved: game), rival.pastNames.contains(game.opponent) else { return game.opponent }
        return rival.name
    }

    /// Who a saved game was against, from its opponent and level. Nil for games with people.
    static func of(saved game: SavedGame) -> Rival? {
        guard let level = game.level.flatMap(MatchController.Level.init(rawValue:)) else { return nil }
        return level.rival
    }

    /// The rival a saved name stands for: a crowd's slug or name.
    static func named(_ text: String) -> Rival? {
        let key = text.lowercased()
        return all.first {
            $0.slug == key || $0.name.lowercased() == key || $0.shortName.lowercased() == key
                || $0.pastNames.contains { $0.lowercased() == key }
        }
    }
}

extension SavedGame {
    /// Who this game was against, as the app names them now (see `Rival.shownName(of:)`).
    var opponentShown: String { Rival.shownName(of: self) }
}

extension MatchController.Level {
    /// The rival at this level.
    var rival: Rival {
        switch self {
        case .beginner:
            return Rival(level: self, name: "The Cub", shortName: "Cub",
                         formerName: "The 1000s", slug: "1000s", elo: "~1000",
                         blurb: "Real players finding their feet. They leave pieces hanging, like people do.",
                         hue: Color(hex: 0xEBD3A0), hue2: Color(hex: 0xC9A35E), lightHex: 0xF0C987)
        case .casual:
            return Rival(level: self, name: "The Hunter", shortName: "Hunter",
                         formerName: "The 1200s", slug: "1200s", elo: "~1200",
                         blurb: "Weekend players. They know an opening or two, then wander.",
                         hue: Color(hex: 0xE6C483), hue2: Color(hex: 0xBF9448), lightHex: 0xF2C27A)
        case .club:
            return Rival(level: self, name: "The Berserker", shortName: "Berserker",
                         formerName: "The 1600s", slug: "1600s", elo: "~1600",
                         blurb: "Club players. Solid openings, then the slips real people make.",
                         hue: Color(hex: 0xDDB46A), hue2: Color(hex: 0xB0823A), lightHex: 0xF0B862)
        case .expert:
            return Rival(level: self, name: "The Lionheart", shortName: "Lionheart",
                         formerName: "The 2000s", slug: "2000s", elo: "~2000",
                         blurb: "Strong players. Sharp, patient, and they rarely hand you a piece.",
                         hue: Color(hex: 0xD6A24A), hue2: Color(hex: 0xA6722C), lightHex: 0xEDA94E)
        case .grandmaster:
            // Renamed from the Dragonlord, his dragon-skull helm gone for a crown of bone grown
            // from his own skull (Alex, 2026-11-08).
            return Rival(level: self, name: "The Ashen King", shortName: "Ashen King",
                         formerName: "The Masters", laterFormerNames: ["The Dragonlord"], slug: "masters", elo: "2500+",
                         blurb: "Grandmasters' games, then full Stockfish when the book runs out.",
                         hue: Color(hex: 0xF2DCA8), hue2: Color(hex: 0xD6B26A), lightHex: 0xF6DDA6)
        }
    }
}

/// A rival's small emblem: its coin.
struct RivalSigil: View {
    let rival: Rival
    var size: CGFloat = 84
    var glows = true

    var body: some View {
        RivalCoin(rival: rival, size: size)
            .frame(width: size, height: size)
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

/// A rival's struck coin, cut out so a beast's ears or horns may rise past its rim, resting on
/// a soft shadow.
struct RivalCoin: View {
    let rival: Rival
    let size: CGFloat

    var body: some View {
        Image(rival.coinName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .shadow(color: .black.opacity(0.28), radius: size * 0.04, y: size * 0.03)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A rival's portrait: its coin.
struct RivalPortrait: View {
    let rival: Rival
    var size: CGFloat = 92
    var glows = true

    var body: some View {
        RivalCoin(rival: rival, size: size)
    }
}

#Preview("Sigils") {
    HStack(spacing: 16) {
        ForEach(Rival.all) { rival in
            RivalSigil(rival: rival, size: 64)
        }
    }
    .padding(30)
    .background(Color.black)
}

extension String {
    /// The name as an owner: "The Hunter's", "The 1600s'".
    var possessive: String { hasSuffix("s") ? self + "'" : self + "'s" }
}
