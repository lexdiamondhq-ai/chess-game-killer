import ChessKit
import Foundation
import UIKit

/// Turns a photo or screenshot of a chess board into a position.
protocol BoardReader: Sendable {
    func read(_ image: UIImage) async throws -> BoardReading
}

/// What a reader saw. The draft is always from White's side; `whiteSide`
/// says which way round the picture was.
struct BoardReading: Equatable {
    var draft: PositionDraft
    var whiteSide: PositionDraft.WhiteSide
    var sureOfTurn: Bool
    var confidence: Confidence

    enum Confidence: String, Decodable {
        case high, medium, low
    }
}

enum BoardReaderError: LocalizedError, Equatable {
    case notSetUp
    case noBoard
    case busy
    case failed

    var errorDescription: String? {
        switch self {
        case .notSetUp: return "Photo reading isn't switched on yet. Set up the pieces to match your photo."
        case .noBoard: return "I couldn't find a chess board in that picture. Try a straighter, closer shot."
        case .busy: return "Too many scans in a row. Wait a minute and try again."
        case .failed: return "I couldn't read that picture. Check your connection, or set up the pieces by hand."
        }
    }
}

/// Where the scanner server lives (scanner/ in this repo, on Cloudflare).
/// Empty until the server is deployed.
enum ScannerConfig {
    static let endpoint = URL(string: "")
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

    func read(_ image: UIImage) async throws -> BoardReading {
        guard let jpeg = image.preparedForReading() else { throw BoardReaderError.failed }

        var request = URLRequest(url: endpoint.appendingPathComponent("read"))
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let result: (Data, URLResponse)
        do {
            result = try await session.upload(for: request, from: jpeg)
        } catch {
            throw BoardReaderError.failed
        }
        let (data, response) = result
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429 { throw BoardReaderError.busy }
        guard status == 200 else { throw BoardReaderError.failed }
        return try Self.reading(from: data)
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
