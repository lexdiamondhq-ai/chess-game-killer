import ChessKit
import SwiftUI

/// Your army on the Aurora home (Alex's pick, 2026-11-12: "A and C together"). The champion, your
/// most experienced piece, stands big on a stone base with its name carved in Cinzel (gold once
/// it is a Legend), its rank, how close the next rank is and what it has done. Under it, the
/// army's job for today: free a piece a rival holds, or help one piece to its next rank, with a
/// button that plays that rival. The other pieces line up small at the foot. Nothing glows
/// (Alex, 2026-11-11). A tap anywhere else opens the army.
struct HomeAuroraArmy: View {
    let army: ArmyStore
    let color: Piece.Color
    let pieceTheme: BoardTheme
    /// The rival up next, for a quest that only needs a win.
    let nextRival: MatchController.Level
    let palette: HomeAuroraPalette
    let open: () -> Void
    let play: (MatchController.Level) -> Void

    static let nameFont = "Cinzel-Bold"

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let champion: ArmySlot? = army.champion
        let quest: ArmyQuest? = ArmyQuest.of(army, next: nextRival)
        // Not one big button: the quest's own button sits inside it, and a button inside a
        // button's label is not reliable. A tap anywhere else opens the army.
        VStack(alignment: .leading, spacing: 14) {
            if let champion {
                hero(champion)
            } else {
                Text("Sixteen pieces, each remembers its games. Play a rival and they start earning names.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let quest {
                questRow(quest)
            }
            formation(champion: champion)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(palette.card))
        .overlay(shape.strokeBorder(palette.line, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture(perform: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your army")
        .accessibilityValue(spoken(champion: champion, quest: quest))
        .accessibilityHint("Opens your army")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(perform: open)
        .accessibilityActions {
            if let quest {
                Button(quest.button(army)) { play(quest.rival) }
            }
        }
    }

    // MARK: The champion

    private func hero(_ slot: ArmySlot) -> some View {
        let record = army.record(for: slot)
        let piece = Piece(slot.kind, color: color, square: slot.square(for: color))
        let legend: Bool = record.rank == .legend
        return HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .bottom) {
                // The stone base it stands on.
                Ellipse()
                    .fill(LinearGradient(colors: [Color(hex: 0x6A5D51), Color(hex: 0x2E2621)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Ellipse().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
                    .frame(width: 78, height: 16)
                    .shadow(color: palette.shadow, radius: 5, y: 4)
                PieceImage(piece: piece, theme: pieceTheme, size: 72, heirloom: army.heirloom(for: slot))
                    .modifier(VeteranAura(rank: record.rank, piece: piece, theme: pieceTheme, size: 72, onBoard: false))
                    .frame(width: 72, height: 72)
                    .padding(.bottom, 7)
            }
            .frame(width: 84, height: 88)
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR CHAMPION")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(palette.gold)
                Text(record.name ?? slot.title)
                    .font(.custom(Self.nameFont, size: record.name == nil ? 18 : 24))
                    .foregroundStyle(legend ? palette.gold : palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(record.name == nil ? record.rank.title.uppercased()
                                        : "\(record.rank.title.uppercased()) · \(slot.title.uppercased())")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(palette.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                rankBar(slot, record: record)
                Text(army.deeds(of: slot).joined(separator: " · "))
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// A fine gold line filled as far as the piece has come toward its next rank.
    private func rankBar(_ slot: ArmySlot, record: PieceRecord) -> some View {
        let progress: Double = army.rankProgress(of: slot)
        let words: String
        if let next = record.rank.next {
            words = "\(next.threshold - record.xp) XP to \(next.title)"
        } else {
            words = "\(record.xp) XP"
        }
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.line)
                    Capsule()
                        .fill(LinearGradient(colors: [palette.gold.opacity(0.45), palette.gold],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(3, geo.size.width * progress))
                }
            }
            .frame(height: 3)
            Text(words)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(palette.ink2)
        }
        .padding(.vertical, 2)
    }

    // MARK: The quest

    private func questRow(_ quest: ArmyQuest) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Capsule()
                .fill(LinearGradient(colors: [palette.gold, palette.gold.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
                .padding(.vertical, 2)
            Text(quest.line(army))
                .font(.system(size: 13.5))
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                play(quest.rival)
            } label: {
                HStack(spacing: 6) {
                    Text(quest.button(army))
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Color(hex: 0x2A1E0F))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(HomeAuroraPalette.goldButton))
                .contentShape(Capsule().inset(by: -6))
            }
            .buttonStyle(HomeStagePress())
            .fixedSize()
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.gold.opacity(palette.dark ? 0.07 : 0.08)))
    }

    // MARK: The rest of the army

    /// Pawns in front, the pieces behind them, as they start. The champion's own place stands
    /// faint (it is up above), a piece a rival holds is an empty dashed ring, and a fine gold
    /// line sits under each Veteran and up, longer under a Legend.
    private func formation(champion: ArmySlot?) -> some View {
        let pawns: [ArmySlot] = ArmySlot.allCases.filter(\.isPawn)
        let pieces: [ArmySlot] = ArmySlot.allCases.filter { !$0.isPawn }
        return VStack(spacing: 4) {
            row(pawns, size: 20, champion: champion)
            row(pieces, size: 25, champion: champion)
        }
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func row(_ slots: [ArmySlot], size: CGFloat, champion: ArmySlot?) -> some View {
        HStack(spacing: 0) {
            ForEach(slots) { slot in
                soldier(slot, size: size, champion: slot == champion)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func soldier(_ slot: ArmySlot, size: CGFloat, champion: Bool) -> some View {
        let rank: ArmyRank = army.record(for: slot).rank
        if army.captor(of: slot) != nil {
            Circle()
                .strokeBorder(palette.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                .frame(width: size * 0.7, height: size * 0.7)
                .frame(width: size, height: size)
        } else {
            let piece = Piece(slot.kind, color: color, square: slot.square(for: color))
            PieceImage(piece: piece, theme: pieceTheme, size: size)
                .frame(width: size, height: size)
                .overlay(alignment: .bottom) {
                    if rank >= .veteran {
                        Capsule()
                            .fill(palette.gold.opacity(rank == .legend ? 1 : 0.7))
                            .frame(width: size * (rank == .legend ? 0.55 : 0.32), height: 1.5)
                            .offset(y: 3)
                    }
                }
                .opacity(champion ? 0.28 : 1)
        }
    }

    // MARK: VoiceOver

    private func spoken(champion: ArmySlot?, quest: ArmyQuest?) -> String {
        var parts: [String] = []
        if let champion {
            let record = army.record(for: champion)
            parts.append("Champion \(army.displayName(of: champion)), \(record.rank.title)")
            parts.append(contentsOf: army.deeds(of: champion))
        }
        if let quest { parts.append(quest.line(army)) }
        return parts.joined(separator: ". ")
    }
}
