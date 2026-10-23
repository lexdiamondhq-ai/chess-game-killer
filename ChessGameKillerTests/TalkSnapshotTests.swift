import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// Pictures of Talk it through at iPhone size: ready, listening, typing, checking, a rich answer
/// (a mistake with its refutation, a claim right, one wrong because of a pin, one partly right, a
/// missed threat, mixed habits and Leo's answer), a clean answer, a failure, and the rich answer on
/// an iPhone SE-sized screen. Saved to SNAPSHOT_DIR as talk-*.png. Every session is a preview, so
/// nothing touches the engine, the network or the microphone.
@MainActor
final class TalkSnapshotTests: XCTestCase {

    private let defaults = UserDefaults.standard
    private var saved: [String: Any?] = [:]
    private var savedDesign: Font.Design = .default
    private static let keys = ["boardTheme", "haptics"]
    private static let theme: BoardTheme = .gilded

    override func setUp() async throws {
        for key in Self.keys {
            saved[key] = defaults.object(forKey: key)
        }
        defaults.set("gilded", forKey: "boardTheme")
        defaults.set(false, forKey: "haptics")
        savedDesign = ThemeFont.design
        ThemeFont.use(Self.theme)
    }

    override func tearDown() async throws {
        for (key, value) in saved {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        ThemeFont.design = savedDesign
    }

    // MARK: Before Leo checks

    func testReady() throws {
        let session = TalkSession.preview(fen: Self.pinFEN, player: .white, phase: .ready)
        try snapshot("talk-ready", session: session)
    }

    func testListening() throws {
        let session = TalkSession.preview(fen: Self.pinFEN, player: .white, phase: .listening,
                                          transcript: "His bishop pins my knight, but my e4 pawn", level: 0.55)
        try snapshot("talk-listening", session: session)
    }

    func testTyping() throws {
        let session = TalkSession.preview(fen: Self.pinFEN, player: .white, phase: .typing)
        session.draft = "His bishop pins my knight, but my e4 pawn is safe. I'll play Bf4."
        try snapshot("talk-typing", session: session)
    }

    func testChecking() throws {
        let session = TalkSession.preview(fen: Self.pinFEN, player: .white, phase: .checking,
                                          transcript: Self.pinSaid)
        try snapshot("talk-checking", session: session)
    }

    // MARK: Leo's answers

    func testAnswered() throws {
        try snapshot("talk-answered", session: Self.pinAnswered())
    }

    func testAnsweredClean() throws {
        let session = TalkSession.preview(fen: Self.italianFEN, player: .black, phase: .answered,
                                          transcript: Self.italianSaid, check: Self.italianCheck,
                                          answer: Self.italianAnswer)
        try snapshot("talk-answered-clean", session: session)
    }

    func testFailed() throws {
        let session = TalkSession.preview(fen: Self.pinFEN, player: .white, phase: .failed,
                                          transcript: Self.pinSaid,
                                          problem: "Leo needs the internet to check your plan.")
        try snapshot("talk-failed", session: session)
    }

    /// The rich answer at iPhone SE size: 375 by 667, a status bar's inset at the top and no home
    /// indicator. The window starts lower on the screen, so only that much of the real inset reaches it.
    func testSmallPhone() throws {
        try snapshot("talk-small-phone", session: Self.pinAnswered(),
                     frame: CGRect(x: 0, y: 42, width: 375, height: 667))
    }

    // MARK: Positions and verdicts

    /// Scotch Four Knights after 5...Bb4, White to move: the bishop pins the knight on c3, so
    /// Black threatens Nxe4. 6.Bf4? lets it happen; 6.Nxc6 is best.
    private static let pinFEN = "r1bqk2r/pppp1ppp/2n2n2/8/1b1NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 3 6"
    private static let pinSaid = "His bishop pins my knight, but my e4 pawn is safe. I'll play bishop f4, and I'm a bit better here."
    private static let pinAnswer = "Right about the pin, and that's the trouble: your knight on c3 can't take back, so your e4 pawn isn't safe. After bishop f4, knight takes e4 just wins it. It's about equal now. Trade knights on c6 first, then guard e4."

    private static var pinCheck: TalkCheck {
        TalkCheck(
            understood: true,
            player: "white",
            move: TalkMoveCheck(said: "I'll play bishop f4", san: "Bf4", uci: "c1f4", grade: .mistake,
                                note: "After Bf4, Nxe4 wins your e4 pawn.",
                                reply: TalkMove(san: "Nxe4", uci: "f6e4"),
                                squares: ["c1", "f4", "f6", "e4"],
                                arrows: [TalkArrow(from: "c1", to: "f4", tone: .info),
                                         TalkArrow(from: "f6", to: "e4", tone: .bad)]),
            claims: [
                TalkClaim(id: "c1", said: "his bishop pins my knight", kind: .pinned, verdict: .right,
                          note: "The bishop on b4 pins your knight on c3 to your king.",
                          squares: ["b4", "c3", "e1"],
                          arrows: [TalkArrow(from: "b4", to: "e1", tone: .info)]),
                TalkClaim(id: "c2", said: "my e4 pawn is safe", kind: .safe, verdict: .wrong,
                          note: "Your knight on c3 is pinned, so it can't take back on e4.",
                          squares: ["e4", "c3"],
                          arrows: [TalkArrow(from: "f6", to: "e4", tone: .bad),
                                   TalkArrow(from: "b4", to: "e1", tone: .info)]),
                TalkClaim(id: "c3", said: "I'm a bit better here", kind: .eval, verdict: .partly,
                          note: "It's about equal right now."),
            ],
            missed: [
                TalkMissed(kind: "threat", note: "They threaten Nxe4, winning a pawn.",
                           squares: ["f6", "e4"],
                           arrows: [TalkArrow(from: "f6", to: "e4", tone: .bad)]),
            ],
            habits: TalkHabits(threats: .missed, forcing: TalkHabits.Mark.none, safety: .missed),
            eval: TalkEval(cp: 13),
            best: TalkMove(san: "Nxc6", uci: "d4c6")
        )
    }

    private static func pinAnswered() -> TalkSession {
        TalkSession.preview(fen: pinFEN, player: .white, phase: .answered, transcript: pinSaid,
                            check: pinCheck, answer: pinAnswer)
    }

    /// Italian Game after 5.O-O, Black to move: castling is best, and every idea holds up.
    private static let italianFEN = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQ1RK1 b kq - 2 5"
    private static let italianSaid = "His bishop eyes f7, so I'll castle. My knight on f6 is safe, and after castling my king is safe too."
    private static let italianAnswer = "Spot on. His bishop does eye f7, your knight is safe, and castling is the best move here. That's exactly how to think before you move."

    private static var italianCheck: TalkCheck {
        TalkCheck(
            understood: true,
            player: "black",
            move: TalkMoveCheck(said: "I'll castle", san: "O-O", uci: "e8g8", grade: .best,
                                note: "O-O is the best move.",
                                reply: TalkMove(san: "Nbd2", uci: "b1d2"),
                                squares: ["e8", "g8"],
                                arrows: [TalkArrow(from: "e8", to: "g8", tone: .good)]),
            claims: [
                TalkClaim(id: "c1", said: "his bishop eyes f7", kind: .attacks, verdict: .right,
                          note: "The bishop on c4 hits f7.",
                          squares: ["c4", "f7"],
                          arrows: [TalkArrow(from: "c4", to: "f7", tone: .info)]),
                TalkClaim(id: "c2", said: "my knight on f6 is safe", kind: .safe, verdict: .right,
                          note: "Nothing can take your knight on f6 and win it.",
                          squares: ["f6"]),
                TalkClaim(id: "c3", said: "after castling my king is safe", kind: .safe, verdict: .right,
                          note: "After O-O, no check or attack reaches your king.",
                          squares: ["g8"]),
            ],
            habits: TalkHabits(threats: .good, forcing: .good, safety: .good),
            eval: TalkEval(cp: -32)
        )
    }

    // MARK: Taking the picture

    /// Shows the panel in a window the size of the screen (or of `frame`) and saves a picture of it.
    private func snapshot(_ name: String, session: TalkSession, frame: CGRect? = nil,
                          wait: TimeInterval = 1.5) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = frame ?? scene.coordinateSpace.bounds
        let panel = TalkPanel(session: session, theme: Self.theme, play: { _ in }, close: {})
        window.rootViewController = UIHostingController(rootView: panel)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        window.layoutIfNeeded()

        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        window.isHidden = true
    }
}
