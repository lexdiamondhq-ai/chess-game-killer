import Foundation

// Cycles: the Woodpecker Method from Axel Smith and Hans Tikkanen's book. Solve a
// fixed set of puzzles, rest, then solve the same set again in half the time,
// and again, until the patterns are instant.
//
// Saved data: these types are written to puzzle-cycles.json. A field added later
// must be optional or read with decodeIfPresent, so older files keep loading.

/// How many puzzles a set holds.
enum PuzzleCycleSize: Int, CaseIterable, Identifiable, Codable {
    case short = 20
    case standard = 40
    case long = 80

    var id: Int { rawValue }

    var count: Int { rawValue }

    var name: String {
        switch self {
        case .short: return "Short"
        case .standard: return "Standard"
        case .long: return "Long"
        }
    }
}

/// One puzzle played in a cycle.
struct PuzzleCycleAttempt: Codable, Equatable {
    let id: String
    /// Solved with no wrong move and without asking for the answer.
    let clean: Bool
    /// Thinking time: the clock only runs while it's the player's move.
    let seconds: TimeInterval
}

/// One pass through the set.
struct PuzzleCycleRun: Codable, Equatable {
    /// The set's puzzles, in the order this cycle plays them.
    let order: [String]
    /// The time to beat; nil for the first cycle, played at the player's own pace.
    let target: TimeInterval?
    let started: Date
    var attempts: [PuzzleCycleAttempt] = []
    /// Time already spent on the puzzle up next, from a visit that ended part way through it.
    var carried: TimeInterval = 0
    var finished: Date?

    var isFinished: Bool { attempts.count >= order.count }

    var nextPuzzleID: String? { isFinished ? nil : order[attempts.count] }

    /// The cycle's time so far.
    var elapsed: TimeInterval { attempts.reduce(carried) { $0 + $1.seconds } }

    var cleanCount: Int { attempts.filter(\.clean).count }

    /// Clean solves out of the puzzles played, from 0 to 1.
    var accuracy: Double {
        attempts.isEmpty ? 0 : Double(cleanCount) / Double(attempts.count)
    }

    /// Whether the cycle came in under its target; nil without one.
    var beatTarget: Bool? { target.map { elapsed <= $0 } }

    /// The same cycle with one puzzle taken out.
    func without(_ puzzleID: String, now: Date) -> PuzzleCycleRun {
        var run = PuzzleCycleRun(order: order.filter { $0 != puzzleID }, target: target, started: started)
        run.attempts = attempts.filter { $0.id != puzzleID }
        run.carried = nextPuzzleID == puzzleID ? 0 : carried
        run.finished = finished ?? (run.isFinished ? now : nil)
        return run
    }
}

/// A Woodpecker set: the same puzzles solved cycle after cycle, each cycle
/// aiming for half the time of the one before, until the targets reach a
/// few seconds a puzzle or five cycles are done.
struct PuzzleCycleSet: Codable, Equatable, Identifiable {
    static let maxCycles = 5
    /// The quickest a target goes: a moment to take in the position, then two
    /// seconds for each move to play.
    static let floorPerPuzzle: TimeInterval = 2
    static let floorPerMove: TimeInterval = 2
    /// How far below the player's puzzle rating a set is built: recognition, not struggle.
    static let ratingBelow = 200

    enum Stage: Equatable {
        /// A cycle under way; `puzzle` is the one up next, counting from 1.
        case playing(cycle: Int, puzzle: Int)
        /// A cycle finished and the next one not started yet.
        case between(next: Int, target: TimeInterval)
        /// Every cycle played.
        case complete
    }

    let id: UUID
    let created: Date
    /// The puzzle rating the set was built around.
    let level: Int
    private(set) var puzzleIDs: [String]
    /// No target goes below this many seconds.
    private(set) var floor: TimeInterval
    private(set) var cycles: [PuzzleCycleRun]

    init(id: UUID = UUID(), created: Date, level: Int, puzzleIDs: [String], floor: TimeInterval, cycles: [PuzzleCycleRun]) {
        self.id = id
        self.created = created
        self.level = level
        self.puzzleIDs = puzzleIDs
        self.floor = floor
        self.cycles = cycles
    }

    var count: Int { puzzleIDs.count }

