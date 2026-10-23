import Foundation

/// The links and codes of Challenge a friend, as play/PROTOCOL.md names them: the invite link
/// `https://play.chess-game-killer.workers.dev/c/7KQ2XM`, the app's own `chessgamekiller://c/7KQ2XM`
/// (or `chessgamekiller://challenge/7KQ2XM`), and a bare code typed in, in any case, with or without a space.
enum ChallengeLink {
    /// The game server.
    static let serverURL = URL(string: "https://play.chess-game-killer.workers.dev")!
    static let host = "play.chess-game-killer.workers.dev"
    /// The app's own link scheme, registered in Support/ChessGameKiller-Info.plist.
    static let scheme = "chessgamekiller"
    static let codeLength = 6
    /// No 0 or O, no 1, I or L: a code read aloud or copied by hand can't be misread.
    static let alphabet = Set("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    /// "7kq 2xm" or "7KQ-2XM" → "7KQ2XM". Nil unless six characters of the alphabet are left
    /// once spaces and dashes are gone.
    static func normalize(_ text: String) -> String? {
        let cleaned = text.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == codeLength, cleaned.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return cleaned
    }

    /// The code in an invite link or in one of the app's own links; nil for any other link.
    static func code(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch scheme {
        case "https", "http":
            guard url.host?.lowercased() == host, parts.count == 2, parts[0].lowercased() == "c" else { return nil }
            return normalize(parts[1])
        case self.scheme:
            // chessgamekiller://c/CODE: "c" stands where a host would, and the code is the path.
            if let first = url.host?.lowercased(), !first.isEmpty {
                guard first == "c" || first == "challenge", parts.count == 1 else { return nil }
                return normalize(parts[0])
            }
            // chessgamekiller:///c/CODE and chessgamekiller:c/CODE
            let path = parts.isEmpty ? url.absoluteString.dropFirst(scheme.count + 1).split(separator: "/").map(String.init) : parts
            guard path.count == 2, ["c", "challenge"].contains(path[0].lowercased()) else { return nil }
            return normalize(path[1])
        default:
            return nil
        }
    }

    /// A code typed or pasted in: a bare code, an invite link, or a whole invite message with the link in it.
    static func code(fromText text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bare = normalize(trimmed) { return bare }
        for word in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            var candidate = String(word).trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]\"'.,;!?"))
            if candidate.lowercased().hasPrefix(host) { candidate = "https://" + candidate }
            if let url = URL(string: candidate), let found = code(from: url) { return found }
        }
        return nil
    }

    /// The link to send: `https://play.chess-game-killer.workers.dev/c/7KQ2XM`.
    static func inviteURL(for code: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/c/\(code)"
        return components.url ?? serverURL
    }

    /// The app's own link: `chessgamekiller://c/7KQ2XM`.
    static func appURL(for code: String) -> URL {
        URL(string: "\(scheme)://c/\(code)") ?? inviteURL(for: code)
    }

    /// "7KQ 2XM": easier to read out and to type.
    static func spaced(_ code: String) -> String {
        guard code.count == codeLength else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }
}
