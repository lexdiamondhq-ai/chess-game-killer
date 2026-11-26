import ChessKit
import Foundation
import Observation

// MARK: Fetching

/// Why games couldn't be brought in, in words for the player.
enum GameImportError: Error, Equatable {
    case badUsername
    case noSuchPlayer(OnlineSite, String)
    case slowDown(OnlineSite)
    case unreachable(OnlineSite)
    case noGames(OnlineSite, String)

    var message: String {
        switch self {
        case .badUsername:
            return "That doesn't look like a username. Use letters, numbers, _ or -."
        case .noSuchPlayer(let site, let name):
            return "\(site.title) has no player called \(name)."
        case .slowDown(let site):
            return "\(site.title) asked us to wait a minute. Try again shortly."
        case .unreachable(let site):
            return "Couldn't reach \(site.title). Check your connection and try again."
        case .noGames(let site, let name):
            return "No finished games for \(name) on \(site.title) yet."
        }
    }
}

/// Where the recent games come from. A protocol so tests can stand in for the sites.
protocol OnlineGameSource: Sendable {
    /// The player's most recent finished games of standard chess, newest first.
    func recentGames(site: OnlineSite, username: String, count: Int) async throws -> [ImportedGame]
}

/// The sites' public game APIs: Lichess's game export and Chess.com's monthly archives.
/// Neither needs an account or a key.
struct OnlineGamesClient: OnlineGameSource {
    private let session: URLSession

    init(session: URLSession = OnlineGamesClient.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["User-Agent": "ChessGameKiller-iOS (github.com/lexdiamondhq-ai/chess-game-killer)"]
        return URLSession(configuration: configuration)
    }

    func recentGames(site: OnlineSite, username: String, count: Int) async throws -> [ImportedGame] {
        guard let name = OnlineGames.cleaned(username) else { throw GameImportError.badUsername }
        let games: [ImportedGame]
        switch site {
        case .lichess:
            guard let url = OnlineGames.lichessURL(username: name, max: count) else { throw GameImportError.badUsername }
            let data = try await fetch(url, site: site, name: name, accept: "application/x-ndjson")
            games = OnlineGames.parseLichess(data)
        case .chessCom:
            guard let url = OnlineGames.chessComArchivesURL(username: name) else { throw GameImportError.badUsername }
            let months = OnlineGames.parseChessComArchives(try await fetch(url, site: site, name: name))
            var found: [ImportedGame] = []
            // Newest month first, until there are enough (a quiet month may have only a few).
            for month in months.reversed().prefix(3) where found.count < count {
                found += OnlineGames.parseChessComMonth(try await fetch(month, site: site, name: name))
            }
            games = found
        }
        let own = games.filter { $0.playerIsWhite(name) != nil }
        guard !own.isEmpty else { throw GameImportError.noGames(site, name) }
        return Array(own.sorted { $0.date > $1.date }.prefix(count))
    }

    private func fetch(_ url: URL, site: OnlineSite, name: String, accept: String = "application/json") async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GameImportError.unreachable(site)
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return data
        case 404, 410: throw GameImportError.noSuchPlayer(site, name)
        case 429: throw GameImportError.slowDown(site)
        default: throw GameImportError.unreachable(site)
        }
    }
}

// MARK: Turning moves into a game

enum GameImportBuilder {
    /// The moves in engine notation and every position, the start first. Nil if a move
    /// doesn't fit the position it was played in.
    static func replay(_ sanMoves: [String], from start: String = OnlineGames.standardStart)
        -> (uci: [String], positions: [String], endsInMate: Bool)? {
        guard let position = Position(fen: start) else { return nil }
        var board = Board(position: position)
        var positions = [board.position.fen]
        var ucis: [String] = []
        for san in sanMoves {
            guard let uci = uci(forSAN: san, on: board), TrainingChess.play(uci, on: &board) != nil else { return nil }
            ucis.append(uci)
            positions.append(board.position.fen)
        }
        return (ucis, positions, TrainingChess.isCheckmate(board))
    }

    /// The legal move a piece of standard notation names, in engine notation.
    static func uci(forSAN san: String, on board: Board) -> String? {
        let target = normalized(san)
        guard !target.isEmpty else { return nil }
        let fen = board.position.fen
        for uci in candidates(on: board) {
            if let written = Notation.san(of: uci, fen: fen), normalized(written) == target { return uci }
        }
        return nil
    }

