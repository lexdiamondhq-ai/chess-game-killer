import SwiftUI

/// The app's five speeds. Most motion already sat close to one of these; the name says what
/// kind of change it is, so the same kind of change moves the same way on every screen.
enum Motion {
    /// A touch on the board answered: a piece picked up, a move taken back.
    static let tap: Animation = .snappy(duration: 0.22)
    /// Something small changes in place: a chip picked, a row opened, a line of words swapped.
    static let change: Animation = .snappy(duration: 0.3)
    /// Something arrives over the screen or leaves it: a banner, a toast, a card.
    static let panel: Animation = .spring(response: 0.42, dampingFraction: 0.86)
    /// The whole scene changes: Home to the game, one position to the next, a new look.
    static let scene: Animation = .easeInOut(duration: 0.35)
    /// A button sinking under the finger and coming back.
    static let press: Animation = .spring(response: 0.25, dampingFraction: 0.8)
}
