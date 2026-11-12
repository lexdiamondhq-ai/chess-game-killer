import ChessKit
import SwiftUI

/// Your army at the foot of the Aurora home, as one slim strip (Alex's picks, 2026-11-12: "A and
/// C together", then "move the Army to the bottom ... more of a rectangle", then B, the slim
/// strip). The champion, your most experienced piece, stands small on its stone base beside its
/// name carved in Cinzel (gold once it is a Legend) and its rank; at the end, the gold button for
/// the army's job today (free a held piece, or help one to its next rank). Nothing glows (Alex,
/// 2026-11-11). A tap anywhere else opens the army, where the quest's words, the bars and all
/// sixteen pieces are.
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
        let champion: ArmySlot? = army.champion
        let quest: ArmyQuest? = ArmyQuest.of(army, next: nextRival)
        // Not one big button: the quest's own button sits inside it, and a button inside a
        // button's label is not reliable. A tap anywhere else opens the army.
        return asOneButton(content(champion: champion, quest: quest), champion: champion, quest: quest)
    }

    /// VoiceOver hears the card as one button that opens the army, with the quest as an action.
    private func asOneButton(_ card: some View, champion: ArmySlot?, quest: ArmyQuest?) -> some View {
        let value: String = spoken(champion: champion, quest: quest)
        let questWords: String = quest.map { $0.button(army) } ?? "Open your army"
        let questRival: MatchController.Level? = quest?.rival
        let tapped: () -> Void = open
        let played: (MatchController.Level) -> Void = play
        let questAction: () -> Void = {
            if let questRival { played(questRival) } else { tapped() }
        }
        return card
            .onTapGesture(perform: tapped)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Your army"))
            .accessibilityValue(Text(value))
            .accessibilityHint(Text("Opens your army"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, tapped)
            .accessibilityAction(named: Text(questWords), questAction)
    }

    private func content(champion: ArmySlot?, quest: ArmyQuest?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return HStack(alignment: .center, spacing: 12) {
            if let champion {
                figure(champion)
                words(champion)
            } else {
                Text("Sixteen pieces, each remembers its games. Play a rival and they start earning names.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            if let quest {
                questButton(quest)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(shape.fill(palette.card))
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.line, lineWidth: 1))
        .contentShape(shape)
    }

    // MARK: The champion

    /// The champion, standing on a small stone base.
    private func figure(_ slot: ArmySlot) -> some View {
        let rank: ArmyRank = army.record(for: slot).rank
        let piece = Piece(slot.kind, color: color, square: slot.square(for: color))
        let stone = LinearGradient(colors: [Color(hex: 0x6A5D51), Color(hex: 0x2E2621)],
                                   startPoint: .top, endPoint: .bottom)
        let base = Ellipse()
            .fill(stone)
            .frame(width: 40, height: 8)
            .shadow(color: palette.shadow, radius: 3, y: 2)
        let figure = PieceImage(piece: piece, theme: pieceTheme, size: 44, heirloom: army.heirloom(for: slot))
            .modifier(VeteranAura(rank: rank, piece: piece, theme: pieceTheme, size: 44, onBoard: false))
            .frame(width: 44, height: 44)
            .padding(.bottom, 3)
        return ZStack(alignment: .bottom) {
            base
            figure
        }
        .frame(width: 46, height: 50)
    }

    /// Its name carved in Cinzel (gold for a Legend) and, under it, its rank and the XP to
    /// the next rank.
    private func words(_ slot: ArmySlot) -> some View {
        let record: PieceRecord = army.record(for: slot)
        let named: Bool = record.name != nil
        let nameColor: Color = record.rank == .legend ? palette.gold : palette.ink
        var parts: [String] = [record.rank.title]
        if let next = record.rank.next {
            parts.append("\(next.threshold - record.xp) XP to \(next.title)")
        } else {
            parts.append("\(record.xp) XP")
        }
        let rankWords: String = parts.joined(separator: " · ").uppercased()
        return VStack(alignment: .leading, spacing: 3) {
            Text(record.name ?? slot.title)
                .font(.custom(Self.nameFont, size: named ? 19 : 16))
                .foregroundStyle(nameColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(rankWords)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(palette.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The quest

    /// The gold button that plays the quest's rival. The quest's words live in the Army screen
    /// and in VoiceOver.
    private func questButton(_ quest: ArmyQuest) -> some View {
        let words: String = quest.button(army)
        let rival: MatchController.Level = quest.rival
        return Button {
            play(rival)
        } label: {
            HStack(spacing: 6) {
                Text(words)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
        .layoutPriority(1)
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
