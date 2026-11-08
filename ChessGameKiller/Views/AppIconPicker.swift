import SwiftUI
import UIKit

/// The home screen icons you can choose in Settings. Gilded is the app's own icon;
/// the others are alternate icons in the asset catalog (AppIcon-<name>).
enum AppIconChoice: String, CaseIterable, Identifiable {
    case gilded = "Gilded"
    case guardian = "Guardian"
    case ivory = "Ivory"
    case oath = "Oath"
    case helm = "Helm"
    case warlord = "Warlord"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gilded: "Gilded"
        case .guardian: "The Guardian"
        case .ivory: "Ivory Champion"
        case .oath: "The Oath"
        case .helm: "Knight Helm"
        case .warlord: "The Warlord"
        }
    }

    /// nil sets the primary icon back.
    var alternateName: String? { self == .gilded ? nil : "AppIcon-\(rawValue)" }

    var preview: Image { Image("IconPreviews/\(rawValue)") }

    static var current: AppIconChoice {
        guard let name = UIApplication.shared.alternateIconName else { return .gilded }
        return allCases.first { $0.alternateName == name } ?? .gilded
    }
}

/// A row of icon tiles; tapping one changes the home screen icon (iOS confirms with its own alert).
struct AppIconPicker: View {
    let accent: Color

    @State private var selected = AppIconChoice.current

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(AppIconChoice.allCases) { choice in
                Button { choose(choice) } label: { tile(choice) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(choice == selected ? .isSelected : [])
            }
        }
        .padding(14)
    }

    private func tile(_ choice: AppIconChoice) -> some View {
        let isOn = choice == selected
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        return VStack(spacing: 8) {
            choice.preview
                .resizable()
                .scaledToFill()
                .frame(width: 66, height: 66)
                .clipShape(shape)
                .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 0.5) }
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent, lineWidth: isOn ? 2 : 0)
                }
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            Text(choice.title)
                .font(.app(.caption, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.2), value: isOn)
    }

    private func choose(_ choice: AppIconChoice) {
        guard choice != selected, UIApplication.shared.supportsAlternateIcons else { return }
        let previous = selected
        selected = choice
        UIApplication.shared.setAlternateIconName(choice.alternateName) { error in
            if error != nil {
                DispatchQueue.main.async { selected = previous }
            }
        }
    }
}
