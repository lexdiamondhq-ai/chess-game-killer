import SwiftUI

/// Colors for the board. Kept in one place so new themes are easy to add.
struct BoardTheme {
    let light: Color
    let dark: Color
    let frame: Color

    /// Warm walnut and cream, tuned for contrast with the black and white pieces.
    static let walnut = BoardTheme(
        light: Color(red: 0.941, green: 0.851, blue: 0.710),  // #F0D9B5
        dark: Color(red: 0.710, green: 0.533, blue: 0.388),   // #B58863
        frame: Color(red: 0.24, green: 0.17, blue: 0.12)
    )
}