    /// Every legal move, with each promotion to every piece.
    private static func candidates(on board: Board) -> [String] {
        TrainingChess.legalMoves(in: board).flatMap { uci -> [String] in
            guard uci.count == 5 else { return [uci] }
            let stem = String(uci.prefix(4))
            return ["q", "r", "b", "n"].map { stem + $0 }
        }
    }

    /// Notation reduced to what names the move: no check marks, captures, "=" or "!?", and castling with O's.
    static func normalized(_ san: String) -> String {
        san.replacingOccurrences(of: "0", with: "O")
            .filter { !"+#!?x=".contains($0) }
    }
}

// MARK: Grading

/// Grades the player's moves in a finished game the way a game against a rival is graded as
/// it is played, move by move against Stockfish: a game from a chess site, or a game played
/// here against a person.
struct GameImportGrader {
    let engine: any ChessEngine
    var depth = 14
    /// The most time for the position before each of the player's moves, and after it.
    var beforeMs = 350
    var afterMs = 200
    /// Grading nobody is watching (a game against a person, after it ends). The engine is asked
    /// quietly, so a game being played never waits on it; a search that had to give way is
    /// asked again once the engine has been free for a moment.
    var quiet = false
    /// How long to stand back after giving way, before asking again.
    var standBack = Duration.seconds(2)

    /// The game as a saved game, or nil if its moves don't replay or the player isn't in it.
    func grade(_ online: ImportedGame, username: String, isCancelled: @Sendable () -> Bool = { Task.isCancelled }) async -> SavedGame? {
        guard let playerIsWhite = online.playerIsWhite(username),
              let replay = GameImportBuilder.replay(online.moves) else { return nil }
        let san = online.moves.map(GameImportBuilder.cleanSAN)
        guard let read = await read(uci: replay.uci, positions: replay.positions, san: san,
                                    playerIsWhite: playerIsWhite, endsInMate: replay.endsInMate,
                                    isCancelled: isCancelled) else { return nil }

        let playerColor: Piece.Color = playerIsWhite ? .white : .black
        let winner: Piece.Color? = online.winner.map { $0 == .white ? Piece.Color.white : Piece.Color.black }
        var game = SavedGame.make(
            id: UUID(), date: online.date,
            opponent: playerIsWhite ? online.black : online.white,
            level: nil, playerColor: playerColor, winner: winner, isOver: true,
            accuracy: SavedGame.accuracy(of: read.counts),
            positions: replay.positions, moves: san, moments: read.moments
        )
        game.clock = online.clock
        game.source = online.site.rawValue
        game.sourceID = online.sourceID
        game.opponentRating = playerIsWhite ? online.blackRating : online.whiteRating
        return game
    }

    /// What became of grading a game played here against a person.
    enum Reading: Equatable {
        /// The game, with the player's moves graded.
        case graded(SavedGame)
        /// Stopped before the end (cancelled, or the engine had nothing to say): try again later.
        case stopped
        /// Its positions aren't a move apart, so there is nothing to grade.
        case unreadable
    }

    /// Grades the player's moves in a game played here against a person. The game keeps its
    /// id and date, so the saved one is brought up to date in place.
    func grade(_ game: SavedGame, isCancelled: @Sendable () -> Bool = { Task.isCancelled }) async -> Reading {
        guard game.positions.count == game.moves.count + 1,
              let replay = GameImportBuilder.moves(through: game.positions) else { return .unreadable }
        guard let read = await read(uci: replay.uci, positions: game.positions, san: game.moves,
                                    playerIsWhite: game.playerIsWhite, endsInMate: replay.endsInMate,
                                    isCancelled: isCancelled) else { return .stopped }
        var graded = game
        graded.moments = read.moments
        graded.accuracy = SavedGame.accuracy(of: read.counts)
        graded.graded = true
        return .graded(graded)
    }

