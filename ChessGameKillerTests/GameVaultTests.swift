import XCTest
@testable import ChessGameKiller

/// Saved games survive a file that can't be fully read.
@MainActor
final class GameVaultTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString).json")
    }

    func testOneUnreadableGameDoesNotCostTheOthers() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let kept = RewindSample.game(id: UUID())
        let broken = RewindSample.game(id: UUID())
        let data = try JSONEncoder().encode([kept, broken])
        var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        // A game written by an older (or newer) version, missing a field this one needs.
        objects[1].removeValue(forKey: "moves")
        try JSONSerialization.data(withJSONObject: objects).write(to: url)

        let games = GameVault.load(from: url)
        XCTAssertEqual(games.map(\.id), [kept.id])
    }

    func testAFileThatCantBeReadIsMovedAsideNotOverwritten() throws {
        let url = temporaryURL()
        let aside = url.deletingPathExtension().appendingPathExtension("unreadable.json")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: aside)
        }
        let garbage = Data("not the games".utf8)
        try garbage.write(to: url)

        XCTAssertEqual(GameVault.load(from: url), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: aside), garbage)

        // The next save starts a fresh file and leaves the old bytes alone.
        let vault = GameVault(fileURL: url)
        vault.record(RewindSample.game(id: UUID()))
        vault.waitUntilSaved()
        XCTAssertEqual(GameVault.load(from: url).count, 1)
        XCTAssertEqual(try Data(contentsOf: aside), garbage)
    }

    func testUndoPutsADeletedGameBackWhereItWas() {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let vault = GameVault(fileURL: url)
        for _ in 0..<3 { vault.record(RewindSample.game(id: UUID())) }
        let before = vault.games.map(\.id)
        let middle = before[1]
        let deleted = vault.delete(middle)
        XCTAssertEqual(vault.games.count, 2)
        XCTAssertNotNil(deleted)
        if let deleted { vault.restore(deleted) }
        XCTAssertEqual(vault.games.map(\.id), before)
        // Undo twice changes nothing.
        if let deleted { vault.restore(deleted) }
        XCTAssertEqual(vault.games.count, 3)
        XCTAssertNil(vault.delete(UUID()))
    }
}
