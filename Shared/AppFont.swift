import SwiftUI

/// The app's typeface: Geist, in every screen and the widget.
///
/// The four weights ship in Shared/Fonts (SIL Open Font License, see Geist-OFL.txt) and are
/// listed under UIAppFonts in project.yml for the app and the widget. Each weight is picked by
/// its own file, so a weight never depends on the system faking one. Text styles keep their
/// Dynamic Type scaling through `relativeTo:`. If a file ever fails to load, iOS draws SF Pro.
enum AppFont {
    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return "Geist-Regular"
        case .medium: return "Geist-Medium"
        case .semibold: return "Geist-SemiBold"
        default: return "Geist-Bold"
        }
    }

    /// The point size iOS gives each text style at the default reading size.
    static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        default: return 17
        }
    }
}

extension Font {
    /// A text style in Geist. Headline is semibold like the system's; the rest are regular.
    static func app(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let weight = weight ?? (style == .headline ? .semibold : .regular)
        return .custom(AppFont.name(for: weight), size: AppFont.size(for: style), relativeTo: style)
    }

    /// A fixed size in Geist, for numbers and labels drawn to fit a shape.
    static func app(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.name(for: weight), fixedSize: size)
    }
}
