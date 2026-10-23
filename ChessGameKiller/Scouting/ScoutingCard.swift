import ChessKit
import SwiftUI

/// How the last trap a rival set ended, kept per rival so the next report can open with it.
struct ScoutingDuel: Codable, Equatable {
    let date: Date
    let moveNumber: Int
    let fell: Bool
}

/// The last duel with each rival, on this device.
enum ScoutingLedger {
    static let key = "scouting.duels"

    static func last(for level: MatchController.Level, defaults: UserDefaults = .standard) -> ScoutingDuel? {
        all(defaults)[String(level.rawValue)]
    }

    static func record(_ trap: ScoutingReport.Trap, fell: Bool, level: MatchController.Level,
                       now: Date = .now, defaults: UserDefaults = .standard) {
        var duels = all(defaults)
        duels[String(level.rawValue)] = ScoutingDuel(date: now, moveNumber: trap.moveNumber, fell: fell)
        if let data = try? JSONEncoder().encode(duels) { defaults.set(data, forKey: key) }
    }

    private static func all(_ defaults: UserDefaults) -> [String: ScoutingDuel] {
        guard let data = defaults.data(forKey: key),
              let duels = try? JSONDecoder().decode([String: ScoutingDuel].self, from: data) else { return [:] }
        return duels
    }
}

/// The rival's file on the player, under the rival's card on the New Game sheet: a folded
/// tab ("Pulse has studied 14 of your games") that opens to up to three findings, each with
/// the position it comes from.
struct ScoutingCard: View {
    let theme: BoardTheme
    let rival: Rival

    @Environment(GameVault.self) private var vault: GameVault?
    @State private var report: ScoutingReport = .empty
    @State private var isOpen = false
    @AppStorage("haptics") private var hapticsOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard report.isReady else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: report.isReady ? "folder.fill" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(rival.hue)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(theme.isDark ? 0.34 : 0.07),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCOUTING REPORT")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        Text(headline)
                            .font(.system(.callout, design: .themed).weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if report.isReady {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isOpen ? rival.hue : Color.secondary.opacity(0.7))
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(report.isReady ? (isOpen ? "Closes the report" : "Opens the report") : "")

            if isOpen {
                VStack(alignment: .leading, spacing: 12) {
                    if let duel = ScoutingLedger.last(for: rival.level) {
                        Text(duelLine(duel))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(duel.fell ? Color(red: 1, green: 0.42, blue: 0.42) : Color(red: 0.95, green: 0.78, blue: 0.4))
                    }
                    ForEach(report.findings) { finding in
                        FindingRow(finding: finding, theme: theme, rival: rival)
                    }
                    Text("Read only from your games on this phone.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            GlassSurface(shape: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .sensoryFeedback(.selection, trigger: isOpen) { _, _ in hapticsOn }
        .onAppear { report = ScoutingReport.make(from: vault?.games ?? []) }
        .onChange(of: rival.level) { isOpen = false }
    }

    private var headline: String {
        if report.isReady {
            let games = report.gamesStudied
            return "\(rival.name) has studied \(games) of your game\(games == 1 ? "" : "s")."
        }
        let needed = max(1, ScoutingReport.gamesForAReport - report.gamesStudied)
        return "\(rival.name) is watching. Play \(needed) more game\(needed == 1 ? "" : "s") for a full report."
    }

    private func duelLine(_ duel: ScoutingDuel) -> String {
        let when = ScoutingReport.when(duel.date, now: .now)
        return duel.fell
            ? "Last time (\(when)), you fell for my trap on move \(duel.moveNumber)."
            : "Last time (\(when)), you saw my trap on move \(duel.moveNumber)."
    }
}

/// One finding: the rival's line, and the position it comes from.
private struct FindingRow: View {
    let finding: ScoutingReport.Finding
    let theme: BoardTheme
    let rival: Rival

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let fen = finding.fen, let draft = PositionDraft(fen: fen) {
                PositionBoard(draft: draft, theme: theme, flipped: TrainingChess.sideToMove(fen) == .black)
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            } else {
                RivalSigil(rival: rival, size: 44, glows: theme.glows)
                    .frame(width: 64, height: 64)
            }
            Text("\u{201C}\(finding.line)\u{201D}")
                .font(.system(.subheadline, design: .themed))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
