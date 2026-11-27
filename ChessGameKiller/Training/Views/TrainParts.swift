import ChessKit
import SwiftUI

// The building blocks of the Train screens: the doors on the hub, the rows on each
// door's own screen, and the screen around them. All drawn on the training glass.

/// The six ways into training from the hub.
enum TrainDoor: String, CaseIterable, Identifiable, Hashable {
    case puzzles, lessons, openings, endgames, calculation, games

    var id: String { rawValue }

    var title: String {
        switch self {
        case .puzzles: return "Puzzles"
        case .lessons: return "Lessons"
        case .openings: return "Openings"
        case .endgames: return "Endgames"
        case .calculation: return "Calculation"
        case .games: return "Chess DNA"
        }
    }

    /// A chess glyph where the app has one, otherwise an SF Symbol of the same weight.
    var symbol: String {
        switch self {
        case .puzzles: return Glyphs.puzzles
        case .lessons: return Glyphs.train
        case .openings: return "book.closed.fill"
        case .endgames: return "flag.checkered"
        case .calculation: return "brain.head.profile"
        case .games: return Glyphs.games
        }
    }

    /// The door's own stone. Puzzles and Lessons wear the stones they wear on Home's tiles.
    var stone: HomeAuroraJewel.Stone {
        switch self {
        case .puzzles: return .amethyst
        case .lessons: return .jade
        case .openings: return .sapphire
        case .endgames: return .ruby
        case .calculation: return .violet
        case .games: return .amber
        }
    }
}

/// A square of color behind an icon, in the accent: lit from above, with a fine rim, so it
/// reads as a small enamel plate and not a flat patch.
struct TrainIcon: View {
    let symbol: String
    let theme: BoardTheme
    var size: CGFloat = 44
    var tint: Color?

    var body: some View {
        let color = tint ?? theme.trainingAccent
        let tile = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Glyph(name: symbol, size: size * (Glyph.isGlyph(symbol) ? 0.62 : 0.56), weight: .semibold)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background {
                tile.fill(LinearGradient(colors: [color.opacity(0.24), color.opacity(0.1)],
                                         startPoint: .top, endPoint: .bottom))
            }
            .overlay {
                tile.strokeBorder(LinearGradient(colors: [color.opacity(0.5), color.opacity(0.2)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 0.8)
            }
            .accessibilityHidden(true)
    }
}

/// A small count, like "3" reviews due.
struct TrainBadge: View {
    let count: Int
    let theme: BoardTheme

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.app(.caption, weight: .bold).monospacedDigit())
            .foregroundStyle(Color.black)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(theme.trainingAccent, in: Capsule())
            .accessibilityHidden(true)
    }
}

/// One door on the hub: an icon, a name and one line of where the player stands.
struct DoorTile: View {
    let door: TrainDoor
    let status: String
    var badge = 0
    let theme: BoardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                JewelIcon(symbol: door.symbol, stone: door.stone, size: 44)
                Spacer(minLength: 0)
                if badge > 0 {
                    TrainBadge(count: badge, theme: theme)
                }
            }
            Spacer(minLength: 12)
            Text(door.title)
                .font(.display(.title3, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(status)
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .trainingCard(theme)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(door.title). \(status)\(badge > 0 ? ". \(badge) due" : "")")
        .accessibilityAddTraits(.isButton)
    }
}

/// A row on a door's screen: what it is, one line on why it helps, and where the player stands.
struct TrainRow: View {
    let symbol: String
    let title: String
    let detail: String
    var value: String?
    var badge = 0
    var tint: Color?
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 14) {
            TrainIcon(symbol: symbol, theme: theme, size: 44, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.display(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .font(.app(.subheadline, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if badge > 0 {
                TrainBadge(count: badge, theme: theme)
            }
            Image(systemName: "chevron.right")
                .font(.app(.caption, weight: .bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .trainingCard(theme)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A heading above a group of rows: carved gold capitals and a fine rule (`SectionLabel`).
struct TrainSectionTitle: View {
    let text: String

    var body: some View {
        SectionLabel(text: text)
            .padding(.horizontal, 4)
            .padding(.top, 12)
            .padding(.bottom, 1)
    }
}

/// A door's own screen: a large title over the board's backdrop, one short line on
/// what's here, then the rows.
struct TrainScreen<Content: View>: View {
    let theme: BoardTheme
    let title: String
    var intro: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let intro {
                    Text(intro)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
                content()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { TrainingBackdrop(theme: theme) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

/// The streak, as a flame and a number.
struct StreakPill: View {
    let streak: Int
    let theme: BoardTheme

    var body: some View {
        let color = TrainingColor.orange.color(on: theme)
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(streak > 0 ? color : Color.secondary.opacity(0.6))
                .symbolEffect(.bounce, value: streak)
            Text("\(streak)")
                .font(.app(.headline).monospacedDigit())
            Text(streak == 1 ? "day" : "days")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassPane(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training streak: \(streak) \(streak == 1 ? "day" : "days")")
    }
}
