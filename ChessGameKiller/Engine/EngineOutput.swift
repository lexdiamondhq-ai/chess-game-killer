import ChessKitEngine
import Foundation

/// Reads Stockfish's replies on a thread of its own, a whole line at a time.
///
/// ChessKitEngine reads them itself on the main thread's run loop, in chunks, and splits each
/// chunk at its line breaks. That loses replies: whenever the main thread is busy the output
/// piles up, a chunk then ends partway through a line, and both halves of that line (often the
/// "bestmove" that answers a "stop") are thrown away as unreadable. It also hands each line on
/// in a task of its own, so lines can arrive out of order, and it reads nothing at all while
/// the main run loop is out of its default mode (a finger dragging or scrolling).
///
/// Stockfish writes to the app's standard output, which ChessKitEngine points at its pipe.
/// Pointing it at a pipe of ours instead sends every later line here, read without the main
/// thread and passed on in order, while commands still go in through ChessKitEngine.
enum EngineOutput {
    /// Takes over Stockfish's output, from now on, and returns its replies. Nil if the
    /// pipe can't be set up; ChessKitEngine's own stream still works then.
    static func takeOver() -> AsyncStream<EngineResponse>? {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else { return nil }
        let (readEnd, writeEnd) = (ends[0], ends[1])
        // Anything already buffered goes where it was headed before the switch.
        fflush(nil)
        guard dup2(writeEnd, STDOUT_FILENO) >= 0 else {
            close(readEnd)
            close(writeEnd)
            return nil
        }
        // Standard output holds the write end now.
        close(writeEnd)

        let (stream, continuation) = AsyncStream<EngineResponse>.makeStream()
        let reader = Thread {
            var lines = LineSplitter()
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while true {
                let count = buffer.withUnsafeMutableBytes { read(readEnd, $0.baseAddress, $0.count) }
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { break }
                for line in lines.append(buffer[0..<count]) {
                    if let response = EngineResponse(rawValue: line) {
                        continuation.yield(response)
                    }
                }
            }
            close(readEnd)
            continuation.finish()
        }
        reader.name = "Stockfish output"
        reader.qualityOfService = .userInteractive
        reader.start()
        return stream
    }
}

/// Cuts a stream of bytes into lines, keeping a line that arrives in pieces until it is whole.
struct LineSplitter {
    private var partial: [UInt8] = []

    /// The lines completed by `bytes`, without their line breaks.
    mutating func append<Bytes: Sequence>(_ bytes: Bytes) -> [String] where Bytes.Element == UInt8 {
        var lines: [String] = []
        for byte in bytes {
            switch byte {
            case UInt8(ascii: "\n"):
                lines.append(String(decoding: partial, as: UTF8.self))
                partial.removeAll(keepingCapacity: true)
            case UInt8(ascii: "\r"):
                continue
            default:
                partial.append(byte)
            }
        }
        return lines
    }
}
