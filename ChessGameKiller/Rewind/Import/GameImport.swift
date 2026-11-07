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

/// Grades the player's moves in a game from a chess site the way a game here is graded,
/// move by move against Stockfish, and keeps it as a saved game.
struct GameImportGrader {
    let engine: any ChessEngine
    var depth = 14
    /// The most time for the position before each of the player's moves, and after it.
    var beforeMs = 350
    var afterMs = 200

    /// The game as a saved game, or nil if its moves don't replay or the player isn't in it.
    func grade(_ online: ImportedGame, username: String, isCancelled: @Sendable () -> Bool = { Task.isCancelled }) async -> SavedGame? {
        guard let playerIsWhite = online.playerIsWhite(username),
              let replay = GameImportBuilder.replay(online.moves) else { return nil }
        var moments: [SavedMoment] = []
        var counts: [MoveReview.Grade: Int] = [:]
        // Lines already found, by position: the position after one move is the one before the next.
        var known: [Int: [EngineLine]] = [:]

        for index in replay.uci.indices {
            let byWhite = index % 2 == 0
            guard byWhite == playerIsWhite else { continue }
            if isCancelled() { return nil }
            let uci = replay.uci[index]
            let fenBefore = replay.positions[index], fenAfter = replay.positions[index + 1]
            let san = GameImportBuilder.cleanSAN(online.moves[index])
            let ply = index + 1
            let isLast = index == replay.uci.count - 1

            if isLast, replay.endsInMate {
                moments.append(SavedMoment(ply: ply, grade: MoveReview.Grade.checkmate.rawValue, san: san, uci: uci,
                                           byWhite: byWhite, fenBefore: fenBefore, fenAfter: fenAfter,
                                           before: 1, after: 1))
                counts[.checkmate, default: 0] += 1
                continue
            }

            var before = known[index] ?? []
            if known[index] == nil {
                before = await engine.analyze(fen: fenBefore, depth: depth, lines: 2, maxTimeMs: beforeMs)
                known[index] = before
            }
            guard let bestLine = before.first, let bestMove = bestLine.firstMove else { continue }

            let playedBest = bestMove == uci
            var after: Evaluation?
            var reply: String?
            if playedBest {
                after = bestLine.evaluation
                reply = bestLine.moves.dropFirst().first
            } else if before.count > 1, before[1].firstMove == uci {
                after = before[1].evaluation
                reply = before[1].moves.dropFirst().first
            } else {
                var answer = known[index + 1] ?? []
                if known[index + 1] == nil {
                    answer = await engine.analyze(fen: fenAfter, depth: depth, lines: 1, maxTimeMs: afterMs)
                    known[index + 1] = answer
                }
                if let line = answer.first {
                    after = line.evaluation.flipped
                    reply = line.firstMove
                } else if isLast {
                    // Nothing to answer with and no mate: a stalemate, or a draw on the board.
                    after = .centipawns(0)
                }
            }
            guard let after else { continue }

            let grade = MoveReview.grade(before: bestLine.evaluation, after: after, playedBest: playedBest)
            counts[grade, default: 0] += 1
            moments.append(SavedMoment(
                ply: ply, grade: grade.rawValue, san: san, uci: uci, byWhite: byWhite,
                fenBefore: fenBefore, fenAfter: fenAfter,
                best: playedBest ? nil : Notation.san(of: bestMove, fen: fenBefore),
                bestUCI: playedBest ? nil : bestMove,
                bestLine: playedBest ? [] : bestLine.moves,
                reply: reply,
                before: bestLine.evaluation.winningChances, after: after.winningChances,
                beforeEval: bestLine.evaluation, afterEval: after
            ))
        }

        let playerColor: Piece.Color = playerIsWhite ? .white : .black
        let winner: Piece.Color? = online.winner.map { $0 == .white ? Piece.Color.white : Piece.Color.black }
        var game = SavedGame.make(
            id: UUID(), date: online.date,
            opponent: playerIsWhite ? online.black : online.white,
            level: nil, playerColor: playerColor, winner: winner, isOver: true,
            accuracy: SavedGame.accuracy(of: counts),
            positions: replay.positions, moves: online.moves.map(GameImportBuilder.cleanSAN), moments: moments
        )
        game.clock = online.clock
        game.source = online.site.rawValue
        game.sourceID = online.sourceID
        game.opponentRating = playerIsWhite ? online.blackRating : online.whiteRating
        return game
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
    static func saveMistakes(from game: SavedGame, to store: TrainingStore) -> Int {
        var saved = 0
        for moment in game.playerMoments where [.mistake, .blunder].contains(moment.moveGrade) {
            guard let best = moment.bestUCI else { continue }
            let found = MomentFinder.find(in: moment.review).flatMap { $0.kind.isPraise ? nil : $0 }
            let title = found.map { GameCoach.words(for: $0, library: store.library).title } ?? "Find the better move"
            if store.addMistake(fen: moment.fenBefore, best: best, played: moment.uci, skill: found?.skill ?? "", title: title) {
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
