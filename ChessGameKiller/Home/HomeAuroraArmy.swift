import ChessKit
import SwiftUI

/// Your army at the foot of the Aurora home, as a wide banner (Alex's picks, 2026-11-12: "A and C
/// together", then "move the Army to the bottom and change the format to more of a rectangle").
/// The champion, your most experienced piece, stands on a stone base beside its name carved in
/// Cinzel (gold once it is a Legend), its rank and a fine gold line to the next rank. Along the
/// bottom, the army's job for today: free a piece a rival holds, or help one piece to its next
/// rank, with a button that plays that rival. Nothing glows (Alex, 2026-11-11). A tap anywhere
/// else opens the army, where all sixteen pieces are.
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
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            if let champion {
                hero(champion)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                Text("Sixteen pieces, each remembers its games. Play a rival and they start earning names.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
            if let quest {
                questStrip(quest)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(palette.card))
        .clipShape(shape)
        .overlay(shape.strokeBorder(palette.line, lineWidth: 1))
        .contentShape(shape)
    }

    // MARK: The champion

    private func hero(_ slot: ArmySlot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            plinth(slot)
            heroWords(slot)
            Spacer(minLength: 0)
        }
    }

    /// The champion big, on the stone base it stands on.
    private func plinth(_ slot: ArmySlot) -> some View {
        let rank: ArmyRank = army.record(for: slot).rank
        let piece = Piece(slot.kind, color: color, square: slot.square(for: color))
        let stone = LinearGradient(colors: [Color(hex: 0x6A5D51), Color(hex: 0x2E2621)],
                                   startPoint: .top, endPoint: .bottom)
        let base = Ellipse()
            .fill(stone)
            .overlay(Ellipse().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
            .frame(width: 70, height: 14)
            .shadow(color: palette.shadow, radius: 5, y: 4)
        let figure = PieceImage(piece: piece, theme: pieceTheme, size: 64, heirloom: army.heirloom(for: slot))
            .modifier(VeteranAura(rank: rank, piece: piece, theme: pieceTheme, size: 64, onBoard: false))
            .frame(width: 64, height: 64)
            .padding(.bottom, 6)
        return ZStack(alignment: .bottom) {
            base
            figure
        }
        .frame(width: 74, height: 78)
    }

    /// Its name carved in Cinzel (gold for a Legend), its rank, place and the XP to its next
    /// rank on one line, and a fine gold line filled as far as it has come.
    private func heroWords(_ slot: ArmySlot) -> some View {
        let record: PieceRecord = army.record(for: slot)
        let named: Bool = record.name != nil
        let nameColor: Color = record.rank == .legend ? palette.gold : palette.ink
        var parts: [String] = [record.rank.title]
        if named { parts.append(slot.title) }
        if let next = record.rank.next {
            parts.append("\(next.threshold - record.xp) XP to \(next.title)")
        } else {
            parts.append("\(record.xp) XP")
        }
        let rankWords: String = parts.joined(separator: " · ").uppercased()
        return VStack(alignment: .leading, spacing: 4) {
            Text("YOUR CHAMPION")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(palette.gold)
            Text(record.name ?? slot.title)
                .font(.custom(Self.nameFont, size: named ? 23 : 18))
                .foregroundStyle(nameColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(rankWords)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(palette.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            rankBar(army.rankProgress(of: slot))
                .padding(.top, 4)
        }
    }

    private func rankBar(_ progress: Double) -> some View {
        let fill = LinearGradient(colors: [palette.gold.opacity(0.45), palette.gold],
                                  startPoint: .leading, endPoint: .trailing)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.line)
                Capsule()
                    .fill(fill)
                    .frame(width: max(3, geo.size.width * progress))
            }
        }
        .frame(height: 3)
    }

    // MARK: The quest

    /// The strip along the banner's foot: the quest in words, and its gold button.
    private func questStrip(_ quest: ArmyQuest) -> some View {
        let wash: Color = palette.gold.opacity(palette.dark ? 0.06 : 0.07)
        return HStack(alignment: .center, spacing: 12) {
            Text(quest.line(army))
                .font(.system(size: 12.5))
                .foregroundStyle(palette.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            questButton(quest)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 48)
        .background(wash)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.line).frame(height: 1)
        }
    }

    /// The gold button that plays the quest's rival.
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
