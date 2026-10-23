import Foundation

/// Why a talk with Leo's server didn't work.
enum TalkFailure: Error, Equatable, Sendable {
    /// The server couldn't be reached.
    case offline
    /// The server's own error code, like "rate_limited", or "http_502" when it gave none.
    case server(String)
    /// A reply the app couldn't read.
    case badResponse
}

/// Leo's server over HTTPS, as coach/PROTOCOL.md describes it: one POST, then the answer as
/// NDJSON lines (checked, answer, voice, done) passed on as they arrive.
struct TalkAPI: TalkTransport {
    static let live = TalkAPI(baseURL: URL(string: "https://coach.chess-game-killer.workers.dev")!)

    typealias Events = AsyncThrowingStream<TalkEvent, Error>

    let baseURL: URL
    let session: URLSession
    /// The whole talk, from sending to the last line. Past it the stream ends with "timeout".
    let timeout: Duration

    /// Leo's voice comes as one base64 line; anything far longer isn't a reply from Leo.
    static let longestLine = 8_000_000

    init(baseURL: URL, session: URLSession = .shared, timeout: Duration = .seconds(35)) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func talk(_ request: TalkRequest) -> AsyncThrowingStream<TalkEvent, Error> {
        let urlRequest: URLRequest
        do {
            urlRequest = try makeRequest(request)
        } catch {
            return Events { continuation in
                continuation.finish(throwing: TalkFailure.badResponse)
            }
        }
        let session = self.session
        let timeout = self.timeout
        return Events { continuation in
            let worker = Task {
                do {
                    try await TalkAPI.stream(urlRequest, session: session, to: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: TalkAPI.failure(for: error))
                }
            }
            let timer = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                continuation.finish(throwing: TalkFailure.server("timeout"))
                worker.cancel()
            }
            // The listener went away (the panel closed, or the player started again): stop the request.
            continuation.onTermination = { _ in
                worker.cancel()
                timer.cancel()
            }
        }
    }

    /// POST /talk with the request as JSON. Optionals that are nil are left out.
    func makeRequest(_ talk: TalkRequest) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "talk"))
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(talk)
        return request
    }

    // MARK: Reading the reply

    private static func stream(_ request: URLRequest, session: URLSession,
                               to continuation: Events.Continuation) async throws {
        let result: (URLSession.AsyncBytes, URLResponse)
        do {
            result = try await session.bytes(for: request)
        } catch {
            throw failure(for: error)
        }
        let (bytes, response) = result
        guard let http = response as? HTTPURLResponse else { throw TalkFailure.badResponse }
        guard http.statusCode == 200 else {
            // Refused before the stream started: a small JSON body names the error.
            var body: [UInt8] = []
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 16_384 { break }
            }
            throw failure(status: http.statusCode, body: Data(body))
        }
        try await relay(bytes, to: continuation)
    }

    /// Passes on each line's event as it arrives, until `done` or an error line. Lines are split on
    /// newlines only (never on the Unicode line separators a sentence could hold), and a line this
    /// app can't read, or doesn't know, is skipped rather than sinking the whole answer.
    static func relay<Bytes: AsyncSequence>(_ bytes: Bytes, to continuation: Events.Continuation) async throws
        where Bytes.Element == UInt8 {
        var line: [UInt8] = []
        for try await byte in bytes {
            if byte == 0x0A {
                if deliver(line, to: continuation) { return }
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(byte)
                if line.count > longestLine { throw TalkFailure.badResponse }
            }
        }
        _ = deliver(line, to: continuation)
    }

    /// Sends one line's event on. True when the line ends the stream.
    private static func deliver(_ line: [UInt8], to continuation: Events.Continuation) -> Bool {
        guard !line.isEmpty else { return false }
        let text = String(decoding: line, as: UTF8.self)
        guard let event = try? TalkEvent.decode(line: text) else { return false }
        continuation.yield(event)
        switch event {
        case .done, .failed:
            return true
        case .checked, .answer, .voice:
            return false
        }
    }

    // MARK: Errors

    private struct ErrorReply: Decodable {
        let error: String?
    }

    /// The error for a refused request: the code the body names, or the status when it names none.
    static func failure(status: Int, body: Data) -> TalkFailure {
        if let reply = try? JSONDecoder().decode(ErrorReply.self, from: body), let code = reply.error, !code.isEmpty {
            return .server(code)
        }
        return .server("http_\(status)")
    }

    /// What the stream ends with for an error on the way: cancelling stays cancelling, a request
    /// that took too long is the server's "timeout", and any other network trouble is offline.
    static func failure(for error: Error) -> Error {
        if error is TalkFailure || error is CancellationError { return error }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return CancellationError()
            case .timedOut: return TalkFailure.server("timeout")
            default: return TalkFailure.offline
            }
        }
        return TalkFailure.offline
    }
}
