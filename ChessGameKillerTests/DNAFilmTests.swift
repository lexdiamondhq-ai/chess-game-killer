import AVFoundation
import XCTest
@testable import ChessGameKiller

/// Chess DNA's film, "The Forge": it ships with picture and sound, it plays once, and it stays
/// out of the tests and CI's pictures.
@MainActor
final class DNAFilmTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "DNAFilmTests")
        defaults.removePersistentDomain(forName: "DNAFilmTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "DNAFilmTests")
        super.tearDown()
    }

    func testTheFilmShipsWithPictureAndSound() async throws {
        let url = try XCTUnwrap(DNAFilm.url, "dna-film.mp4 is in the app")
        let film = AVURLAsset(url: url)
        let seconds = try await film.load(.duration).seconds
        XCTAssertEqual(seconds, 31, accuracy: 1, "Six shots and the last one held")
        let picture = try await film.loadTracks(withMediaType: .video)
        let sound = try await film.loadTracks(withMediaType: .audio)
        XCTAssertFalse(picture.isEmpty)
        XCTAssertFalse(sound.isEmpty, "Leo's voice and the score")
    }

    func testItPlaysOnce() {
        XCTAssertTrue(DNAFilm.shouldShow(defaults, underTest: false), "The first time Chess DNA opens")
        DNAFilm.markSeen(defaults)
        XCTAssertFalse(DNAFilm.shouldShow(defaults, underTest: false), "Never by itself again")
    }

    func testItStaysOutOfTestsAndCIPictures() {
        XCTAssertFalse(DNAFilm.shouldShow(defaults), "The unit tests draw Chess DNA, not its film")
        defaults.set("game", forKey: "showcase")
        XCTAssertFalse(DNAFilm.shouldShow(defaults, underTest: false))
        defaults.removeObject(forKey: "showcase")
        defaults.set("dna", forKey: "showcaseOpen")
        XCTAssertFalse(DNAFilm.shouldShow(defaults, underTest: false), "A picture of Chess DNA shows Chess DNA")
    }

    func testItIsNotLearnsFilm() {
        XCTAssertNotEqual(DNAFilm.key, LearnFilm.key, "Seeing one film does not skip the other")
        XCTAssertNotEqual(DNAFilm.url, LearnFilm.url)
    }
}
