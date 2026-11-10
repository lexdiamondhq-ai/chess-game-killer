import Foundation

/// Where a deep review comes from: the coach's server, or a stand-in for tests and pictures.
protocol DeepReviewTransport: Sendable {
    func review(_ request: DeepReviewRequest) -> AsyncThrowingStream<DeepReviewEvent, Error>
}

/// The coach's server over HTTPS, as coach/PROTOCOL.md describes it: one POST /review, then
/// NDJSON lines (review, a voice line per part, done) passed on as they arrive. Failures are
/// Talk's own (`TalkFailure`): the server is the same one.
struct DeepReviewAPI: DeepReviewTransport {
    static let live = DeepReviewAPI(baseURL: TalkAPI.live.baseURL)

    typealias Events = AsyncThrowingStream<DeepReviewEvent, Error>

    let baseURL: URL
    let session: URLSession
    /// The whole review, from sending to the last line. Past it the stream ends with "timeout".
    let timeout: Duration

    /// Claude takes about fifteen seconds to write a review and may take forty-five; then the voice.
    init(baseURL: URL, session: URLSession = .shared, timeout: Duration = .seconds(100)) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func review(_ request: DeepReviewRequest) -> AsyncThrowingStream<DeepReviewEvent, Error> {
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
                    try await DeepReviewAPI.stream(urlRequest, session: session, to: continuation)
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
            // The listener went away (the screen closed): stop the request.
            continuation.onTermination = { _ in
                worker.cancel()
                timer.cancel()
            }
        }
    }

    /// POST /review with the game as JSON. Optionals that are nil are left out.
    func makeRequest(_ review: DeepReviewRequest) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "review"))
        request.httpMethod = "POST"
        // Nothing arrives while Claude writes, so the wait between bytes is the long one.
        request.timeoutInterval = 70
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(review)
        return request
    }

    private static func stream(_ request: URLRequest, session: URLSession,
                               to continuation: Events.Continuation) async throws {
        let result: (URLSession.AsyncBytes, URLResponse)
        do {
            result = try await session.bytes(for: request)
        } catch {
            throw TalkAPI.failure(for: error)
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
            throw TalkAPI.failure(status: http.statusCode, body: Data(body))
        }
        try await relay(bytes, to: continuation)
    }

    /// Passes on each line's event as it arrives, until `done` or an error line. A line this app
    /// can't read, or doesn't know, is skipped rather than sinking the whole review.
    static func relay<Bytes: AsyncSequence>(_ bytes: Bytes, to continuation: Events.Continuation) async throws
        where Bytes.Element == UInt8 {
        var line: [UInt8] = []
        for try await byte in bytes {
            if byte == 0x0A {
                if deliver(line, to: continuation) { return }
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(byte)
                if line.count > TalkAPI.longestLine { throw TalkFailure.badResponse }
            }
        }
        _ = deliver(line, to: continuation)
    }

    /// Sends one line's event on. True when the line ends the stream.
    private static func deliver(_ line: [UInt8], to continuation: Events.Continuation) -> Bool {
        guard !line.isEmpty else { return false }
        let text = String(decoding: line, as: UTF8.self)
        guard let event = try? DeepReviewEvent.decode(line: text) else { return false }
        continuation.yield(event)
        switch event {
        case .done, .failed:
            return true
        case .review, .voice:
            return false
        }
    }
}
