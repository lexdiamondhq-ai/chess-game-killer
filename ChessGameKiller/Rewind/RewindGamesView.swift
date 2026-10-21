import ChessKit
import SwiftUI

/// Your games: every game you've played, newest first, each with its line and
/// how many moments are left to rewrite. Tap one to rewind it.
struct RewindGamesView: View {
    let theme: BoardTheme
    var onPlayAgain: ((SavedGame) -> Void)?

    @Environment(GameVault.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vault.games.isEmpty {
                        empty
                    } else {
                        week
                        ForEach(vault.games) { game in
                            NavigationLink(value: game.id) {
                                GameCard(game: game, theme: theme)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation { vault.delete(game.id) }
                                } label: {
                                    Label("Delete game", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background { ThemeBackdrop(theme: theme).ignoresSafeArea() }
            .navigationTitle("Your games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let game = vault.game(id) {
                    RewindView(game: game, theme: theme) { game in
                        dismiss()
                        onPlayAgain?(game)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.accent ?? RewindPalette.gold)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "backward.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("No games yet")
                .font(.system(.title3, design: .themed).weight(.semibold))
            Text("Finish a game and it lands here. Rewind it to see the moments that mattered, then go back and fix them.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 120)
        .padding(.horizontal, 24)
    }

    private var week: some View {
        let fixed = vault.rewrittenThisWeek()
        let left = vault.leftThisWeek()
        let next = vault.games.first { $0.leftToRewrite > 0 }
        return VStack(alignment: .leading, spacing: 8) {
            Text("This week")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(RewindPalette.gold)
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                stat(fixed, "rewritten")
                stat(left, "left")
                Spacer()
                if let next {
                    Button {
                        path.append(next.id)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .tint(.primary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [RewindPalette.gold.opacity(0.10), Color.primary.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(RewindPalette.gold.opacity(0.25), lineWidth: 1)
                }
        }
        .padding(.top, 8)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(value)").font(.system(.title, design: .themed).weight(.semibold).monospacedDigit())
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// One game in the list: the final position, who it was against, and its line.
private struct GameCard: View {
    let game: SavedGame
    let theme: BoardTheme

    private var rival: Rival? { game.level.flatMap(MatchController.Level.init(rawValue:))?.rival }

    private var resultColor: Color {
        switch game.result {
        case .win: return RewindPalette.gold
        case .loss: return RewindPalette.coral
        case .draw, .unfinished: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PositionBoard(draft: PositionDraft(fen: game.finalFEN) ?? .standard, theme: theme,
                          flipped: !game.playerIsWhite)
                .frame(width: 104, height: 104)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    portrait
                    VStack(alignment: .leading, spacing: 1) {
                        Text(game.opponent)
                            .font(.system(.headline, design: .themed))
                        Text("\(game.moveCount) moves · \(game.date.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(game.result.title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(resultColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(resultColor.opacity(0.14)))
                }
                LifelineSpark(game: game, color: resultColor)
                    .frame(height: 30)
                HStack(spacing: 6) {
                    Circle().fill(footColor).frame(width: 7, height: 7)
                    Text(footText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 2) {
                        Text("Rewind")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(theme.isDark ? Color.white.opacity(0.06) : Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var portrait: some View {
        if let rival {
            Image(rival.portraitName)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.2.fill")
                .font(.footnote)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.08)))
        }
    }

    private var footText: String {
        let left = game.leftToRewrite
        if game.toRewrite.isEmpty {
            if let mate = game.playerMoments.last(where: { $0.moveGrade == .checkmate }) { return "Checkmate · \(mate.numbered)" }
            return "A clean game"
        }
        if left == 0 { return "All rewritten" }
        return left == 1 ? "1 moment to rewrite" : "\(left) moments to rewrite"
    }

    private var footColor: Color {
        game.toRewrite.isEmpty || game.leftToRewrite == 0 ? RewindPalette.gold : RewindPalette.amber
    }
}
