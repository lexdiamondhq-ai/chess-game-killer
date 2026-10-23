import ChessKit
import Foundation
import Observation

/// The player's coach: Leo or Vera. Both teach the same course; each has a name, a voice
/// (recorded with ElevenLabs by scripts/training/make_narration.py), a piece for a portrait
/// and short spoken reactions in puzzles and drills.
enum Coach: String, CaseIterable, Identifiable, Codable, Sendable {
    case leo
    case vera

    var id: String { rawValue }

    var name: String {
        switch self {
        case .leo: return "Leo"
        case .vera: return "Vera"
        }
    }

    /// "Coach Leo".
    var title: String { "Coach \(name)" }

    /// One line on who they are, for the picker.
    var blurb: String {
        switch self {
        case .leo: return "A warm British grandmaster with a story for every mistake."
        case .vera: return "Quick, sharp and on your side. Named for Vera Menchik, the first women's world champion."
        }
    }

    /// "he" or "she", for lines like "She checks every part."
    var subject: String { self == .leo ? "he" : "she" }
    var subjectCapitalized: String { self == .leo ? "He" : "She" }
    /// "his" or "her".
    var possessive: String { self == .leo ? "his" : "her" }

    /// The piece in the coach's portrait: Leo is the knight, Vera the queen.
    var piece: Piece.Kind { self == .leo ? .knight : .queen }

    /// Recordings start with this, then 12 hex digits of the line's SHA-1.
    /// Leo's were recorded first, so his keep the original "nar-".
    var filePrefix: String { self == .leo ? "nar-" : "vera-" }

    /// The course is written in Leo's words. For another coach, his name becomes theirs.
    /// make_narration.py's personalize() does the same, so the recordings match.
    func personalize(_ text: String) -> String {
        guard self != .leo else { return text }
        return text.replacingOccurrences(of: #"\bLeo\b"#, with: name, options: .regularExpression)
    }
}

/// Which coach the player picked, saved on the device. Views that read it redraw when it changes.
/// Changed only from the screen (the pickers); read anywhere.
@Observable
final class CoachChoice {
    static let shared = CoachChoice()
    static let storageKey = "coach"

    @ObservationIgnored private let defaults: UserDefaults

    var coach: Coach {
        didSet { defaults.set(coach.rawValue, forKey: Self.storageKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        coach = defaults.string(forKey: Self.storageKey).flatMap(Coach.init(rawValue:)) ?? .leo
    }
}

extension Coach {
    /// The coach the player picked. A view that reads it redraws when it changes.
    static var current: Coach { CoachChoice.shared.coach }
}
