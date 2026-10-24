import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// The Train page and the screen behind each of its doors, at iPhone size: for a brand-new
/// player, and for one a few weeks in with games, mistakes, reviews and a repertoire.
/// When SNAPSHOT_DIR is set the pictures are saved there.
@MainActor
final class TrainSnapshotTests: XCTestCase {
    private let theme = BoardTheme.named(.gilded)

    func testTrainPageForANewPlayer() throws {
        let sample = TrainSample(settled: false)
        let window = try show(sample.hub(theme: theme))
        try save(window, "train-hub-1-new")
        window.isHidden = true
    }

    func testTrainPageAFewWeeksIn() throws {
        let sample = TrainSample(settled: true)
        let window = try show(sample.hub(theme: theme), wait: 4)
        try save(window, "train-hub-2-settled")
        scroll(window, to: 900)
        try save(window, "train-hub-3-foot")
        window.isHidden = true
    }

    func testTrainPageOnNeon() throws {
        let sample = TrainSample(settled: true)
        let window = try show(sample.hub(theme: .named(.neon)), wait: 4)
        try save(window, "train-hub-4-neon")
        window.isHidden = true
    }

    func testEveryDoor() throws {
        let sample = TrainSample(settled: true)
        for door in TrainDoor.allCases {
            let window = try show(sample.door(door, theme: theme), wait: 2.5)
            try save(window, "train-door-\(door.rawValue)")
            window.isHidden = true
        }
    }

    func testTheGamesDoorBeforeAnyGames() throws {
        let sample = TrainSample(settled: false)
        let window = try show(sample.door(.games, theme: theme), wait: 2)
        try save(window, "train-door-games-empty")
        window.isHidden = true
    }

    /// A puzzle in Leo's session, with his microphone at the end of his card to talk it through:
    /// on this phone, and on an iPhone SE-sized screen.
    func testASessionPuzzleOffersTalk() throws {
        let sample = TrainSample(settled: true)
        let library = try XCTUnwrap(TrainingLibrary.shared)
        let drills = library.drills(for: "forks").filter { $0.type == .move }.prefix(3)
        XCTAssertEqual(drills.count, 3)
        let plan = SessionPlan(title: "Today", focus: library.skill("forks"), lesson: nil,
                               items: drills.map { SessionItem(content: .drill($0), role: .focus) })
        let screens: [(name: String, frame: CGRect?)] = [
            ("train-session-drill", nil),
            ("train-session-drill-small", CGRect(x: 0, y: 42, width: 375, height: 667)),
        ]
        for (name, frame) in screens {
            let view = SessionView(plan: plan, theme: theme, startsAtOnce: true)
                .environment(sample.training)
                .environment(sample.puzzles)
            let window = try show(view, wait: 2.5, frame: frame)
            try save(window, name)
            window.isHidden = true
        }
    }

    /// A puzzle on the looks from Settings, and on Drift, the rival's board that training used
    /// to borrow when "match the rival's board" was on.
    func testAPuzzleOnEachLook() throws {
        let sample = TrainSample(settled: true)
        let library = try XCTUnwrap(TrainingLibrary.shared)
        let drills = library.drills(for: "forks").filter { $0.type == .move }.prefix(1)
        let plan = SessionPlan(title: "Today", focus: library.skill("forks"), lesson: nil,
                               items: drills.map { SessionItem(content: .drill($0), role: .focus) })
        let looks: [BoardTheme.ID] = [.gilded, .midnight, .noir, .faberge, .neon, .drift]
        for look in looks {
            let view = SessionView(plan: plan, theme: .named(look), startsAtOnce: true)
                .environment(sample.training)
                .environment(sample.puzzles)
            let window = try show(view, wait: 2.5)
            try save(window, "study-puzzle-\(look.rawValue)")
            window.isHidden = true
        }
    }

    /// Coach Vera: the picker in Settings, the Train page with her portrait, and one of her
    /// session puzzles. The pick is put back to Leo afterwards.
    func testCoachVera() throws {
        let choice = CoachChoice.shared
        let before = choice.coach
        defer { choice.coach = before }
        choice.coach = .vera

        let settings = try show(SettingsSheet(), wait: 2.5)
        for (offset, name) in [(1250, "coaches-1-settings"), (1700, "coaches-2-settings-sound")] {
            scroll(settings, to: CGFloat(offset))
            try save(settings, name)
        }
        settings.isHidden = true

        let sample = TrainSample(settled: true)
        let hub = try show(sample.hub(theme: theme), wait: 3)
        try save(hub, "coaches-3-train-vera")
        hub.isHidden = true

        let library = try XCTUnwrap(sample.training.library)
        XCTAssertEqual(library.coach.name, "Vera")
        let drills = library.drills(for: "forks").filter { $0.type == .move }.prefix(2)
        let plan = SessionPlan(title: "Today", focus: library.skill("forks"), lesson: nil,
                               items: drills.map { SessionItem(content: .drill($0), role: .focus) })
        let session = try show(SessionView(plan: plan, theme: theme, startsAtOnce: true)
            .environment(sample.training)
            .environment(sample.puzzles), wait: 2.5)
        try save(session, "coaches-4-session-vera")
        session.isHidden = true
    }

