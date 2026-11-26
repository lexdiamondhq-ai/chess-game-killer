import Foundation

/// The ruler Chess DNA measures against: where real players sit on each habit, each of the
/// six areas and each pattern, so a bar can say "better than 7 in 10 players" where it used
/// to say a fixed word that most players shared.
///
/// Measured once, in November 2026, on 3,096 online games from 155 players rated about 860
/// to 2440 (their 20 newest games each), graded move by move the way the app grades and read
/// with the app's own rules. Each ruler is the measure's value at every twentieth of those
/// players, lowest first. A new rule needs a new measurement before it gets a ruler here.
enum RealPlayers {
    static let players = 155
    static let games = 3_096

    /// Where a value sits among the players measured.
    struct Standing: Equatable {
        /// The share of real players below it, and above it, 0 to 1. Players level with it
        /// are in neither, so a score most players share isn't "better than most".
        let below: Double
        let above: Double

        /// Where to draw it on a bar, 0 to 1: players level with it count half. The typical
        /// player sits in the middle.
        var place: Double { (below + 1 - above) / 2 }

        /// Clearly past most players, or clearly behind them. In between is "like most".
        var isAhead: Bool { below >= Self.clear }
        var isBehind: Bool { above >= Self.clear }

        /// The share of players that has to be on the other side before a bar says so.
        static let clear = 0.65

        /// Players in ten on the far side of this one, for "better than 7 in 10": 6 to 9.
        static func inTen(_ share: Double) -> Int {
            min(9, max(6, Int((share * 10 + 1e-9).rounded(.down))))
        }

        /// A few words for one of the six areas.
        var words: String {
            if isAhead { return "Better than \(Self.inTen(below)) in 10" }
            if isBehind { return "Below most players" }
            return "Like most players"
        }
    }

    /// One measure across the players: its value at every twentieth of them, lowest first.
    struct Ruler: Equatable {
        let marks: [Double]

        func standing(of value: Double) -> Standing {
            guard let lowest = marks.first, let highest = marks.last, marks.count > 1 else {
                return Standing(below: 0.5, above: 0.5)
            }
            if value < lowest { return Standing(below: 0, above: 1) }
            if value > highest { return Standing(below: 1, above: 0) }
            let steps = Double(marks.count - 1)
            // Both exist: the value is within the ruler.
            let first = marks.firstIndex { $0 >= value } ?? 0
            let last = marks.lastIndex { $0 <= value } ?? marks.count - 1
            if marks[first] == value {
                // Level with one or more marks: everyone from the first to the last is a tie.
                return Standing(below: Double(first) / steps, above: 1 - Double(last) / steps)
            }
            // Between two marks next to each other.
            let position = (Double(last) + (value - marks[last]) / (marks[first] - marks[last])) / steps
            return Standing(below: position, above: 1 - position)
        }
    }

    // MARK: The four habits

    /// Checks, captures and moves into the other half, as a share of the player's moves.
    static let aggression = Ruler(marks: [0.308, 0.377, 0.402, 0.419, 0.436, 0.441, 0.447, 0.453, 0.462, 0.473, 0.480,
                                          0.484, 0.491, 0.497, 0.507, 0.520, 0.530, 0.552, 0.560, 0.585, 0.712])
    /// Late castling, sound sacrifices and an early queen, per game.
    static let risk = Ruler(marks: [0.045, 0.082, 0.118, 0.142, 0.165, 0.185, 0.208, 0.223, 0.235, 0.248, 0.261,
                                    0.289, 0.309, 0.320, 0.342, 0.354, 0.377, 0.393, 0.433, 0.458, 0.650])
    /// Long games with few early trades.
    static let patience = Ruler(marks: [0.180, 0.218, 0.244, 0.263, 0.275, 0.296, 0.308, 0.315, 0.326, 0.340, 0.347,
                                        0.365, 0.379, 0.395, 0.410, 0.421, 0.456, 0.484, 0.501, 0.523, 0.602])
    /// Of the games where the player stood clearly worse, the share they still won or drew.
    static let comebacks = Ruler(marks: [0.000, 0.068, 0.111, 0.133, 0.167, 0.207, 0.231, 0.250, 0.267, 0.286, 0.308,
                                         0.333, 0.353, 0.383, 0.400, 0.429, 0.462, 0.500, 0.541, 0.654, 0.778])

    // MARK: The six areas

    /// The area's score in `CoachReport`, over a player's 20 newest games.
    static func area(_ area: CoachReport.Area) -> Ruler {
        switch area {
        case .safety:
            return Ruler(marks: [0.048, 0.165, 0.199, 0.248, 0.287, 0.309, 0.323, 0.362, 0.380, 0.403, 0.427,
                                 0.442, 0.463, 0.497, 0.522, 0.565, 0.597, 0.658, 0.741, 0.929, 1.000])
        case .tactics:
            return Ruler(marks: [0.344, 0.513, 0.540, 0.568, 0.600, 0.617, 0.639, 0.656, 0.659, 0.670, 0.693,
                                 0.705, 0.729, 0.742, 0.766, 0.785, 0.812, 0.846, 0.905, 0.940, 1.000])
        case .checkmates:
            // More than half the players never missed a short mate in 20 games: they tie at the top.
            return Ruler(marks: [0.854, 0.905, 0.926, 0.946, 0.951, 0.951, 0.966, 0.981, 0.983, 1.000, 1.000,
                                 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000])
        case .openings:
            return Ruler(marks: [0.115, 0.187, 0.220, 0.247, 0.275, 0.316, 0.331, 0.355, 0.374, 0.387, 0.413,
                                 0.448, 0.459, 0.465, 0.497, 0.531, 0.549, 0.616, 0.677, 0.757, 1.000])
        case .endgames:
            return Ruler(marks: [0.056, 0.097, 0.132, 0.159, 0.189, 0.202, 0.222, 0.248, 0.281, 0.296, 0.329,
                                 0.368, 0.385, 0.420, 0.444, 0.486, 0.567, 0.627, 0.676, 0.846, 1.000])
        case .calculation:
            return Ruler(marks: [0.061, 0.102, 0.115, 0.133, 0.152, 0.157, 0.167, 0.176, 0.193, 0.207, 0.219,
                                 0.240, 0.264, 0.280, 0.299, 0.316, 0.352, 0.414, 0.479, 0.632, 1.000])
        }
    }

    // MARK: Patterns

    /// How often real players play a pattern when it is on the board: the usual share, and
    /// how far players spread around it.
    struct FindRate: Equatable {
        let typical: Double
        let spread: Double

        /// How far a player's share sits past the usual one, in spreads.
        func lead(of share: Double) -> Double { (share - typical) / spread }
    }

    static let forks = FindRate(typical: 0.77, spread: 0.19)
    static let freePieces = FindRate(typical: 0.66, spread: 0.15)
    static let mates = FindRate(typical: 0.78, spread: 0.23)
}
