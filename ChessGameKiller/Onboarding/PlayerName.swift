import Foundation

/// The player's name, asked on the welcome and kept in Settings. It is the same name friends see
/// on a challenge (`ChallengeName`), so it is asked once. The home's hello and the coach's written
/// lines use it ("Welcome back, Alex."). Recorded lines are never changed, since the recording
/// can't say it; Talk It Through sends it so Leo can use it in his own words.
enum PlayerName {
    static let key = ChallengeName.key
    static let maxLength = ChallengeName.maxLength

    /// The saved name, tidied, or nil when there is none.
    static func current(_ defaults: UserDefaults = .standard) -> String? {
        clean(defaults.string(forKey: key) ?? "")
    }

    static func save(_ text: String, _ defaults: UserDefaults = .standard) {
        if let name = clean(text) {
            defaults.set(name, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Cleaned as a challenge cleans it; nil when nothing is left.
    static func clean(_ text: String) -> String? {
        let name = ChallengeName.clean(text)
        return name.isEmpty ? nil : name
    }

    /// Openings that take the name straight after them: "Welcome back." becomes "Welcome back, Alex."
    private static let openers = [
        "Good morning", "Good afternoon", "Good evening", "Good to see you", "Welcome back",
        "Hello again", "Hello", "Ready when you are", "Talk me through your plan", "Nicely done"
    ]

    /// A written line spoken to the player by name, when it opens with a greeting that takes one.
    /// Lines that don't are returned as they are.
    static func address(_ line: String, name: String?) -> String {
        guard let name = name.flatMap(clean) else { return line }
        for opener in openers where line.hasPrefix(opener) {
            let rest = line.dropFirst(opener.count)
            // Only a whole opener: "Hello" must not match "Hellow".
            guard rest.isEmpty || rest.first.map({ ".!?,".contains($0) }) == true else { continue }
            if rest.first == "," { return line }
            return opener + ", " + name + rest
        }
        return line
    }

    /// Whether `address` would put the name in this line.
    static func takesName(_ line: String) -> Bool {
        address(line, name: "A") != line
    }

    /// One of `lines`, preferring those that can carry the name when there is one.
    static func pick(_ lines: [String], name: String?) -> String? {
        guard name != nil else { return lines.randomElement() }
        let named = lines.filter(takesName)
        return (named.isEmpty ? lines : named).randomElement().map { address($0, name: name) }
    }
}