    /// The player's moves, graded, and how many got each grade. Nil when stopped before the end.
    private func read(uci: [String], positions: [String], san: [String], playerIsWhite: Bool, endsInMate: Bool,
                      isCancelled: @Sendable () -> Bool) async -> (moments: [SavedMoment], counts: [MoveReview.Grade: Int])? {
        var moments: [SavedMoment] = []
        var counts: [MoveReview.Grade: Int] = [:]
        // Lines already found, by position: the position after one move is the one before the next.
        var known: [Int: [EngineLine]] = [:]

        for index in uci.indices {
            let byWhite = index % 2 == 0
            guard byWhite == playerIsWhite else { continue }
            if isCancelled() { return nil }
            let move = uci[index]
            let fenBefore = positions[index], fenAfter = positions[index + 1]
            let ply = index + 1
            let isLast = index == uci.count - 1

            if isLast, endsInMate {
                moments.append(SavedMoment(ply: ply, grade: MoveReview.Grade.checkmate.rawValue, san: san[index], uci: move,
                                           byWhite: byWhite, fenBefore: fenBefore, fenAfter: fenAfter,
                                           before: 1, after: 1))
                counts[.checkmate, default: 0] += 1
                continue
            }

            var before = known[index] ?? []
            if known[index] == nil {
                guard let found = await lines(fenBefore, count: 2, ms: beforeMs, isCancelled: isCancelled) else { return nil }
                before = found
                known[index] = before
            }
            guard let bestLine = before.first, let bestMove = bestLine.firstMove else {
                // The player moved from here, so there were moves to find: a quiet reading
                // stops rather than leave the move out. (An import carries on, as it always has.)
                if quiet { return nil }
                continue
            }

            let playedBest = bestMove == move
            var after: Evaluation?
            var reply: String?
            if playedBest {
                after = bestLine.evaluation
                reply = bestLine.moves.dropFirst().first
            } else if before.count > 1, before[1].firstMove == move {
                after = before[1].evaluation
                reply = before[1].moves.dropFirst().first
            } else {
                var answer = known[index + 1] ?? []
                if known[index + 1] == nil {
                    guard let found = await lines(fenAfter, count: 1, ms: afterMs, isCancelled: isCancelled) else { return nil }
                    answer = found
                    known[index + 1] = answer
                }
                if let line = answer.first {
                    after = line.evaluation.flipped
                    reply = line.firstMove
                } else if isLast, !quiet || !GameImportBuilder.hasMoves(fenAfter) {
                    // Nothing to answer with and no mate: a stalemate, or a draw on the board.
                    after = .centipawns(0)
                } else if quiet {
                    return nil
                }
            }
            guard let after else { continue }

            let grade = MoveReview.grade(before: bestLine.evaluation, after: after, playedBest: playedBest)
            counts[grade, default: 0] += 1
            moments.append(SavedMoment(
                ply: ply, grade: grade.rawValue, san: san[index], uci: move, byWhite: byWhite,
                fenBefore: fenBefore, fenAfter: fenAfter,
                best: playedBest ? nil : Notation.san(of: bestMove, fen: fenBefore),
                bestUCI: playedBest ? nil : bestMove,
                bestLine: playedBest ? [] : bestLine.moves,
                reply: reply,
                before: bestLine.evaluation.winningChances, after: after.winningChances,
                beforeEval: bestLine.evaluation, afterEval: after
            ))
        }
        return (moments, counts)
    }

    /// The engine's lines for a position. A quiet reading asks again, after standing back,
    /// each time it had to give way; nil once cancelled.
    private func lines(_ fen: String, count: Int, ms: Int, isCancelled: @Sendable () -> Bool) async -> [EngineLine]? {
        guard quiet else { return await engine.analyze(fen: fen, depth: depth, lines: count, maxTimeMs: ms) }
        while !isCancelled() {
            if let found = await engine.analyzeQuietly(fen: fen, depth: depth, lines: count, maxTimeMs: ms) { return found }
            try? await Task.sleep(for: standBack)
        }
        return nil
    }
}

extension GameImportBuilder {
    /// The moves, in engine notation, that lead from each position to the next, and whether
    /// the last one is mate. Nil if two positions in a row aren't one move apart.
    static func moves(through positions: [String]) -> (uci: [String], endsInMate: Bool)? {
        var ucis: [String] = []
        var endsInMate = false
        for (fen, next) in zip(positions, positions.dropFirst()) {
            guard let position = Position(fen: fen) else { return nil }
            let target = TrainingChess.key(next)
            var found: (uci: String, board: Board)?
            for uci in candidates(on: Board(position: position)) {
                guard let board = TrainingChess.board(after: [uci], from: fen),
                      TrainingChess.key(board.position.fen) == target else { continue }
                found = (uci, board)
                break
            }
            guard let found else { return nil }
            ucis.append(found.uci)
            endsInMate = TrainingChess.isCheckmate(found.board)
        }
        return (ucis, endsInMate)
    }

    /// Whether the side to move has a legal move.
    static func hasMoves(_ fen: String) -> Bool {
        guard let position = Position(fen: fen) else { return false }
        return !TrainingChess.legalMoves(in: Board(position: position)).isEmpty
    }
}

