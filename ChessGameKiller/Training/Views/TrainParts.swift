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
        case .games: return "Your games"
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
}

/// A square of color behind an icon, in the accent.
struct TrainIcon: View {
    let symbol: String
    let theme: BoardTheme
    var size: CGFloat = 44
    var tint: Color?

    var body: some View {
        let color = tint ?? theme.trainingAccent
        Glyph(name: symbol, size: size * (Glyph.isGlyph(symbol) ? 0.62 : 0.56), weight: .semibold)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(color.opacity(0.22), lineWidth: 0.6)
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
            .font(.system(.caption, design: .themed).weight(.bold).monospacedDigit())
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
                TrainIcon(symbol: door.symbol, theme: theme, size: 42)
                Spacer(minLength: 0)
                if badge > 0 {
                    TrainBadge(count: badge, theme: theme)
                }
            }
            Spacer(minLength: 12)
            Text(door.title)
                .font(.system(.headline, design: .themed))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(status)
                .font(.system(.footnote, design: .themed))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 2)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
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
                    .font(.system(.headline, design: .themed))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(.subheadline, design: .themed))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if badge > 0 {
                TrainBadge(count: badge, theme: theme)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
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

/// A quiet heading above a group of rows.
struct TrainSectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .themed).weight(.semibold))
            .tracking(0.9)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .padding(.top, 10)
            .accessibilityAddTraits(.isHeader)
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
                        .font(.system(.subheadline, design: .themed))
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
                .font(.system(.headline, design: .themed).monospacedDigit())
            Text(streak == 1 ? "day" : "days")
                .font(.system(.footnote, design: .themed))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background { TrainingGlass(shape: Capsule()) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training streak: \(streak) \(streak == 1 ? "day" : "days")")
    }
}

/// The learner's rank: the piece it's named after, the XP and how far to the next.
struct RankStrip: View {
    let theme: BoardTheme
    @Environment(TrainingStore.self) private var store

    var body: some View {
        if let rank = store.rank {
            HStack(spacing: 12) {
                PieceImage(piece: Piece(rank.pieceKind, color: .white, square: .a1), theme: theme, size: 34)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(rank.title)
                            .font(.system(.subheadline, design: .themed).weight(.semibold))
                        Text("\(store.progress.xp) XP")
                            .font(.system(.caption, design: .themed).weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if let next = store.nextRank {
                            Text("Next: \(next.title)")
                                .font(.system(.caption, design: .themed))
                                .foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: store.rankProgress)
                        .tint(theme.trainingAccent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .trainingCard(theme, cornerRadius: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rank \(rank.title), \(store.progress.xp) XP" + (store.nextRank.map { ", next \($0.title)" } ?? ""))
        }
    }
}
