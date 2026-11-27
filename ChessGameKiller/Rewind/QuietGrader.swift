import Foundation

/// Reads the games played here against people. A game with a friend, online or by the day is
/// kept the moment it ends, with no grades: nobody waits on the engine at the end of a game.
/// This grades the player's side of it afterwards (about twenty seconds of engine time a game,
/// and only while nothing else wants the engine), so Chess DNA and Leo's report read it like
/// any other game, and its real mistakes go to "Fix your mistakes".
@MainActor
final class QuietGrader {
    private let vault: GameVault
    private let store: TrainingStore?
    private let grader: GameImportGrader
    /// Whether to leave the engine alone for now. The app holds back on a hot phone and in
    /// Low Power Mode; the games wait for the next time.
    var holdsBack: @MainActor () -> Bool = { PowerPolicy.shared.isConstrained }
    private var task: Task<Void, Never>?

    /// The most games read in one go, so a long backlog is read a little at a time: when the
    /// app opens, and again each time a game against a person ends.
    static let atATime = 12

    init(vault: GameVault, store: TrainingStore?, engine: any ChessEngine = StockfishEngine.shared) {
        self.vault = vault
        self.store = store
        grader = GameImportGrader(engine: engine, quiet: true)
    }

    /// Reads the games still waiting, newest first. Does nothing while a reading is under way:
    /// that one finds the new game by itself.
    func catchUp() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run()
            self?.task = nil
        }
    }

    /// Stops after the search under way. Games already read stay read.
    func stop() {
        task?.cancel()
        task = nil
    }

    /// One go: up to `atATime` games, newest first. Stops early when the phone should hold
    /// back or the engine has nothing to say; what is left waits for the next go.
    func run() async {
        var read = 0
        // Games whose positions don't replay: left as they are, and not asked about again this go.
        var setAside: Set<UUID> = []
        while read < Self.atATime, !Task.isCancelled, !holdsBack() {
            guard let game = vault.games.first(where: { $0.awaitsGrading && !setAside.contains($0.id) }) else { return }
            switch await grader.grade(game) {
            case .graded(let graded):
                read += 1
                // Deleted while it was being read: nothing to bring up to date.
                guard vault.game(game.id) != nil else { continue }
                vault.record(graded)
                if let store { _ = GameImporter.saveMistakes(from: graded, to: store, at: graded.date) }
            case .unreadable:
                setAside.insert(game.id)
            case .stopped:
                return
            }
        }
    }
}
