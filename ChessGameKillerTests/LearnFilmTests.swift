import AVFoundation
import XCTest
@testable import ChessGameKiller

/// Learn's film, "The Maze That Remembers": it ships with picture and sound, it plays once, and
/// it stays out of the tests and CI's pictures.
@MainActor
final class LearnFilmTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "LearnFilmTests")
        defaults.removePersistentDomain(forName: "LearnFilmTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "LearnFilmTests")
        super.tearDown()
    }

    func testTheFilmShipsWithPictureAndSound() async throws {
        let url = try XCTUnwrap(LearnFilm.url, "learn-film.mp4 is in the app")
        let film = AVURLAsset(url: url)
        let seconds = try await film.load(.duration).seconds
        XCTAssertEqual(seconds, 42, accuracy: 1, "Eight shots of five seconds, and the last one held")
        let picture = try await film.loadTracks(withMediaType: .video)
        let sound = try await film.loadTracks(withMediaType: .audio)
        XCTAssertFalse(picture.isEmpty)
        XCTAssertFalse(sound.isEmpty, "Leo's voice and the score")
    }

    func testItPlaysOnce() {
        XCTAssertTrue(LearnFilm.shouldShow(defaults, underTest: false), "The first time Learn opens")
        LearnFilm.markSeen(defaults)
        XCTAssertFalse(LearnFilm.shouldShow(defaults, underTest: false), "Never by itself again")
    }

    func testItStaysOutOfTestsAndCIPictures() {
        XCTAssertFalse(LearnFilm.shouldShow(defaults), "The unit tests draw Learn, not its film")
        defaults.set("game", forKey: "showcase")
        XCTAssertFalse(LearnFilm.shouldShow(defaults, underTest: false))
        defaults.removeObject(forKey: "showcase")
        defaults.set("learn", forKey: "showcaseOpen")
        XCTAssertFalse(LearnFilm.shouldShow(defaults, underTest: false), "A picture of Learn shows Learn")
    }
}