    /// Your Chess DNA: the card on the Your games door, the profile itself (top and openings),
    /// and the line the coach adds at the end of a game.
    func testChessDNA() throws {
        let sample = TrainSample(settled: true)
        var games: [SavedGame] = []
        let slip: [Int: MoveReview.Grade] = [21: .mistake, 25: .blunder]
        for day in 0..<8 {
            // Attacking games as White, the older ones with a slip or two, two of the newest lost.
            games.append(ChessDNATests.game(ChessDNATests.friedLiver, result: day == 1 || day == 6 ? .loss : .win,
                                            accuracy: day < 4 ? 86 : 71, daysAgo: Double(day * 2),
                                            grades: day < 4 ? [:] : slip))
        }
        for day in 0..<3 {
            games.append(ChessDNATests.game(ChessDNATests.quietLondon, white: false, result: day == 0 ? .draw : .loss,
                                            accuracy: 78, daysAgo: Double(day * 2 + 1)))
        }
        let vault = GameVault(games: games.sorted { $0.date > $1.date })
        var progress = sample.puzzles.progress
        progress.themeStats = ["fork": ThemeRecord(attempts: 40, clean: 34), "pin": ThemeRecord(attempts: 30, clean: 14),
                               "mateIn2": ThemeRecord(attempts: 25, clean: 17)]
        let puzzles = PuzzleStore(progress: progress)
        let dna = ChessDNA.make(games: vault.games, puzzleStats: progress.themeStats, puzzlesPlayed: progress.played)
        XCTAssertNotNil(dna.style)

        func environment(_ view: some View) -> some View {
            view
                .tint(theme.trainingAccent)
                .preferredColorScheme(.dark)
                .environment(sample.training)
                .environment(puzzles)
                .environment(vault)
                .environment(sample.repertoire)
                .environment(sample.endgames)
                .environment(sample.think)
        }
        let door = try show(environment(NavigationStack { GamesDoorView(theme: theme) }), wait: 3)
        try save(door, "dna-0-door")
        door.isHidden = true

        let profile = try show(environment(NavigationStack { ChessDNAView(dna: dna, theme: theme) }), wait: 2.5)
        try save(profile, "dna-1-top")
        scroll(profile, to: 760)
        try save(profile, "dna-2-growth")
        scroll(profile, to: 1_500)
        try save(profile, "dna-3-openings")
        profile.isHidden = true

        let learned = environment(
            VStack { LearnedAboutYouRow(gameID: vault.games[0].id, theme: theme) }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background { TrainingBackdrop(theme: theme) }
        )
        let end = try show(learned, wait: 3)
        try save(end, "dna-4-learned")
        end.isHidden = true
    }

    // MARK: Drawing

    private func show(_ view: some View, wait: TimeInterval = 3, frame: CGRect? = nil) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = frame ?? scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        return window
    }

    private func scroll(_ window: UIWindow, to offset: CGFloat) {
        guard let scroll = Self.scrollViews(in: window).max(by: { $0.contentSize.height < $1.contentSize.height }) else { return }
        let top = -scroll.adjustedContentInset.top
        let bottom = max(top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: min(top + offset, bottom)), animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
    }

    private func save(_ window: UIWindow, _ name: String) throws {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
}

/// A player's training, in memory: brand new, or a few weeks in.
@MainActor
struct TrainSample {
    let training: TrainingStore
    let puzzles: PuzzleStore
    let vault: GameVault
    let repertoire: RepertoireStore
    let endgames: EndgameProgress
    let think: ThinkStore

