import SwiftUI

/// What the Trophy Hall shows, read from the player's own games and training: the rivals beaten,
/// the best wins and the records. Kept apart from the view so tests can check it.
struct TrophyHallRecords: Equatable {
    struct Win: Equatable, Identifiable {
        let id: UUID
        let opponent: String
        let date: Date
        let accuracy: Int?
        let moves: Int
    }

    struct RivalTrophy: Equatable, Identifiable {
        let level: MatchController.Level
        let beaten: Bool
        var id: Int { level.rawValue }
    }

    /// The five rivals, in ladder order, and whether each is beaten.
    var rivals: [RivalTrophy]
    /// Up to three wins: against the strongest rival first, the cleanest game first after that.
    var bestWins: [Win]
    var wins: Int
    var bestAccuracy: Int?
    /// The most wins in a row.
    var longestRun: Int

    init(games: [SavedGame], ladder: RivalLadder) {
        rivals = MatchController.Level.allCases.map { RivalTrophy(level: $0, beaten: ladder.beaten($0.rival)) }
        // Only games played in the app against a rival: not friends' games, not imported ones.
        let own = games.filter { $0.level != nil && !$0.isImported }.sorted { $0.date < $1.date }
        let won = own.filter { $0.result == .win }
        wins = won.count
        bestAccuracy = won.compactMap(\.accuracy).max()
        var run = 0
        var best = 0
        for game in own where game.result != .unfinished {
            run = game.result == .win ? run + 1 : 0
            best = max(best, run)
        }
        longestRun = best
        bestWins = won
            .sorted { a, b in
                if (a.level ?? 0) != (b.level ?? 0) { return (a.level ?? 0) > (b.level ?? 0) }
                return (a.accuracy ?? 0) > (b.accuracy ?? 0)
            }
            .prefix(3)
            // The rival's name as it is today: a win saved as "The 1600s" hangs here as the Berserker's.
            .map { Win(id: $0.id, opponent: $0.opponentShown, date: $0.date, accuracy: $0.accuracy, moves: $0.moveCount) }
    }
}

/// The Trophy Hall (Alex's pick, 2026-11-14): a shelf with every rival, lit gold once beaten,
/// the best wins, and the records.
struct TrophyHallView: View {
    let theme: BoardTheme
    @Environment(GameVault.self) private var vault: GameVault?
    @Environment(PuzzleStore.self) private var puzzles: PuzzleStore?

    private var records: TrophyHallRecords {
        TrophyHallRecords(games: vault?.games ?? [], ladder: RivalLadder())
    }

    var body: some View {
        let records = records
        ScrollView {
            VStack(spacing: 14) {
                Text("Every rival you beat stands here in gold.")
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(CastleStyle.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                shelf(records)
                CastleSectionTitle(text: "Best wins")
                bestWins(records)
                CastleSectionTitle(text: "Records")
                recordGrid(records)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: The rivals' shelf

    private func shelf(_ records: TrophyHallRecords) -> some View {
        let beaten = records.rivals.filter { $0.beaten }.count
        return CastleCard(padding: 14) {
            VStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(records.rivals) { entry in
                        trophy(entry.level.rival, beaten: entry.beaten)
                    }
                }
                // The shelf itself.
                Capsule()
                    .fill(LinearGradient(colors: [CastleStyle.gold.opacity(0.7), CastleStyle.gold.opacity(0.15)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 2)
                Text(beaten == 0 ? "Beat the Cub to place your first trophy."
                     : beaten == records.rivals.count ? "All five rivals beaten. The hall is full."
                     : "\(beaten) of \(records.rivals.count) rivals beaten")
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(beaten == 0 ? CastleStyle.ink2 : CastleStyle.gold)
            }
        }
    }

    private func trophy(_ rival: Rival, beaten: Bool) -> some View {
        let size: CGFloat = 40 + 4 * CGFloat(rival.level.rawValue)
        return VStack(spacing: 5) {
            RivalCoin(rival: rival, size: size)
                .saturation(beaten ? 1 : 0)
                .brightness(beaten ? 0 : -0.35)
                .padding(3)
                .overlay {
                    if beaten {
                        Circle()
                            .strokeBorder(CastleStyle.gold, lineWidth: 1.5)
                            .shadow(color: CastleStyle.gold.opacity(0.6), radius: 6)
                    }
                }
            Text(rival.shortName)
                .font(.app(.caption2, weight: .semibold))
                .foregroundStyle(beaten ? CastleStyle.ink : CastleStyle.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rival.name)
        .accessibilityValue(beaten ? "Beaten" : "Not beaten yet")
    }

    // MARK: Best wins

    @ViewBuilder
    private func bestWins(_ records: TrophyHallRecords) -> some View {
        if records.bestWins.isEmpty {
            CastleCard {
                Text("Your best wins will hang here.")
                    .font(.app(.subheadline))
                    .foregroundStyle(CastleStyle.ink2)
            }
        } else {
            CastleCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(records.bestWins.enumerated()), id: \.element.id) { index, win in
                        winRow(win, place: index)
                        if index < records.bestWins.count - 1 {
                            Rectangle().fill(CastleStyle.edge).frame(height: 0.5).padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    private func winRow(_ win: TrophyHallRecords.Win, place: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: place == 0 ? "trophy.fill" : "medal.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(place == 0 ? CastleStyle.gold : CastleStyle.ink2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Beat \(win.opponent)")
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(CastleStyle.ink)
                    .lineLimit(1)
                Text("\(win.date.formatted(.dateTime.month(.abbreviated).day().year())) · \(win.moves) moves")
                    .font(.app(.caption))
                    .foregroundStyle(CastleStyle.ink2)
            }
            Spacer(minLength: 8)
            if let accuracy = win.accuracy {
                Text("\(accuracy)%")
                    .font(.app(.headline).monospacedDigit())
                    .foregroundStyle(CastleStyle.gold)
                    .accessibilityLabel("\(accuracy) percent accuracy")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Records

    private struct RecordTile {
        let symbol: String
        let value: String
        let label: String
    }

    private func recordGrid(_ records: TrophyHallRecords) -> some View {
        let endgames = EndgameProgress.shared
        let tiles: [RecordTile] = [
            RecordTile(symbol: "crown.fill", value: "\(records.wins)", label: records.wins == 1 ? "Win" : "Wins"),
            RecordTile(symbol: "flame.fill", value: "\(records.longestRun)", label: "Wins in a row"),
            RecordTile(symbol: "scope", value: records.bestAccuracy.map { "\($0)%" } ?? "–", label: "Best accuracy"),
            RecordTile(symbol: "puzzlepiece.fill", value: "\(puzzles?.progress.highestRating ?? 0)", label: "Best puzzle rating"),
            RecordTile(symbol: "flag.checkered", value: "\(endgames.records.count)", label: "Endgames learned"),
            RecordTile(symbol: "lock.open.fill", value: "\(DungeonCells.escapedCount())", label: "Dungeon escapes"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
                                   GridItem(.flexible())], spacing: 10) {
            ForEach(tiles, id: \.label) { tile in
                CastleCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: tile.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CastleStyle.gold)
                        Text(tile.value)
                            .font(.app(.title3, weight: .bold).monospacedDigit())
                            .foregroundStyle(CastleStyle.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(tile.label)
                            .font(.app(.caption2, weight: .medium))
                            .foregroundStyle(CastleStyle.ink2)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