    /// The cycle being played, or the last one played.
    var currentRun: PuzzleCycleRun? { cycles.last }

    var finishedRuns: [PuzzleCycleRun] { cycles.filter(\.isFinished) }

    var stage: Stage {
        guard let last = cycles.last, !puzzleIDs.isEmpty else { return .complete }
        if !last.isFinished {
            return .playing(cycle: cycles.count, puzzle: last.attempts.count + 1)
        }
        if let target = nextTarget {
            return .between(next: cycles.count + 1, target: target)
        }
        return .complete
    }

    var isComplete: Bool { stage == .complete }

    /// The target for the cycle after the last one finished: half its time,
    /// never below the floor. Nil when the set is done, after five cycles or
    /// once a cycle has been played against the floor.
    var nextTarget: TimeInterval? {
        guard let last = cycles.last, last.isFinished, cycles.count < Self.maxCycles, !puzzleIDs.isEmpty else { return nil }
        if let target = last.target, target <= floor { return nil }
        return max(floor, (last.elapsed / 2).rounded())
    }

    // MARK: Playing

    /// Counts the puzzle up next as played, with any time carried over from
    /// an earlier visit. Ignored for any other puzzle, so a late call can't
    /// skip one. True when it was recorded.
    @discardableResult
    mutating func record(_ puzzleID: String, clean: Bool, seconds: TimeInterval, now: Date) -> Bool {
        guard var run = cycles.last, run.nextPuzzleID == puzzleID else { return false }
        run.attempts.append(PuzzleCycleAttempt(id: puzzleID, clean: clean, seconds: max(0, seconds) + run.carried))
        run.carried = 0
        if run.isFinished { run.finished = now }
        cycles[cycles.count - 1] = run
        return true
    }

    /// Keeps the time spent on the puzzle up next when the player leaves part way through it.
    mutating func carry(_ seconds: TimeInterval) {
        guard seconds > 0, var run = cycles.last, !run.isFinished else { return }
        run.carried += seconds
        cycles[cycles.count - 1] = run
    }

    /// Starts the next cycle: the same puzzles in a new order, with half the
    /// last cycle's time to beat. False when the set is done or a cycle is still being played.
    @discardableResult
    mutating func startNextCycle(now: Date, using generator: inout some RandomNumberGenerator) -> Bool {
        guard let target = nextTarget, let last = cycles.last else { return false }
        let order = Self.reshuffled(puzzleIDs, after: last.order, using: &generator)
        cycles.append(PuzzleCycleRun(order: order, target: target, started: now))
        return true
    }

    /// Takes out a puzzle the pack no longer has (after an update), with its share of the floor.
    mutating func remove(_ puzzleID: String, now: Date) {
        guard puzzleIDs.contains(puzzleID) else { return }
        floor = (floor * Double(puzzleIDs.count - 1) / Double(puzzleIDs.count)).rounded()
        puzzleIDs.removeAll { $0 == puzzleID }
        cycles = cycles.map { $0.without(puzzleID, now: now) }
    }

    /// A new order for the next cycle, so the set isn't remembered by its
    /// sequence: never the last cycle's order, and never opening with the
    /// puzzle that just closed it.
    static func reshuffled(_ ids: [String], after previous: [String],
                           using generator: inout some RandomNumberGenerator) -> [String] {
        guard ids.count > 2 else { return ids.reversed() }
        var order = ids
        for _ in 0..<10 {
            order.shuffle(using: &generator)
            if order != previous, order.first != previous.last { return order }
        }
        if order.first == previous.last { order.append(order.removeFirst()) }
        return order
    }

    // MARK: Status

    /// Whether the last cycle finished today, so the next one is better after a night's sleep.
    func restSuggested(now: Date, calendar: Calendar) -> Bool {
        guard case .between = stage, let finished = cycles.last?.finished else { return false }
        return calendar.isDate(finished, inSameDayAs: now)
    }

    /// One line for the Puzzles door: "Cycle 2 · 12 of 20", "Cycle 3 ready",
    /// or "Cycle 3 tomorrow" when a cycle ended today. Nil once the set is complete.
    func status(now: Date, calendar: Calendar) -> String? {
        switch stage {
        case .playing(let cycle, let puzzle):
            return "Cycle \(cycle) · \(puzzle) of \(count)"
        case .between(let next, _):
            return restSuggested(now: now, calendar: calendar) ? "Cycle \(next) tomorrow" : "Cycle \(next) ready"
        case .complete:
            return nil
        }
    }
}

