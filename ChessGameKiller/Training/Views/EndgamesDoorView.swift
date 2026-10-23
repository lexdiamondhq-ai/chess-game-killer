import SwiftUI

/// Behind the Endgames door: the endgames every player must know, in the order to learn
/// them, each played against perfect defence. The next one to learn sits on top.
struct EndgamesDoorView: View {
    let theme: BoardTheme
    @Environment(EndgameProgress.self) private var progress
    @State private var study: EndgameStudy?

    private var studies: [EndgameStudy] { GrandmasterContent.shared.endgames }

    /// The studies by group, in the order the content lists them.
    private var groups: [(name: String, studies: [EndgameStudy])] {
        var order: [String] = []
        var byGroup: [String: [EndgameStudy]] = [:]
        for study in studies {
            if byGroup[study.group] == nil { order.append(study.group) }
            byGroup[study.group, default: []].append(study)
        }
        return order.map { (name: $0, studies: byGroup[$0] ?? []) }
    }

    private var next: EndgameStudy? { studies.first { !progress.isDone($0.id) } }

    var body: some View {
        TrainScreen(theme: theme, title: "Endgames",
                    intro: "Close games are decided here. Learn the positions every player must know, against a defender who never slips.") {
            nextCard
            ForEach(groups, id: \.name) { group in
                TrainSectionTitle(text: group.name)
                VStack(spacing: 0) {
                    ForEach(Array(group.studies.enumerated()), id: \.element.id) { index, study in
                        Button {
                            self.study = study
                        } label: {
                            row(study)
                        }
                        .buttonStyle(.plain)
                        if index < group.studies.count - 1 {
                            Divider().opacity(0.4).padding(.leading, 60)
                        }
                    }
                }
                .trainingCard(theme)
            }
            Text("Online, every move is judged by the Lichess tablebase, which knows the perfect result. Offline, Stockfish judges.")
                .font(.system(.footnote, design: .themed))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .fullScreenCover(item: $study) { study in
            EndgameView(study: study, theme: theme)
                .environment(progress)
        }
    }

    /// How far along the player is, and the next endgame to learn.
    private var nextCard: some View {
        let done = studies.filter { progress.isDone($0.id) }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(done == studies.count ? "ALL MASTERED" : "NEXT UP")
                    .font(.system(.caption, design: .themed).weight(.bold))
                    .tracking(1)
                    .foregroundStyle(theme.trainingAccent)
                Spacer()
                Text("\(done) of \(studies.count)")
                    .font(.system(.footnote, design: .themed).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let next {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.title)
                        .font(.system(.title3, design: .themed).weight(.bold))
                    Text(next.idea)
                        .font(.system(.subheadline, design: .themed))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("You've mastered every endgame here. Play them again any time to keep them sharp.")
                    .font(.system(.subheadline, design: .themed))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProgressView(value: Double(done), total: Double(max(studies.count, 1)))
                .tint(theme.trainingAccent)
                .accessibilityHidden(true)
            if let next {
                Button {
                    study = next
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
            }
        }
        .padding(18)
        .trainingCard(theme, tint: theme.trainingAccent)
        .accessibilityElement(children: .contain)
    }

    private func row(_ study: EndgameStudy) -> some View {
        let isDone = progress.isDone(study.id)
        return HStack(spacing: 14) {
            ZStack {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(theme.trainingAccent)
                } else {
                    EndgameLevelBars(level: study.level, color: theme.trainingAccent)
                }
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(study.title)
                    .font(.system(.subheadline, design: .themed).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(study.idea)
                    .font(.system(.caption, design: .themed))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(study.title), \(EndgameLevelBars.name(study.level))\(isDone ? ", mastered" : "")")
        .accessibilityHint(study.idea)
        .accessibilityAddTraits(.isButton)
    }
}

/// Difficulty as three small bars, filled up to the level.
struct EndgameLevelBars: View {
    let level: Int
    let color: Color

    static func name(_ level: Int) -> String {
        switch level {
        case ...1: return "easy"
        case 2: return "medium"
        default: return "hard"
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(1...3, id: \.self) { bar in
                Capsule()
                    .fill(bar <= level ? color : Color.primary.opacity(0.16))
                    .frame(width: 4, height: 6 + CGFloat(bar) * 4)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