extension GameImportBuilder {
    /// Notation as the app writes it: "!" and "?" marks dropped, castling with O's.
    static func cleanSAN(_ san: String) -> String {
        san.replacingOccurrences(of: "0", with: "O").filter { !"!?".contains($0) }
    }
}

// MARK: The import

/// Brings the player's recent games in from Lichess or Chess.com: fetches them, grades each
/// one, keeps it with the games played here (so Rewind, Leo's report and the Chess DNA read
/// it), and saves its real mistakes to practice.
@MainActor
@Observable
final class GameImporter {
    enum Phase: Equatable {
        case idle
        case fetching(OnlineSite)
        /// Grading game `done + 1` of `total`.
        case reading(done: Int, total: Int)
        case finished(added: Int, mistakes: Int)
        case failed(String)

        var isWorking: Bool {
            switch self {
            case .fetching, .reading: return true
            default: return false
            }
        }
    }

    /// The account the player last brought games in from, remembered for next time.
    struct Account: Codable, Equatable {
        var site: OnlineSite
        var username: String
    }

    private(set) var phase: Phase = .idle
    private(set) var account: Account?

    @ObservationIgnored private let source: any OnlineGameSource
    @ObservationIgnored private let engine: any ChessEngine
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?

    static let accountKey = "onlineGames.account"

    init(source: any OnlineGameSource = OnlineGamesClient(), engine: any ChessEngine = StockfishEngine.shared,
         defaults: UserDefaults = .standard) {
        self.source = source
        self.engine = engine
        self.defaults = defaults
        account = defaults.data(forKey: Self.accountKey).flatMap { try? JSONDecoder().decode(Account.self, from: $0) }
    }

    /// Starts bringing games in. What's already here is skipped.
    func start(site: OnlineSite, username: String, vault: GameVault, store: TrainingStore?) {
        task?.cancel()
        task = Task { await run(site: site, username: username, vault: vault, store: store) }
    }

    /// Stops after the game being graded. Games already graded stay.
    func cancel() {
        task?.cancel()
        task = nil
        if phase.isWorking { phase = .idle }
    }

    /// Forgets the account (the games stay).
    func forgetAccount() {
        account = nil
        defaults.removeObject(forKey: Self.accountKey)
    }

    func run(site: OnlineSite, username: String, vault: GameVault, store: TrainingStore?) async {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OnlineGames.cleaned(name) != nil else {
            phase = .failed(GameImportError.badUsername.message)
            return
        }
        phase = .fetching(site)
        let games: [ImportedGame]
        do {
            games = try await source.recentGames(site: site, username: name, count: OnlineGames.importCount)
        } catch let error as GameImportError {
            phase = .failed(error.message)
            return
        } catch {
            phase = .failed(GameImportError.unreachable(site).message)
            return
        }
        guard !Task.isCancelled else { return }
        remember(Account(site: site, username: name))

        let fresh = games.filter { !vault.hasImported($0.sourceID) }
        let grader = GameImportGrader(engine: engine)
        var added = 0
        var mistakes = 0
        for (index, online) in fresh.enumerated() {
            phase = .reading(done: index, total: fresh.count)
            guard let game = await grader.grade(online, username: name) else {
                if Task.isCancelled { return }
                continue
            }
            if Task.isCancelled { return }
            vault.record(game)
            added += 1
            if let store { mistakes += Self.saveMistakes(from: game, to: store) }
        }
        phase = .finished(added: added, mistakes: mistakes)
    }

    /// The game's real mistakes, saved to "Fix your mistakes" like those from games played here.
    /// `date` is when they count as made: the pile keeps the newest, so a game read long after
    /// it was played passes its own date and never pushes out fresher mistakes.
    static func saveMistakes(from game: SavedGame, to store: TrainingStore, at date: Date = .now) -> Int {
        var saved = 0
        for moment in game.playerMoments where [.mistake, .blunder].contains(moment.moveGrade) {
            guard let best = moment.bestUCI else { continue }
            let found = MomentFinder.find(in: game.review(of: moment)).flatMap { $0.kind.isPraise ? nil : $0 }
            let title = found.map { GameCoach.words(for: $0, library: store.library).title } ?? "Find the better move"
            if store.addMistake(fen: moment.fenBefore, best: best, played: moment.uci, skill: found?.skill ?? "",
                                title: title, at: date) {
                saved += 1
            }
        }
        return saved
    }

    private func remember(_ account: Account) {
        self.account = account
        if let data = try? JSONEncoder().encode(account) { defaults.set(data, forKey: Self.accountKey) }
    }
}
