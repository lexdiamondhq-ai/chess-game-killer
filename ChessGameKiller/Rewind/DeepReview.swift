import ChessKit
import Foundation

/// The coach's deep review: once a game is over, Leo talks through all of it, once, the way a
/// coach at the board would. The phone's Stockfish already graded the game; the server
/// (coach/, POST /review) has Claude tell its story from those grades and reads it aloud in
/// parts, so the board can follow his words.
struct DeepReview: Codable, Equatable, Sendable {
    /// Who is talking: "leo" or "vera".
    var coach: String
    var parts: [DeepReviewPart]

    /// The coach whose review this is.
    var speaker: Coach { Coach(rawValue: coach) ?? .leo }

    /// The review's chapters, in order: parts next to each other can share a label.
    var chapters: [String] {
        parts.reduce(into: [String]()) { names, part in
            if names.last != part.label { names.append(part.label) }
        }
    }

    /// Roughly how long it takes to hear, at a coach's pace.
    var seconds: Int {
        Int((Double(parts.reduce(0) { $0 + $1.wordCount }) / 2.6).rounded())
    }
}

/// One part of the review: a few sentences, about one move at most.
struct DeepReviewPart: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case intro, praise, mistake, moment, habit
    }

    /// The chapter's name, like "The pawn on d4".
    var label: String
    var kind: Kind
    /// The move the part is about, counted from 1 (White's first move). Nil: about no one move.
    var ply: Int?
    var text: String

    init(label: String, kind: Kind, ply: Int? = nil, text: String) {
        self.label = label
        self.kind = kind
        self.ply = ply
        self.text = text
    }

    /// A kind this app doesn't know is read as a plain moment, so a newer server never breaks an older app.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = (try? container.decode(String.self, forKey: .label)) ?? ""
        kind = (try? container.decode(Kind.self, forKey: .kind)) ?? .moment
        ply = try? container.decodeIfPresent(Int.self, forKey: .ply)
        text = try container.decode(String.self, forKey: .text)
    }

    var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }

    /// How long the words stay up when nothing is read aloud (the coach is muted).
    var readingTime: Duration { .seconds(max(3, Double(wordCount) / 2.8)) }

    /// Where the board stands for this part: before a mistake, so the better move can be
    /// shown; after any other move. Nil when the part is about no one move of this game.
    func boardPly(in game: SavedGame) -> Int? {
        guard let ply, ply >= 1, ply <= game.moves.count else { return nil }
        return kind == .mistake ? ply - 1 : ply
    }
}

// MARK: - What the app sends

/// POST /review: the game with the grades the phone already has (coach/PROTOCOL.md).
struct DeepReviewRequest: Encodable, Equatable, Sendable {
    /// One of the player's moves as it was graded.
    struct Graded: Encodable, Equatable, Sendable {
        var ply: Int
        var grade: String
        /// The player's winning chances around the move, -1 to 1.
        var before: Double
        var after: Double
        /// The engine's move in standard notation, when it wasn't the one played, and its line.
        var best: String?
        var line: [String]?
    }

    var v = 1
    /// "white" or "black".
    var player: String
    /// The rival's name. Left out for a game from a chess site: a person's handle stays on the phone.
    var rival: String?
    var rivalRating: Int?
    /// "win", "loss" or "draw", the player's.
    var result: String
    /// The first position, when the game didn't start from the usual one.
    var start: String?
    var moves: [String]
    var graded: [Graded]
    /// Who reviews: left out for Leo, "vera" for Vera.
    var coach: String?
    var voice: Bool

    /// The fewest plies and graded moves a game needs for there to be a story to tell.
    static let fewestPlies = 16
    static let fewestGraded = 5

    /// Whether this game can be reviewed: finished, the player's own, and long enough.
    static func offered(for game: SavedGame) -> Bool {
        game.result != .unfinished && game.isPlayersOwn
            && game.moves.count >= fewestPlies && game.positions.count == game.moves.count + 1
            && game.playerMoments.count >= fewestGraded
    }

    /// Nil for a game that can't be reviewed.
    init?(game: SavedGame, coach: Coach = .current, voice: Bool = true) {
        guard Self.offered(for: game) else { return nil }
        player = game.playerIsWhite ? "white" : "black"
        rival = game.isImported ? nil : game.opponentShown
        rivalRating = game.opponentRating ?? game.level.flatMap(MatchController.Level.init(rawValue:))?.rating
        result = game.result.rawValue
        if let first = game.positions.first, first != Position.standard.fen { start = first }
        moves = game.moves
        graded = game.playerMoments.map { moment in
            let line = SavedGame.ghostLine(for: moment, limit: 6).moves
            return Graded(
                ply: moment.ply, grade: moment.grade,
                before: (moment.before * 1000).rounded() / 1000, after: (moment.after * 1000).rounded() / 1000,
                best: moment.best, line: moment.best == nil || line.isEmpty ? nil : line
            )
        }
        self.coach = coach == .leo ? nil : coach.rawValue
        self.voice = voice
    }
}

