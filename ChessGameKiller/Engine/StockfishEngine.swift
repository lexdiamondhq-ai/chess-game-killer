import ChessKit
import ChessKitEngine
import Foundation

/// What the game needs from a chess engine. A protocol so tests can use a fake.
protocol ChessEngine: AnyObject, Sendable {
    /// The best `lines` continuations from `fen`, best first. The search stops at
    /// `depth` or after `maxTimeMs`, whichever comes first; nil means no time cap.
    func analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int?) async -> [EngineLine]
    /// A move to play from `fen` at the given strength (0 = weakest, 20 = full strength).
    func chooseMove(fen: String, skill: Int, thinkTimeMs: Int) async -> String?
}

extension ChessEngine {
    /// An analysis with no time cap: it runs until `depth`.
    func analyze(fen: String, depth: Int, lines: Int) async -> [EngineLine] {
        await analyze(fen: fen, depth: depth, lines: lines, maxTimeMs: nil)
    }
}

/// Stockfish 17 running on the device, through ChessKitEngine.
///
/// One engine is shared by the whole app. Searches run one at a time; a new
/// search waits for (and stops) the one before it.
actor StockfishEngine: ChessEngine {
    static let shared = StockfishEngine()

    private let engine = Engine(type: .stockfish)
    private var startTask: Task<Bool, Never>?
    private var readyCount = 0
    private var listener: Task<Void, Never>?
    private var pending: PendingSearch?
    private var nextSearchID = 0

    private struct PendingSearch {
        let id: Int
        /// Engine output is checked against this, so late output from an
        /// earlier search can never leak into this one.
        let position: Position
        var lines: [Int: (depth: Int, line: EngineLine)] = [:]
        let continuation: AsyncStream<SearchResult>.Continuation
    }

    private struct SearchResult: Sendable {
        var bestMove: String?
        var lines: [EngineLine]
    }

    // MARK: ChessEngine

    func analyze(fen: String, depth: Int, lines: Int, maxTimeMs: Int?) async -> [EngineLine] {
        let result = await search(
            fen: fen,
            options: [("Skill Level", "20"), ("MultiPV", "\(max(1, lines))")],
            go: .go(depth: depth, movetime: maxTimeMs),
            timeout: maxTimeMs.map { .milliseconds($0 + 10_000) } ?? .seconds(20)
        )
        return Array(result.lines.prefix(lines))
    }

    /// Starts Stockfish and loads its networks ahead of the first search, so the
    /// first computer move of the session doesn't pay for it.
    func warmUp() async {
        _ = await startIfNeeded()
    }

    func chooseMove(fen: String, skill: Int, thinkTimeMs: Int) async -> String? {
        let result = await search(
            fen: fen,
            options: [("Skill Level", "\(max(0, min(20, skill)))"), ("MultiPV", "1")],
            go: .go(movetime: thinkTimeMs),
            timeout: .milliseconds(thinkTimeMs + 10_000)
        )
        return result.bestMove
    }

    // MARK: Searching

    private func search(
        fen: String,
        options: [(String, String)],
        go: EngineCommand,
        timeout: Duration
    ) async -> SearchResult {
        guard let position = Position(fen: fen), await startIfNeeded() else {
            return SearchResult(bestMove: nil, lines: [])
        }

        // A caller whose task was cancelled no longer wants an answer, and must
        // not stop a search someone else is waiting for.
        if Task.isCancelled { return SearchResult(bestMove: nil, lines: []) }

        // One search at a time: stop the current one and wait for it to report.
        if pending != nil {
            await engine.send(command: .stop)
        }
        while pending != nil {
            if Task.isCancelled { return SearchResult(bestMove: nil, lines: []) }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let (stream, continuation) = AsyncStream<SearchResult>.makeStream()
        let id = nextSearchID
        nextSearchID += 1
        pending = PendingSearch(id: id, position: position, continuation: continuation)

        for (name, value) in options {
            await engine.send(command: .setoption(id: name, value: value))
        }
        await engine.send(command: .position(.fen(fen)))
        await engine.send(command: go)

        // Safety net in case the engine never answers: ask it to stop, so its
        // bestmove still lands on this search rather than on the next one, and
        // give up on it a little after that.
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            let stopped = await self?.stopIfPending(searchID: id) ?? false
            guard stopped else { return }
            try? await Task.sleep(for: .seconds(2))
            await self?.finish(searchID: id, bestMove: nil)
        }

        for await result in stream {
            return result
        }
        return SearchResult(bestMove: nil, lines: [])
    }

    /// Two search threads where the device has cores to spare; one otherwise.
    static var searchThreads: Int {
        ProcessInfo.processInfo.activeProcessorCount >= 4 ? 2 : 1
    }

    /// Stockfish's neural network files, copied into the app by scripts/fetch_nnue.sh.
    static let networkFiles = ["nn-1111cefa1111", "nn-37f18f62d772"]

    /// Whether the network files are in the app. Without them Stockfish would quit.
    static var hasNetworks: Bool {
        networkFiles.allSatisfy { Bundle.main.url(forResource: $0, withExtension: "nnue") != nil }
    }

    /// Starts the engine once. Searches that arrive meanwhile wait for the same start.
    private func startIfNeeded() async -> Bool {
        if let startTask { return await startTask.value }
        let task = Task { await self.startEngine() }
        startTask = task
        return await task.value
    }

    private func startEngine() async -> Bool {
        guard Self.hasNetworks else { return false }

        await engine.start()
        var attempts = 0
        while !(await engine.isRunning), attempts < 200 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard await engine.isRunning, let responses = await engine.responseStream else {
            return false
        }

        listener = Task { [weak self] in
            for await response in responses {
                await self?.handle(response)
            }
        }

        // The engine passes on its own "readyok" once its setup (which points
        // Stockfish at the network files) is done.
        attempts = 0
        while readyCount == 0, attempts < 50 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(20))
        }

        // Then ask again: this "readyok" comes once the networks are loaded.
        let seen = readyCount
        await engine.send(command: .setoption(id: "Hash", value: "64"))
        await engine.send(command: .setoption(id: "Threads", value: "\(Self.searchThreads)"))
        await engine.send(command: .isready)
        attempts = 0
        while readyCount == seen, attempts < 400 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(20))
        }
        return readyCount > seen
    }

    private func handle(_ response: EngineResponse) {
        if case .readyok = response {
            readyCount += 1
            return
        }
        guard var search = pending else { return }

        switch response {
        case .info(let info):
            guard
                let moves = info.pv, let first = moves.first,
                let depth = info.depth,
                let score = info.score,
                score.lowerbound != true, score.upperbound != true,
                isLegal(first, in: search.position)
            else { return }

            let evaluation: Evaluation
            if let mate = score.mate {
                evaluation = .mate(mate)
            } else if let cp = score.cp {
                evaluation = .centipawns(Int(cp))
            } else {
                return
            }

            let index = info.multipv ?? 1
            if let existing = search.lines[index], existing.depth > depth { return }
            search.lines[index] = (depth, EngineLine(moves: moves, evaluation: evaluation))
            pending = search

        case .bestmove(let move, _):
            if move == "(none)" {
                finish(searchID: search.id, bestMove: nil)
            } else if isLegal(move, in: search.position) {
                finish(searchID: search.id, bestMove: move)
            }

        default:
            break
        }
    }

    /// Tells the engine to stop if `searchID` is still the search in progress,
    /// and says whether it was.
    private func stopIfPending(searchID: Int) async -> Bool {
        guard let search = pending, search.id == searchID else { return false }
        await engine.send(command: .stop)
        return true
    }

    private func finish(searchID: Int, bestMove: String?) {
        guard let search = pending, search.id == searchID else { return }
        let lines = search.lines.sorted { $0.key < $1.key }.map { $0.value.line }
        search.continuation.yield(SearchResult(bestMove: bestMove ?? lines.first?.firstMove, lines: lines))
        search.continuation.finish()
        pending = nil
    }

    /// Whether `move` is legal in `position` for the side to move. ChessKit's parser
    /// checks the move itself but not whose turn it is.
    private func isLegal(_ move: String, in position: Position) -> Bool {
        guard let parsed = EngineLANParser.parse(move: move, for: position.sideToMove, in: position) else { return false }
        return parsed.piece.color == position.sideToMove
    }
}