// MARK: Building a set

extension PuzzleCycleSet {
    /// The puzzle rating a set is built around for a player: 200 below theirs,
    /// kept inside the pack's range.
    static func level(forRating rating: Int) -> Int {
        min(2700, max(450, rating - ratingBelow))
    }

    /// A new set from the pack around 200 below `rating`, avoiding `avoid`
    /// (puzzles played lately), with its first cycle ready to play. Nil when
    /// the pack has nothing to offer.
    static func make(from library: PuzzleLibrary, size: Int, rating: Int, avoid: Set<String>, now: Date,
                     using generator: inout some RandomNumberGenerator) -> PuzzleCycleSet? {
        let level = Self.level(forRating: rating)
        let picked = pick(from: library, count: size, near: level, avoid: avoid, using: &generator)
        guard !picked.isEmpty else { return nil }
        let ids = picked.map(\.id)
        let floor = picked.reduce(0) { $0 + floorPerPuzzle + floorPerMove * Double($1.length) }
        return PuzzleCycleSet(created: now, level: level, puzzleIDs: ids, floor: floor,
                              cycles: [PuzzleCycleRun(order: ids, target: nil, started: now)])
    }

    /// Puzzles of one to three moves near `level`, mixed so no single idea
    /// takes over: each motif at most an eighth of the set, mates at most
    /// three in ten, mate in one at most one in ten, and no game phase more
    /// than six in ten. Ratings widen up to 250 either side to keep that mix;
    /// past that (low ratings are mostly mates) the mix loosens instead.
    static func pick(from library: PuzzleLibrary, count: Int, near level: Int, avoid: Set<String>,
                     using generator: inout some RandomNumberGenerator) -> [LichessPuzzle] {
        guard count > 0 else { return [] }
        let fresh = library.puzzles.filter { (1...3).contains($0.length) && !avoid.contains($0.id) }
        for window in [100, 175, 250] {
            var pool = fresh.filter { abs($0.rating - level) <= window }
            pool.shuffle(using: &generator)
            let picked = mixed(pool, count: count, loosenesses: [1])
            if picked.count == count { return picked }
        }
        var pool: [LichessPuzzle] = []
        for window in [250, 400, 700, 3000] {
            pool = fresh.filter { abs($0.rating - level) <= window }
            if pool.count >= count * 2 { break }
        }
        if pool.count < count {
            // Nearly everything was played lately: the nearest puzzles will do.
            pool = Array(library.puzzles.sorted { abs($0.rating - level) < abs($1.rating - level) }.prefix(count * 4))
        }
        pool.shuffle(using: &generator)
        return mixed(pool, count: count, loosenesses: [1, 2, .max])
    }

    /// Takes puzzles from `pool` in order while the mix allows, loosening the limits pass by pass.
    private static func mixed(_ pool: [LichessPuzzle], count: Int, loosenesses: [Int]) -> [LichessPuzzle] {
        var mix = CycleMix(count: count)
        var picked: [LichessPuzzle] = []
        var taken: Set<String> = []
        for looseness in loosenesses {
            mix.looseness = looseness
            for puzzle in pool where picked.count < count && !taken.contains(puzzle.id) && mix.allows(puzzle) {
                picked.append(puzzle)
                taken.insert(puzzle.id)
                mix.add(puzzle)
            }
        }
        return picked
    }
}

/// Counts what a set holds so far, to keep its ideas mixed.
private struct CycleMix {
    let count: Int
    /// How many times over the limits may be filled: 1 to start, more if the pack runs short.
    var looseness = 1
    private var motifs: [String: Int] = [:]
    private var phases: [String: Int] = [:]
    private var mates = 0
    private var mateInOnes = 0

    init(count: Int) {
        self.count = count
    }

    private var motifLimit: Int { max(2, Int((Double(count) / 8).rounded(.up))) }
    private var mateLimit: Int { max(1, Int((Double(count) * 0.3).rounded())) }
    private var mateInOneLimit: Int { max(1, Int((Double(count) * 0.1).rounded())) }
    private var phaseLimit: Int { max(1, Int((Double(count) * 0.6).rounded(.up))) }

