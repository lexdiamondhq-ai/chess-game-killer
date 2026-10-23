import AVFoundation
import Foundation

/// A moment in a puzzle or drill the coach can react to out loud.
enum ReactionMoment: String, CaseIterable, Codable, Sendable {
    /// The coach says hello: in the picker, to hear the voice.
    case hello
    /// Solved on the first try.
    case nice
    /// Solved a long puzzle on the first try, every move right.
    case brilliant
    /// The third first-try solve in a row (every fifth in Puzzle Rush). The policy turns a `nice` into this.
    case streak
    /// A right move in the middle of a longer puzzle.
    case keepGoing
    /// Solved, after a hint or a miss.
    case afterHelp
    /// The first wrong answer in a puzzle.
    case tryAgain
    /// A wrong move that just gives a piece away.
    case blunder
    /// Out of tries: the answer is shown.
    case missed
}

/// Every coach's reactions, from Training/Content/reactions.json.
struct ReactionLines: Decodable {
    let coaches: [String: [String: [String]]]

    func lines(for coach: Coach, _ moment: ReactionMoment) -> [String] {
        coaches[coach.rawValue]?[moment.rawValue] ?? []
    }

    static let bundled: ReactionLines? = {
        guard let url = Bundle.main.url(forResource: "reactions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ReactionLines.self, from: data)
    }()
}

/// When the coach speaks up, and with which line. A reaction every move would get old fast, so:
/// big moments (brilliant, a streak, a blunder) always get one; ordinary ones only some of the
/// time; never two within a few seconds; never the same line twice in a row; and Puzzle Rush,
/// which is quick, hears far less.
struct ReactionPolicy {
    /// From 0 up to 1, so tests can decide.
    var random: () -> Double = { Double.random(in: 0..<1) }

    private(set) var lastSpoken: Date?
    private var lastLine: [ReactionMoment: String] = [:]
    private var lastBlunder: Date?
    private var firstTryRun = 0

    init(random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
    }

    /// Seconds of quiet after a reaction before an ordinary one may follow.
    static let gap: TimeInterval = 3.5
    /// Pointing out a hanging piece stings, so at most one this often; a second becomes "Try again".
    static let blunderGap: TimeInterval = 90
    /// After this long without a reaction it's a new sitting, and the first solve always gets one.
    static let newSitting: TimeInterval = 600

    /// The line to say for `moment`, or nil to stay quiet. Remembers what it chose.
    mutating func line(for moment: ReactionMoment, strict: Bool = false, now: Date = .now,
                       lines: (ReactionMoment) -> [String]) -> String? {
        let quiet = lastSpoken.map { now.timeIntervalSince($0) } ?? .infinity
        let freshSitting = quiet > Self.newSitting
        if freshSitting { firstTryRun = 0 }

        var moment = moment
        switch moment {
        case .nice, .brilliant:
            firstTryRun += 1
            if moment == .nice, firstTryRun.isMultiple(of: strict ? 5 : 3) { moment = .streak }
        case .tryAgain, .blunder, .missed, .afterHelp:
            firstTryRun = 0
        case .hello, .streak, .keepGoing:
            break
        }
        if moment == .blunder, let last = lastBlunder, now.timeIntervalSince(last) < Self.blunderGap {
            moment = .tryAgain
        }

        let big = moment == .brilliant || moment == .streak || moment == .blunder || moment == .hello
        guard quiet >= (big ? 1 : Self.gap) else { return nil }
        guard random() < chance(of: moment, strict: strict, freshSitting: freshSitting) else { return nil }

        let options = lines(moment)
        guard !options.isEmpty else { return nil }
        let fresh = options.count > 1 ? options.filter { $0 != lastLine[moment] } : options
        let index = min(fresh.count - 1, Int(random() * Double(fresh.count)))
        let line = fresh[max(0, index)]

        lastLine[moment] = line
        lastSpoken = now
        if moment == .blunder { lastBlunder = now }
        return line
    }

    private func chance(of moment: ReactionMoment, strict: Bool, freshSitting: Bool) -> Double {
        switch moment {
        case .hello, .brilliant, .streak: return 1
        case .blunder: return strict ? 0.6 : 1
        case .nice: return freshSitting ? 1 : (strict ? 0.2 : 0.55)
        case .tryAgain: return strict ? 0 : 0.7
        case .afterHelp: return strict ? 0 : 0.45
        case .keepGoing: return strict ? 0 : 0.3
        case .missed: return 0.5
        }
    }
}

/// Something that hears what happens in a drill. DrillRunner tells it; CoachReactions speaks.
@MainActor
protocol Reacting: AnyObject {
    func react(_ moment: ReactionMoment, strict: Bool)
}

/// The coach's short spoken reactions in puzzles and drills: "Nice move", "Try again",
/// "Brilliant!", "That piece is hanging". Recorded lines only, played like the game's sound
/// effects (they follow the silent switch and mix with music). Off with the "Voice reactions"
/// switch, or when the coach's voice is muted; quiet while the coach is talking.
@MainActor
final class CoachReactions: Reacting {
    static let shared = CoachReactions()
    static let storageKey = "voiceReactions"

    /// The "Voice reactions" switch. On unless the player turned it off.
    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    private var policy = ReactionPolicy()
    private var player: AVAudioPlayer?
    private let lines: ReactionLines?

    init(lines: ReactionLines? = .bundled) {
        self.lines = lines
    }

    func react(_ moment: ReactionMoment, strict: Bool) {
        guard Self.isOn, !CoachVoice.shared.isMuted, !CoachVoice.shared.isSpeaking else { return }
        let coach = Coach.current
        guard let line = policy.line(for: moment, strict: strict, lines: { self.lines?.lines(for: coach, $0) ?? [] })
        else { return }
        play(line, coach: coach)
    }

    /// The coach says hello, so the player can hear the voice before picking it.
    func preview(_ coach: Coach) {
        guard let line = lines?.lines(for: coach, .hello).first else { return }
        CoachVoice.shared.stop()
        play(line, coach: coach)
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func play(_ line: String, coach: Coach) {
        guard let url = CoachVoice.recording(for: line, coach: coach),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        self.player?.stop()
        player.volume = 0.9
        player.prepareToPlay()
        self.player = player
        player.play()
    }
}
