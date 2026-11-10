import SwiftUI

/// The way into the coach's deep review: one slim gold row on Rewind, between the game's
/// line and its card.
struct DeepReviewRow: View {
    let theme: BoardTheme
    let coach: Coach
    /// Kept with the game already: hearing it again is instant and free.
    let kept: Bool
    /// A new review is Premium's; without it the row opens the offer.
    let open: Bool
    let action: () -> Void

    private var subtitle: String {
        if kept { return "Hear it again" }
        return open ? "The whole game, in about 90 seconds" : "Premium · the whole game, in about 90 seconds"
    }

    var body: some View {
        let gold = RewindPalette.goldInk(on: theme)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            HStack(spacing: 12) {
                CoachAvatar(theme: theme, size: 36, coach: coach)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(coach.name)'s deep review")
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Image(systemName: open || kept ? "play.fill" : "lock.fill")
                    .font(.app(.footnote, weight: .bold))
                    .foregroundStyle(gold)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(gold.opacity(0.16)))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 56)
            .background { shape.fill(gold.opacity(0.10)) }
            .overlay { shape.strokeBorder(gold.opacity(0.35), lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(coach.name)'s deep review. \(subtitle)")
    }
}

/// The review as it plays: who is talking and the chapter, how far along it is, the words
/// being said, and pause, back and forward.
struct DeepReviewCard: View {
    let theme: BoardTheme
    let player: DeepReviewPlayer
    let onClose: () -> Void

    private var gold: Color { RewindPalette.goldInk(on: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top
            switch player.phase {
            case .loading:
                waiting
            case .failed(let why):
                failed(why)
            case .playing, .paused, .finished:
                progress.padding(.top, 14)
                words
                controls.padding(.top, 4)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: player.index)
        .animation(.snappy(duration: 0.25), value: player.phase)
    }

    private var top: some View {
        HStack(spacing: 12) {
            CoachAvatar(theme: theme, size: 40, coach: player.coach)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(player.coach.name)'s deep review")
                    .font(.app(.caption2, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(chapter)
                    .font(.app(.headline))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.app(.footnote, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.primary.opacity(0.07)).padding(4))
            }
            .tint(.primary)
            .accessibilityLabel("Close the review")
        }
    }

    private var chapter: String {
        switch player.phase {
        case .loading: return "Going through your game"
        case .failed: return "No review this time"
        case .playing, .paused, .finished: return player.part?.label ?? ""
        }
    }

    /// One mark per part; the ones heard are gold.
    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(player.partCount, 1), id: \.self) { part in
                Capsule()
                    .fill(part <= player.index ? AnyShapeStyle(gold) : AnyShapeStyle(Color.primary.opacity(0.12)))
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private var words: some View {
        ScrollView {
            Text(player.part?.text ?? "")
                .font(.app(.body, scale: 1.06))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .id(player.index)
                .transition(.opacity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            roundButton("chevron.left", label: "Previous part", disabled: player.index == 0) {
                player.go(to: player.index - 1)
            }
            roundButton(player.phase == .playing ? "pause.fill" : "play.fill",
                  label: player.phase == .playing ? "Pause" : player.phase == .finished ? "Hear it again" : "Play",
                  disabled: false) {
                if player.phase == .playing { player.pause() } else { player.resume() }
            }
            roundButton("chevron.right", label: "Next part", disabled: player.index + 1 >= player.partCount) {
                player.go(to: player.index + 1)
            }
            Spacer(minLength: 4)
            if player.phase == .finished {
                Button(action: onClose) {
                    Text("Done")
                        .font(.app(.subheadline, weight: .semibold))
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .foregroundStyle(.background)
                        .background(Capsule().fill(Color.primary.opacity(0.92)))
                }
                .buttonStyle(.plain)
            } else {
                Text("\(player.index + 1) of \(player.partCount)")
                    .font(.app(.subheadline, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("\(player.coach.name) is going through your game.")
                    .font(.app(.body))
            }
            Text("It takes about fifteen seconds. \(player.coach.subjectCapitalized) reads every move before \(player.coach.subject) says a word.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func failed(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(why)
                .font(.app(.body))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                player.start()
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(.app(.subheadline, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .foregroundStyle(.background)
                    .background(Capsule().fill(Color.primary.opacity(0.92)))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func roundButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(.footnote, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .tint(.primary)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}