// MARK: - What the server sends back

/// One line of the review's stream: the words first, then each part's voice in any order, then done.
enum DeepReviewEvent: Equatable, Sendable {
    case review(DeepReview)
    /// A part read aloud as an MP3, or nil when the server has no voice for it.
    case voice(part: Int, mp3: Data?)
    case done
    /// The server's error code, like "upstream". The stream ends with it.
    case failed(String)

    /// Reads one line of the stream. Nil for a blank line or a kind of line this app doesn't know.
    static func decode(line: some StringProtocol) throws -> DeepReviewEvent? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        let head = try decoder.decode(Head.self, from: data)
        switch head.type {
        case "review":
            let review = try decoder.decode(DeepReview.self, from: data)
            return review.parts.isEmpty ? .failed("internal") : .review(review)
        case "voice":
            guard let part = head.part, part >= 0 else { return nil }
            return .voice(part: part, mp3: head.audio.flatMap { Data(base64Encoded: $0) }.flatMap { $0.isEmpty ? nil : $0 })
        case "done":
            return .done
        case "error":
            return .failed(head.error ?? "internal")
        default:
            return nil
        }
    }

    private struct Head: Decodable {
        var type: String
        var error: String?
        var part: Int?
        var audio: String?
    }
}

// MARK: - Kept with the game

/// Reviews already heard, saved on this device with their recordings, so hearing one again is
/// instant, works offline and costs nothing.
struct DeepReviewStore: Sendable {
    /// Nil keeps nothing (previews and tests that don't want files).
    let folder: URL?

    /// As many reviews as are kept; the oldest go first. About 1.5 MB each.
    static let limit = 30

    static let live: DeepReviewStore = {
        let base = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return DeepReviewStore(folder: base?.appendingPathComponent("DeepReviews", isDirectory: true))
    }()

    private func folder(for game: UUID) -> URL? {
        folder?.appendingPathComponent(game.uuidString, isDirectory: true)
    }

    func has(_ game: UUID) -> Bool {
        guard let url = folder(for: game)?.appendingPathComponent("review.json") else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func review(for game: UUID) -> DeepReview? {
        guard let url = folder(for: game)?.appendingPathComponent("review.json"),
              let data = try? Data(contentsOf: url),
              let review = try? JSONDecoder().decode(DeepReview.self, from: data), !review.parts.isEmpty
        else { return nil }
        return review
    }

    /// A part's recording, when it was kept.
    func voice(part: Int, for game: UUID) -> Data? {
        guard let url = folder(for: game)?.appendingPathComponent("part-\(part).mp3") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Keeps a new review, replacing any earlier one of this game and its recordings.
    func save(_ review: DeepReview, for game: UUID) {
        guard let url = folder(for: game) else { return }
        let files = FileManager.default
        try? files.removeItem(at: url)
        do {
            try files.createDirectory(at: url, withIntermediateDirectories: true)
            try JSONEncoder().encode(review).write(to: url.appendingPathComponent("review.json"), options: .atomic)
        } catch {
            NSLog("Couldn't keep the deep review: %@", "\(error)")
        }
        prune(keeping: game)
    }

    func saveVoice(_ mp3: Data, part: Int, for game: UUID) {
        guard let url = folder(for: game), FileManager.default.fileExists(atPath: url.path) else { return }
        try? mp3.write(to: url.appendingPathComponent("part-\(part).mp3"), options: .atomic)
    }

    func delete(_ game: UUID) {
        guard let url = folder(for: game) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Drops the oldest reviews past the limit.
    private func prune(keeping game: UUID) {
        guard let folder else { return }
        let files = FileManager.default
        let kept = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        guard kept.count > Self.limit else { return }
        let dated = kept
            .filter { $0.lastPathComponent != game.uuidString }
            .map { url -> (url: URL, changed: Date) in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                return (url, values?.contentModificationDate ?? Date.distantPast)
            }
            .sorted { $0.changed < $1.changed }
        for (url, _) in dated.prefix(kept.count - Self.limit) {
            try? files.removeItem(at: url)
        }
    }
}
