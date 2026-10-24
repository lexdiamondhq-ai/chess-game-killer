import SwiftUI

/// Behind the Endgames door: the endgames every player must know, in the order to learn
/// them, each played against perfect defence. The next one to learn sits on top.
struct EndgamesDoorView: View {
    let theme: BoardTheme
    @Environment(EndgameProgress.self) private var progress
    @State private var study: EndgameStudy?
    @State private var offer: PremiumFeature?

    /// The shelves that have studies on them, in the order to learn them.
    private var groups: [(group: EndgameStudy.Group, studies: [EndgameStudy])] {
        EndgameStudy.Group.allCases.compactMap { group in
            let studies = progress.studies(in: group)
            return studies.isEmpty ? nil : (group, studies)
        }
    }

    var body: some View {
        let due = progress.dueForReview()
        TrainScreen(theme: theme, title: "Endgames",
                    intro: "Close games are decided here. Learn the positions every player must know, against a defender who never slips.") {
            nextCard
            if !due.isEmpty {
                TrainSectionTitle(text: "Due for review")
                list(due)
            }
            ForEach(groups, id: \.group) { entry in
                TrainSectionTitle(text: "\(entry.group.rawValue) · \(progress.doneCount(in: entry.group)) of \(entry.studies.count)")
                list(entry.studies)
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
        }
        .premiumOffer($offer)
    }

    /// One endgame a day free (playing it again that day is free too); Premium plays them all.
    private func play(_ next: EndgameStudy) {
        if Premium.shared.use(.endgameDrill, key: next.id) { study = next } else { offer = .endgameDrill }
    }

    private func list(_ studies: [EndgameStudy]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(studies.enumerated()), id: \.element.id) { index, study in
                Button {
                    play(study)
                } label: {
                    row(study)
                }
                .buttonStyle(.plain)
                if index < studies.count - 1 {
                    Divider().opacity(0.4).padding(.leading, 60)
                }
            }
        }
        .trainingCard(theme)
    }

    /// How far along the player is, and the next endgame to learn.
    private var nextCard: some View {
        let next = progress.nextUp
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(next == nil ? "ALL LEARNED" : "NEXT UP")
                    .font(.system(.caption, design: .themed).weight(.bold))
                    .tracking(1)
                    .foregroundStyle(theme.trainingAccent)
                Spacer()
                Text("\(progress.doneCount) of \(progress.total)")
                    .font(.system(.footnote, design: .themed).weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let next {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.title)
                        .font(.system(.title3, design: .themed).weight(.bold))
                    Text(next.goalText)
                        .font(.system(.footnote, design: .themed).weight(.semibold))
                        .foregroundStyle(theme.trainingAccent)
                    Text(next.idea)
                        .font(.system(.subheadline, design: .themed))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            } else {
                Text("You've learned every endgame here. They come back for review now and then, so they stay sharp.")
                    .font(.system(.subheadline, design: .themed))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProgressView(value: Double(progress.doneCount), total: Double(max(progress.total, 1)))
                .tint(theme.trainingAccent)
                .accessibilityHidden(true)
            if let next {
                Button {
                    play(next)
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
        let isClean = progress.isClean(study.id)
        return HStack(spacing: 14) {
            ZStack {
                if isDone {
                    Image(systemName: isClean ? "checkmark.seal.fill" : "checkmark.circle.fill")
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
                Text(study.goalText)
                    .font(.system(.caption, design: .themed))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .accessibilityLabel(rowLabel(study, isDone: isDone, isClean: isClean))
        .accessibilityHint(study.idea)
        .accessibilityAddTraits(.isButton)
    }

    private func rowLabel(_ study: EndgameStudy, isDone: Bool, isClean: Bool) -> String {
        let state = isClean ? ", learned with no slips" : isDone ? ", learned" : ""
        return "\(study.title). \(study.goalText). \(study.levelName)\(state)"
    }
}

/// Difficulty as three small bars, filled up to the level.
struct EndgameLevelBars: View {
    let level: Int
    let color: Color

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
