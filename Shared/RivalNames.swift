import Foundation

/// Rivals' names in sentences, for the app and the widget alike.
extension String {
    /// Whether this is a crowd's name: "The 1600s", "The Masters". A crowd is many players, so it
    /// takes a plural verb ("The 1600s win"), where "Your Grudge wins".
    var namesACrowd: Bool { hasPrefix("The ") }

    /// The verb that agrees with this rival's name: `"The 1600s".agreeing("wins", "win")` is "win".
    func agreeing(_ singular: String, _ plural: String) -> String {
        namesACrowd ? plural : singular
    }

    /// A rival's name inside a sentence: "the 1600s", "the Masters", "your Grudge".
    var midSentence: String {
        guard hasPrefix("The ") || hasPrefix("Your ") else { return self }
        return prefix(1).lowercased() + dropFirst()
    }
}
