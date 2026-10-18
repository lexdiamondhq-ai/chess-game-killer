import SwiftUI

/// Colors for the board. Kept in one place so new themes are easy to add.
struct BoardTheme {
    let light: Color
    let dark: Color
    /// Tint over the selected piece's square.
    let selected: Color
    /// Tint over the two squares of the last move.
    let lastMove: Color
    /// Dots and rings that mark legal moves.
    let hint: Color
    /// Glow under a king in check.
    let check: Color

    /// Warm walnut and cream, tuned for contrast with the black and white pieces.
    static let walnut = BoardTheme(
        light: Color(red: 0.941, green: 0.851, blue: 0.710),  // #F0D9B5
        dark: Color(red: 0.710, green: 0.533, blue: 0.388),   // #B58863
        selected: Color(red: 0.42, green: 0.62, blue: 0.20).opacity(0.55),
        lastMove: Color(red: 0.80, green: 0.82, blue: 0.24).opacity(0.45),
        hint: Color.black.opacity(0.20),
        check: Color(red: 0.90, green: 0.10, blue: 0.10)
    )
}
