import Foundation

/// Rivals' names in sentences, for the app and the widget alike.
extension String {
    /// Whether this is a crowd's former name, from before the rivals had faces: "The 1600s",
    /// "The Masters". A crowd is many players, so it takes a plural verb ("The 1600s win"), where
    /// "The Berserker wins" and "Your Grudge wins".
    var namesACrowd: Bool { hasPrefix("The ") && hasSuffix("s") }

    /// The verb that agrees with this rival's name: `"The Berserker".agreeing("wins", "win")` is "wins".
    func agreeing(_ singular: String, _ plural: String) -> String {
        namesACrowd ? plural : singular
    }

    /// A rival's name inside a sentence: "the Berserker", "the Ashen King", "your Grudge".
    var midSentence: String {
        guard hasPrefix("The ") || hasPrefix("Your ") else { return self }
        return prefix(1).lowercased() + dropFirst()
    }
}