    init(settled: Bool) {
        let day: TimeInterval = 86_400
        var progress = TrainingProgress()
        var puzzleProgress = PuzzleProgress()
        var entries: [RepertoireEntry] = []
        if settled, let library = TrainingLibrary.shared {
            progress.sessionsDone = 9
            progress.xp = 1_240
            // Trained yesterday, so today's session is still to do and the streak is alive.
            progress.streak = Streak(current: 6, best: 11,
                                     lastDay: Trainer.dayString(.now.addingTimeInterval(-day), calendar: .current))
            for lesson in library.lessons.prefix(6) {
                progress.lessonsDone[lesson.id] = .now.addingTimeInterval(-3 * day)
            }
            for skill in library.orderedSkills.prefix(5) {
                progress.skills[skill.id] = SkillRecord(rating: 900, attempts: 12, solved: 9,
                                                        lastPracticed: .now.addingTimeInterval(-2 * day))
            }
            // Two forks missed in recent games: today's focus.
            for (index, fen) in ["r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4",
                                 "r2qkbnr/ppp2ppp/2np4/4p3/2B1P1b1/2N2N2/PPPP1PPP/R1BQK2R w KQkq - 2 5"].enumerated() {
                progress.mistakes.append(GameMistake(
                    id: "fork-\(index)", fen: fen, best: "f3g5", played: "d2d3", skill: "forks",
                    title: "Missed a fork", created: .now.addingTimeInterval(-Double(index + 1) * day),
                    due: .now.addingTimeInterval(-day)))
            }
            puzzleProgress.rating = 1_412
            puzzleProgress.highestRating = 1_455
            puzzleProgress.played = 240
            puzzleProgress.solved = 171
            puzzleProgress.streak = 4
            puzzleProgress.rushBest = 23
            let lines = GrandmasterContent.shared.openings
            for (name, side) in [("Italian Game", "w"), ("Caro-Kann Defense", "b"), ("Queen's Gambit Declined", "b")] {
                if let line = lines.first(where: { $0.name == name }) {
                    entries.append(RepertoireEntry(lineID: line.id, name: line.name, moves: line.moves, side: side,
                                                   box: 1, due: .now.addingTimeInterval(side == "w" ? day : -day)))
                }
            }
        }
        training = TrainingStore(library: TrainingLibrary.shared, progress: progress)
        puzzles = PuzzleStore(progress: puzzleProgress)
        vault = GameVault(games: settled ? Self.games() : [])
        repertoire = RepertoireStore(entries: entries)
        // A few weeks in: the first endgames learned, one of them clean.
        let studies = GrandmasterContent.shared.endgames
        var records: [String: EndgameRecord] = [:]
        if settled {
            for (index, study) in studies.prefix(3).enumerated() {
                records[study.id] = EndgameRecord(date: .now.addingTimeInterval(-Double(index + 1) * day),
                                                  moves: 12, clean: index == 0)
            }
        }
        endgames = EndgameProgress(studies: studies, records: records)
        var thinking = ThinkProgress()
        if settled {
            thinking.positions = 15
            thinking.found = 11
            thinking.rounds = 3
            thinking.bestRound = 19
        }
        think = ThinkStore(progress: thinking)
    }

    func hub(theme: BoardTheme) -> some View {
        TrainingHubView(theme: theme)
            .environment(training)
            .environment(puzzles)
            .environment(vault)
    }

    /// One door's screen, as it opens from the Train page.
    func door(_ door: TrainDoor, theme: BoardTheme) -> some View {
        NavigationStack {
            Group {
                switch door {
                case .puzzles: PuzzlesDoorView(theme: theme)
                case .lessons: LessonsDoorView(theme: theme)
                case .openings: OpeningsView(theme: theme)
                case .endgames: EndgamesDoorView(theme: theme)
                case .calculation: CalculationDoorView(theme: theme)
                case .games: GamesDoorView(theme: theme)
                }
            }
        }
        .tint(theme.trainingAccent)
        .preferredColorScheme(.dark)
        .environment(training)
        .environment(puzzles)
        .environment(vault)
        .environment(repertoire)
        .environment(endgames)
        .environment(think)
    }

    /// A few weeks of games against the rivals.
    private static func games() -> [SavedGame] {
        let plan: [(daysAgo: Double, level: MatchController.Level, result: SavedGame.Result, accuracy: Int)] = [
            (0, .club, .loss, 74), (1, .expert, .loss, 69), (2, .club, .win, 91), (3, .casual, .win, 94),
            (4, .club, .draw, 82), (6, .grandmaster, .loss, 63), (8, .club, .win, 86),
        ]
        return plan.map { item in
            let date = Date.now.addingTimeInterval(-item.daysAgo * 86_400 - 3_600)
            let base = RewindSample.game(date: date)
            return SavedGame(id: UUID(), date: date, opponent: item.level.rival.name, level: item.level.rawValue,
                             playerIsWhite: true, result: item.result, accuracy: item.accuracy,
                             positions: base.positions, moves: base.moves, moments: base.moments)
        }
    }
}
