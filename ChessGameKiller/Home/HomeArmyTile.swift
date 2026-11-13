import ChessKit
import SwiftUI

/// Your army on Today (it used to have a tab of its own): all sixteen pieces lined up as
/// they start, pawns in front, each marked by how far it has come (a gold line under a Veteran,
/// a longer brighter one under a Legend; nothing glows), with the army's hero named above them. A tap opens the army.
struct HomeArmyTile: View {
    let army: ArmyStore
    /// The side the player last took: the army wears its color.
    let color: Piece.Color
    let pieceTheme: BoardTheme
    let tone: HomeTone
    let open: () -> Void

    @ScaledMetric(relativeTo: .body) private var pieceSize: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your army")
                            .font(.app(.headline))
                            .foregroundStyle(tone.ink)
                        Text(line)
                            .font(.app(.footnote))
                            .foregroundStyle(tone.ink2)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.app(.footnote, weight: .semibold))
                        .foregroundStyle(tone.ink3)
                }
                formation
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .bottomLeading) {
                HomeTileGlow(color: tone.metal, strength: litCount > 0 ? 0.26 : 0.14)
                    .offset(x: -60, y: 70)
            }
            .clipShape(shape)
            .homePane(shape, tone: tone)
            .contentShape(shape)
        }
        .buttonStyle(HomeLiftStyle(tone: tone))
        .homeZoomSource(.army)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your army")
        .accessibilityValue(line)
        .accessibilityHint("Your pieces and what each has done")
        .accessibilityAddTraits(.isButton)
    }

    /// Pawns in front, the pieces behind them, as they stand at the start.
    private var formation: some View {
        let size: CGFloat = min(pieceSize, 40)
        let pawns: [ArmySlot] = ArmySlot.allCases.filter(\.isPawn)
        let pieces: [ArmySlot] = ArmySlot.allCases.filter { !$0.isPawn }
        return VStack(spacing: 4) {
            row(pawns, size: size * 0.8)
            row(pieces, size: size)
        }
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func row(_ slots: [ArmySlot], size: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(slots) { slot in
                soldier(slot, size: size)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func soldier(_ slot: ArmySlot, size: CGFloat) -> some View {
        let rank: ArmyRank = army.record(for: slot).rank
        let strength: Double
        switch rank {
        case .recruit: strength = 0
        case .veteran: strength = 0.35
        case .elite: strength = 0.6
        case .legend: strength = 0.95
        }
        let piece = Piece(slot.kind, color: color, square: slot.square(for: color))
        // Fitted into its frame rather than standing on a square, so the two rows don't overlap.
        return PieceImage(piece: piece, theme: pieceTheme, size: size)
            .frame(width: size, height: size)
            .overlay(alignment: .bottom) {
                if rank >= .veteran {
                    Capsule()
                        .fill(tone.metal.opacity(0.4 + strength * 0.6))
                        .frame(width: size * (rank == .legend ? 0.5 : 0.3), height: 2)
                        .offset(y: 3)
                }
            }
            .opacity(rank == .recruit && litCount > 0 ? 0.78 : 1)
    }

    private var litCount: Int {
        ArmySlot.allCases.filter { army.record(for: $0).rank >= .veteran }.count
    }

    /// The army's hero, or what the army is before its first game.
    private var line: String {
        guard let hero = army.hero else { return "Sixteen pieces, each remembers its games" }
        let games: Int = army.gamesPlayed
        let together: String = games == 1 ? "1 game together" : "\(games) games together"
        if hero.rank == .recruit { return "\(hero.name) leads · \(together)" }
        return "\(hero.name), \(hero.rank.title) · \(together)"
    }
}
