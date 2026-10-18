import Foundation

// The training content, as stored in ChessGameKiller/Training/Content.
// Everything a learner sees (lessons, drills, the coach's words) is data, so
// it can grow without touching code. scripts/training/verify_training.py
// checks every position and move in it.

/// The whole course: the coach, the units in journey order, the skills and the coach's lines.
struct Course: Decodable {
    let coach: CoachProfile
    let habit: [HabitLight]
    let units: [CourseUnit]
    let skills: [Skill]
    let ranks: [Rank]
    let lines: CoachLines
    let moments: [MomentText]
}

struct CoachProfile: Decodable {
    let name: String
    let title: String
    let tagline: String
}

/// One light of the Traffic Light habit: red (their threats), yellow (my chances), green (is my move safe?).
struct HabitLight: Decodable, Identifiable {
    let id: String
    let title: String
    let question: String
    let detail: String
}

struct CourseUnit: Decodable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let color: TrainingColor
    let lessons: [String]
    let skills: [String]
}

struct Skill: Decodable, Identifiable {
    let id: String
    let title: String
    let blurb: String
    let symbol: String
    let lesson: String
    /// What a drill of this skill asks, like "Find the fork."
    let prompt: String
    /// The two answers for yes-or-no drills, like "Safe" and "Not safe".
    let yes: String?
    let no: String?
}

/// Ranks named after the pieces: a learner starts as a Pawn and gets promoted.
struct Rank: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let piece: String
    let xp: Int
}

struct CoachLines: Decodable {
    let greeting: [String]
    let correct: [String]
    let correctAfterHint: [String]
    /// Between the moves of a longer puzzle.
    let keepGoing: [String]
    let wrong: [String]
    let tilt: [String]
    let sessionDone: [String]
    let lessonDone: [String]
    let restDay: [String]
    let promotion: [String]
}

/// What the coach says when it spots a pattern in a game. `detail` can use
/// {played}, {best}, {reply}, {piece}, {square}, {targets} and {n}.
struct MomentText: Decodable {
    let kind: String
    let title: String
    let detail: String
}

/// Named colors shared by lessons, drills and units, drawn in each board theme's style.
enum TrainingColor: String, Decodable, CaseIterable {
    case red, yellow, green, blue, violet, teal, orange, pink
}

// MARK: Lessons

/// A short narrated lesson, played like a video: the coach talks, pieces move,
/// arrows appear, and every so often it's the learner's turn.
struct Lesson: Decodable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let skill: String
    /// Which side sits at the bottom of the board. White unless the lesson says otherwise.
    let orientation: SideName?
    let steps: [LessonStep]
}

enum SideName: String, Decodable {
    case white, black
}

struct LessonStep: Decodable {
    /// A new position to show. Steps without one carry on from the last position.
    let fen: String?
    /// What the coach says while the step plays.
    let say: String?
    /// Moves to animate, in engine notation ("e2e4").
    let moves: [String]?
    let arrows: [BoardArrow]?
    let marks: [SquareMark]?
    let labels: [SquareLabel]?
    /// Extra seconds to hold the step after the coach finishes talking.
    let pause: Double?
    /// When set, the lesson waits for the learner to do something.
    let task: LessonTask?
}

struct BoardArrow: Decodable, Hashable {
    let from: String
    let to: String
    let color: TrainingColor?
    let dashed: Bool?
}

struct SquareMark: Decodable, Hashable {
    let square: String
    let color: TrainingColor?
}

struct SquareLabel: Decodable, Hashable {
    let square: String
    let text: String
    let color: TrainingColor?
}

struct LessonTask: Decodable {
    enum Kind: String, Decodable {
        /// Play the right move (or moves).
        case move
        /// Tap the right squares.
        case tap
        /// Pick an answer.
        case choice
    }

    let type: Kind
    let prompt: String
    /// For `move`: the learner's moves and the opponent's replies, alternating, learner first.
    let solution: [String]?
    /// For `move`: other moves that also solve it, one list per learner move.
    let accept: [[String]]?
    /// For `move`: any checkmate solves the last step.
    let mate: Bool?
    /// For `tap`: the squares to find.
    let squares: [String]?
    /// For `choice`.
    let options: [ChoiceOption]?
    let hint: String?
    let success: String
    let wrong: String?
    /// Specific answers to specific wrong moves, keyed by the move ("d4b6").
    let feedback: [String: String]?
}

struct ChoiceOption: Decodable, Hashable {
    let text: String
    /// Drawn on the board as an arrow, when set.
    let move: String?
    let correct: Bool
    let why: String?
}

// MARK: Drills

/// One practice item. Most come from real (engine) games and were checked with Stockfish.
struct Drill: Decodable, Identifiable, Hashable {
    enum Kind: String, Decodable {
        /// Find the best move, sometimes a short sequence.
        case move
        /// Tap the right squares, like the piece their last move attacks.
        case tap
        /// Say whether a move is safe (or a capture is good).
        case safe
        /// Pick one of a few moves.
        case choice
        /// Play it out against the computer, like checkmating with a queen.
        case playout
    }

    let id: String
    let skill: String
    let type: Kind
    /// Difficulty on the puzzle-rating scale: about 400 is easy, 1600 is hard.
    let rating: Int
    let fen: String
    /// The opponent's move that sets up the drill, shown first.
    let setup: String?
    let solution: [String]?
    let alts: [[String]]?
    let mate: Int?
    let squares: [String]?
    let move: String?
    let answer: Bool?
    /// The opponent's reply that shows why a move was unsafe.
    let reply: String?
    let explain: String?
    let options: [ChoiceOption]?
    let prompt: String?
    /// For `playout`: moves allowed to finish the job.
    let limit: Int?

    static func == (lhs: Drill, rhs: Drill) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct DrillFile: Decodable {
    let drills: [Drill]
}
