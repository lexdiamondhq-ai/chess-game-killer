import ChessKit
import XCTest
@testable import ChessGameKiller

/// On the line: staking a named piece on a rival game.
@MainActor
final class OnTheLineTests: XCTestCase {

    /// White's e-pawn takes on d5: the e-pawn is Piece of the Match.
    private func ePawnTakes() -> PieceLedger {
        let game = GameModel()
        for move in ["e2e4", "d7d5", "e4d5"] { XCTAssertTrue(game.playEngineMove(move)) }
        return game.ledger!
    }

    private func named(_ slots: ArmySlot...) -> ArmyStore {
        let store = ArmyStore()
        for (index, slot) in slots.enumerated() { store.rename(slot, to: "Piece\(index)") }
        return store
    }

    private func stakes(_ level: MatchController.Level, _ slot: ArmySlot?) -> GameStakes {
        GameStakes(level: level, assisted: false, staked: slot)
    }

    func testOnlyNamedPiecesOtherThanTheKingCanGoOnTheLine() {
        let store = named(.ePawn, .king, .kingsKnight)
        XCTAssertEqual(Set(store.stakeable), [.ePawn, .kingsKnight])
        XCTAssertTrue(store.canStake(nil, against: .club))
        XCTAssertTrue(store.canStake(.ePawn, against: .club))
        XCTAssertFalse(store.canStake(.king, against: .club))
        XCTAssertFalse(store.canStake(.dPawn, against: .club), "No name yet")
    }

    func testAWinOnTheLineEarnsDoubleAndATrophy() {
        let store = named(.ePawn)
        let news = store.record(ePawnTakes(), playerColor: .white, won: true, stakes: stakes(.beginner, .ePawn))
        // 13 for the game (see ArmyTests), doubled.
        XCTAssertEqual(store.record(for: .ePawn).xp, 26)
        // Pieces not on the line earn as usual.
        XCTAssertEqual(store.record(for: .aPawn).xp, 6)
        XCTAssertEqual(store.record(for: .ePawn).trophies, [MatchController.Level.beginner.rawValue])
        XCTAssertTrue(news.contains { $0.slot == .ePawn && $0.kind == .wonStake(rival: "Spark") })
        XCTAssertNil(store.captor(of: .ePawn))
    }

    func testALossOnTheLineHandsThePieceToTheRivalUntilItIsBeaten() {
        let store = named(.ePawn, .kingsKnight)
        let news = store.record(ePawnTakes(), playerColor: .white, won: false, stakes: stakes(.club, .ePawn))
        XCTAssertEqual(store.captor(of: .ePawn), .club)
        XCTAssertEqual(store.prisoner(of: .club), .ePawn)
        XCTAssertEqual(news.first?.kind, .captured(rival: "Pulse"), "The biggest news of the game")
        XCTAssertFalse(store.stakeable.contains(.ePawn))
        // One prisoner per rival: nothing else goes on the line against Pulse until the rescue.
        XCTAssertFalse(store.canStake(.kingsKnight, against: .club))
        XCTAssertTrue(store.canStake(.kingsKnight, against: .expert))
        XCTAssertEqual(store.rescueNews(against: .club)?.slot, .ePawn)

        // A prisoner sits out: another loss, and a win elsewhere, earn it nothing.
        let held = store.record(for: .ePawn)
        store.record(ePawnTakes(), playerColor: .white, won: false, stakes: stakes(.club, nil))
        store.record(ePawnTakes(), playerColor: .white, won: true, stakes: stakes(.expert, nil))
        XCTAssertEqual(store.record(for: .ePawn), held)
        XCTAssertEqual(store.captor(of: .ePawn), .club)

        // Beating Pulse frees it, and it earns from that game.
        let rescue = store.record(ePawnTakes(), playerColor: .white, won: true, stakes: stakes(.club, nil))
        XCTAssertNil(store.captor(of: .ePawn))
        XCTAssertEqual(store.record(for: .ePawn).escapes, 1)
        XCTAssertGreaterThan(store.record(for: .ePawn).xp, held.xp)
        XCTAssertTrue(rescue.contains { $0.slot == .ePawn && $0.kind == .rescued(rival: "Pulse") })
        XCTAssertTrue(store.canStake(.kingsKnight, against: .club))
    }

    func testADrawOnTheLineChangesNothingButTheRecord() {
        let store = named(.ePawn)
        store.record(ePawnTakes(), playerColor: .white, won: nil, stakes: stakes(.club, .ePawn))
        XCTAssertNil(store.captor(of: .ePawn))
        XCTAssertTrue(store.record(for: .ePawn).trophies.isEmpty)
        XCTAssertEqual(store.record(for: .ePawn).games, 1)
    }

    func testAStakeThatIsNotAllowedIsIgnored() {
        let store = named(.king)
        store.record(ePawnTakes(), playerColor: .white, won: false, stakes: stakes(.club, .king))
        store.record(ePawnTakes(), playerColor: .white, won: false, stakes: stakes(.club, .dPawn))
        XCTAssertNil(store.prisoner(of: .club))
    }

    func testLeavingAStakedGameLosesThePiece() {
        let match = MatchController(engine: nil, sounds: nil)
        let store = named(.ePawn)
        match.onAbandon = { ledger, setup, assisted in
            store.record(ledger, playerColor: setup.playerColor, won: false,
                         stakes: GameStakes(level: setup.level, assisted: assisted, staked: setup.stake))
        }
        match.start(.init(opponent: .computer, playerColor: .white, level: .expert, stake: .ePawn))
        XCTAssertEqual(match.armyStakes.staked, .ePawn)
        for move in ["e2e4", "e7e5", "g1f3", "b8c6"] { XCTAssertTrue(match.game.playEngineMove(move)) }
        match.start(.init(opponent: .computer, playerColor: .white))
        XCTAssertEqual(store.captor(of: .ePawn), .expert)
    }

    func testPrisonersAndTrophiesAreSaved() throws {
        let store = named(.ePawn, .queen)
        store.record(ePawnTakes(), playerColor: .white, won: true, stakes: stakes(.beginner, .queen))
        let loss = ePawnTakes()
        store.record(loss, playerColor: .white, won: false, stakes: stakes(.club, .ePawn))
        let data = try JSONEncoder().encode(store.army)
        let again = try JSONDecoder().decode(ArmyStore.Army.self, from: data)
        XCTAssertEqual(again, store.army)
        XCTAssertEqual(ArmyStore(army: again).captor(of: .ePawn), .club)
        XCTAssertFalse(ArmyStore(army: again).record(for: .queen).trophies.isEmpty)
    }

    func testOldSavedArmiesHoldNoPrisoners() throws {
        let json = #"{}"#
        let army = try JSONDecoder().decode(ArmyStore.Army.self, from: Data(json.utf8))
        XCTAssertTrue(army.captives.isEmpty)
        let record = try JSONDecoder().decode(PieceRecord.self, from: Data(#"{"games":1}"#.utf8))
        XCTAssertTrue(record.trophies.isEmpty)
        XCTAssertEqual(record.escapes, 0)
    }

    func testStakeNewsReads() {
        let store = named(.ePawn)
        let staked = store.stakeNews(.ePawn, against: .club)
        XCTAssertEqual(staked.label, "ON THE LINE")
        XCTAssertEqual(staked.headline, "Piece0 is on the line against Pulse.")
        XCTAssertEqual(ArmyNews(slot: .ePawn, rank: .veteran, name: "Kestrel", kind: .captured(rival: "Pulse")).headline,
                       "Pulse is holding Kestrel. Beat Pulse to get it back.")
    }
}
