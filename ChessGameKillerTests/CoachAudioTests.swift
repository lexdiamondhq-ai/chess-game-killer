import AVFoundation
import XCTest
@testable import ChessGameKiller

/// How the coach's voice fits in with the phone: the ring switch, other audio, and Leo's turns
/// to talk during a lesson.
@MainActor
final class CoachAudioTests: XCTestCase {

    /// Lessons, reels and Talk It Through go quiet with the ring switch on silent, like the
    /// game's own sounds, unless the person turns "Speak on silent" on in Settings.
    func testTheCoachRespectsTheSilentSwitchUnlessAsked() {
        let quiet = CoachVoice.lessonAudio(speaksOnSilent: false)
        XCTAssertEqual(quiet.category, .ambient, "Silent means silent")
        XCTAssertTrue(quiet.options.contains(.duckOthers), "Music still turns down while the coach talks")

        let loud = CoachVoice.lessonAudio(speaksOnSilent: true)
        XCTAssertEqual(loud.category, .playback, "Out loud whatever the switch says, like a video")
        XCTAssertTrue(loud.options.contains(.duckOthers))
    }

    func testSpeakOnSilentIsOffUntilChosen() {
        UserDefaults.standard.removeObject(forKey: CoachVoice.speaksOnSilentKey)
        XCTAssertFalse(CoachVoice.shared.speaksOnSilent)
    }

    /// Leo (Talk It Through) sets the lesson audio up for his replies, unless a lesson already
    /// holds it, which he reads from the voice rather than from the audio session's category:
    /// with the ring switch respected, a lesson's category is the same as the game's.
    func testLeoKnowsWhenALessonHoldsTheAudio() {
        let voice = CoachVoice.shared
        voice.endLesson()
        XCTAssertFalse(voice.lessonAudioActive)
        voice.beginLesson()
        XCTAssertTrue(voice.lessonAudioActive)
        voice.endLesson()
        XCTAssertFalse(voice.lessonAudioActive)
    }
}
