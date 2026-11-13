import ChessKit
import Foundation
import UIKit

/// Turns a photo or screenshot of a chess board into a position.
protocol BoardReader: Sendable {
    func read(_ image: UIImage) async throws -> BoardReading
    /// Opens the line to the reader ahead of a photo, so sending it doesn't wait on a fresh connection.
    func warmUp()
}

extension BoardReader {
    func warmUp() {}
}

/// What a reader saw. The draft is always from White's side; `whiteSide`
/// says which way round the picture was.
struct BoardReading: Equatable {
    var draft: PositionDraft
    var whiteSide: PositionDraft.WhiteSide
    var sureOfTurn: Bool
    var confidence: Confidence
    /// How long each part of the read took, for the stopwatch (nil from readers that don't time).
    var timing: ReadTiming? = nil

    enum Confidence: String, Decodable {
        case high, medium, low
    }
}

/// Where a read's time went, in seconds (Alex, 2026-11-13: "Stopwatch first").
struct ReadTiming: Equatable {
    /// Shrinking the photo on the phone.
    var prepare: Double
    /// Sending it and getting the answer back, the reading included.
    var roundTrip: Double
    /// The reading on the server, when it says.
    var server: Double?

    /// The trip there and back without the reading.
    var network: Double? { server.map { max(0, roundTrip - $0) } }
}

enum BoardReaderError: LocalizedError, Equatable {
    case notSetUp
    case noBoard
    case busy
    /// Everyone's scans for the day are used up (the server's daily ceiling).
    case full
    case offline
    case failed

    var errorDescription: String? {
        switch self {
        case .notSetUp: return "Photo reading isn't switched on yet. Set up the pieces to match your photo."
        case .noBoard: return "I couldn't find a chess board in that picture. Try a straighter, closer shot."
        case .busy: return "Too many scans in a row. Wait a minute and try again."
        case .full: return "The photo reader is full for today. It opens again tomorrow. Until then, set up the pieces by hand."
        case .offline: return "I couldn't reach the photo reader. Check your connection, or set up the pieces by hand."
        case .failed: return "I couldn't read that picture. Try again in a moment, or set up the pieces by hand."
        }
    }
}

/// Where the scanner server lives (scanner/ in this repo, deployed to
/// Cloudflare by .github/workflows/scanner.yml).
enum ScannerConfig {
    static let endpoint = URL(string: "https://chess-game-killer-scanner.chess-game-killer.workers.dev")
}

/// Sends the picture to the scanner server, which asks Claude to read the board.
/// The Anthropic key stays on the server.
struct CloudBoardReader: BoardReader {
    let endpoint: URL
    var session: URLSession = .shared

    static var live: BoardReader {
        if let endpoint = ScannerConfig.endpoint {
            return CloudBoardReader(endpoint: endpoint)
        }
        return UnavailableBoardReader()
    }

    /// The server's answer.
    struct Response: Decodable {
        let found: Bool
        let rows: [String]?
        let whiteSide: PositionDraft.WhiteSide?
        let sideToMove: String?
        let confidence: BoardReading.Confidence?
    }

    /// A tiny request to the server's front door. URLSession keeps the connection open, so the photo
    /// that follows skips the connection and security handshake (Alex, 2026-11-11: make it quicker).
    func warmUp() {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        let session = session
        Task.detached(priority: .utility) { _ = try? await session.data(for: request) }
    }

    func read(_ image: UIImage) async throws -> BoardReading {
        let clock = ContinuousClock()
        let prepareStart = clock.now
        guard let jpeg = image.preparedForReading() else { throw BoardReaderError.failed }
        let prepare = (clock.now - prepareStart).inSeconds

        var request = URLRequest(url: endpoint.appendingPathComponent("read"))
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(String(ScanCount.next()), forHTTPHeaderField: "X-Scan-Count")
        request.timeoutInterval = 120

        let result: (Data, URLResponse)
        let sendStart = clock.now
        do {
            result = try await session.upload(for: request, from: jpeg)
        } catch {
            throw Self.readerError(for: error)
        }
        let roundTrip = (clock.now - sendStart).inSeconds
        let (data, response) = result
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard status == 200 else { throw Self.refusal(status: status, body: data) }
        var reading = try Self.reading(from: data)
        let serverMs = http?.value(forHTTPHeaderField: "X-Read-Ms").flatMap(Double.init)
        reading.timing = ReadTiming(prepare: prepare, roundTrip: roundTrip, server: serverMs.map { $0 / 1000 })
        return reading
    }

    /// What to tell the player when the server turned the picture away. "Wait a minute" is
    /// only true of the per-minute limit; the day's ceiling says tomorrow (audit, 2026-11-12:
    /// both used to read "Too many scans in a row").
    static func refusal(status: Int, body: Data) -> BoardReaderError {
        struct Refusal: Decodable { let error: String? }
        let code = (try? JSONDecoder().decode(Refusal.self, from: body))?.error
        switch (status, code) {
        case (429, "daily_limit"?): return .full
        case (429, _): return .busy
        case (503, "not_configured"?): return .notSetUp
        default: return .failed
        }
    }

    /// Failures that really are about the phone's connection.
    static let connectionProblems: [URLError.Code] = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff,
    ]

    /// What to tell the player when the picture never got an answer. Only a
    /// network problem blames the connection; anything else is on our side.
    static func readerError(for error: Error) -> BoardReaderError {
        if let urlError = error as? URLError, connectionProblems.contains(urlError.code) {
            return .offline
        }
        return .failed
    }

    /// Builds the reading from the server's JSON.
    static func reading(from data: Data) throws -> BoardReading {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let answer = try? decoder.decode(Response.self, from: data) else { throw BoardReaderError.failed }
        guard answer.found, let rows = answer.rows else { throw BoardReaderError.noBoard }

        let whiteSide = answer.whiteSide ?? .bottom
        guard var draft = PositionDraft(rows: rows, whiteSide: whiteSide) else { throw BoardReaderError.failed }
        guard !draft.isEmpty else { throw BoardReaderError.noBoard }

        let turn: Piece.Color? = answer.sideToMove == "black" ? .black : answer.sideToMove == "white" ? .white : nil
        draft.sideToMove = turn ?? .white
        return BoardReading(
            draft: draft,
            whiteSide: whiteSide,
            sureOfTurn: turn != nil,
            confidence: answer.confidence ?? .medium
        )
    }
}

/// This month's photos so far, counting the one being sent. The server reads
/// a player's first 100 scans each month with its fastest model.
enum ScanCount {
    static func next(defaults: UserDefaults = .standard, now: Date = .now, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: now)
        let month = (parts.year ?? 0) * 100 + (parts.month ?? 0)
        let count = defaults.integer(forKey: "scanCountMonth") == month ? defaults.integer(forKey: "scanCount") + 1 : 1
        defaults.set(month, forKey: "scanCountMonth")
        defaults.set(count, forKey: "scanCount")
        return count
    }
}

/// Used until the scanner server is deployed.
struct UnavailableBoardReader: BoardReader {
    func read(_ image: UIImage) async throws -> BoardReading {
        throw BoardReaderError.notSetUp
    }
}

extension UIImage {
    /// A JPEG small enough to send quickly but sharp enough to read every square.
    func preparedForReading(maxSide: CGFloat = 1568) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

extension Duration {
    /// The duration in seconds, as a decimal.
    var inSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