    func allows(_ puzzle: LichessPuzzle) -> Bool {
        guard looseness != .max else { return true }
        if motifs[puzzle.leadMotif, default: 0] >= motifLimit * looseness { return false }
        if let phase = puzzle.phaseTag, phases[phase, default: 0] >= phaseLimit * looseness { return false }
        if puzzle.endsInMate, mates >= mateLimit * looseness { return false }
        if puzzle.mateIn == 1, mateInOnes >= mateInOneLimit * looseness { return false }
        return true
    }

    mutating func add(_ puzzle: LichessPuzzle) {
        motifs[puzzle.leadMotif, default: 0] += 1
        if let phase = puzzle.phaseTag { phases[phase, default: 0] += 1 }
        if puzzle.endsInMate { mates += 1 }
        if puzzle.mateIn == 1 { mateInOnes += 1 }
    }
}

extension LichessPuzzle {
    /// Tags from the most telling idea to the most general, for mixing a set.
    static let leadMotifOrder = [
        "smotheredMate", "backRankMate", "doubleCheck", "discoveredAttack", "skewer", "pin", "fork",
        "xRayAttack", "interference", "clearance", "deflection", "attraction", "intermezzo", "trappedPiece",
        "hangingPiece", "promotion", "quietMove", "zugzwang", "defensiveMove", "sacrifice", "advancedPawn",
        "mateIn1", "mateIn2", "mateIn3", "mateIn4", "mateIn5", "kingsideAttack", "queensideAttack",
    ]

    /// The puzzle's main idea: its most telling tag, else its game phase.
    var leadMotif: String {
        Self.leadMotifOrder.first(where: themes.contains) ?? phaseTag ?? themes.first ?? ""
    }

    /// Opening, middlegame or endgame, when tagged.
    var phaseTag: String? {
        ["opening", "middlegame", "endgame"].first(where: themes.contains)
    }

    /// Ends in checkmate.
    var endsInMate: Bool {
        mateIn != nil || themes.contains("backRankMate") || themes.contains("smotheredMate")
    }
}

// MARK: The clock

/// A stopwatch that pauses: the Cycles clock only runs while it's the player's move.
struct CycleStopwatch: Equatable {
    private(set) var banked: TimeInterval = 0
    private(set) var runningSince: Date?

    var isRunning: Bool { runningSince != nil }

    mutating func start(at date: Date) {
        if runningSince == nil { runningSince = date }
    }

    mutating func stop(at date: Date) {
        guard let since = runningSince else { return }
        banked += max(0, date.timeIntervalSince(since))
        runningSince = nil
    }

    func elapsed(at date: Date) -> TimeInterval {
        banked + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// Stops, hands back the time so far and starts over from zero.
    mutating func take(at date: Date) -> TimeInterval {
        stop(at: date)
        let time = banked
        banked = 0
        return time
    }
}

/// Times as the Cycles screens show them.
enum CycleClock {
    /// "4:10", or "1:02:05" past an hour.
    static func text(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, rest) }
        return String(format: "%d:%02d", minutes, rest)
    }

    /// "4 minutes 10 seconds", for VoiceOver.
    static func spoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if rest > 0 || parts.isEmpty { parts.append(rest == 1 ? "1 second" : "\(rest) seconds") }
        return parts.joined(separator: " ")
    }
}

// MARK: Saving

/// What Cycles keeps, in a file of its own.
struct PuzzleCycleFile: Codable, Equatable {
    /// The set under way, or the last one finished; nil before the first.
    var current: PuzzleCycleSet?
    /// Sets played through every cycle.
    var setsFinished = 0

    enum CodingKeys: String, CodingKey {
        case current, setsFinished
    }
}

extension PuzzleCycleFile {
    /// Reads any saved version. A set that can't be read is dropped rather
    /// than losing the rest of the file.
    init(from decoder: Decoder) throws {
        self.init()
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        current = try? saved.decodeIfPresent(PuzzleCycleSet.self, forKey: .current)
        setsFinished = try saved.decodeIfPresent(Int.self, forKey: .setsFinished) ?? setsFinished
    }
}
