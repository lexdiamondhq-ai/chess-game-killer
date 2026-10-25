import Foundation

extension ArmyNews {
    /// The rule behind the news, for the banner's second line: what it means and what to do,
    /// said before the game it matters in. Nil for news that needs no explaining.
    var rule: String? {
        switch kind {
        case .grudge(let rival, _):
            return "Beat \(rival) with \(name) making a capture for bonus XP."
        case .staked(let rival):
            return "Win: double XP and a trophy. Lose: \(rival) keeps \(name) until you win it back."
        case .captured:
            return "Until then it earns no XP."
        case .promoted, .revenge, .wonStake, .rescued:
            return nil
        }
    }
}
