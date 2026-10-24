import SwiftUI

/// Leo or Vera: two portraits side by side. Tapping one picks that coach and plays their hello,
/// so the voice is heard before it's chosen. In Settings and on the Train page.
struct CoachPicker: View {
    let theme: BoardTheme
    @State private var choice = CoachChoice.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ForEach(Coach.allCases) { coach in
                    CoachCard(coach: coach, isSelected: choice.coach == coach, theme: theme) {
                        pick(coach)
                    }
                }
            }
            Text(choice.coach.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .animation(.easeInOut(duration: 0.2), value: choice.coach)
        }
    }

    private func pick(_ coach: Coach) {
        withAnimation(.easeInOut(duration: 0.25)) { choice.coach = coach }
        CoachReactions.shared.preview(coach)
    }
}

/// One coach: the portrait, the name and how they sound.
private struct CoachCard: View {
    let coach: Coach
    let isSelected: Bool
    let theme: BoardTheme
    let action: () -> Void

    private var accent: Color { theme.accent ?? theme.trainingAccent }

    private var voiceNote: String {
        coach == .leo ? "Warm, British" : "Bright, American"
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                CoachAvatar(theme: theme, size: 56, tint: isSelected ? accent : nil, coach: coach)
                Text(coach.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text(voiceNote)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(coach.title). \(voiceNote) voice.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Picks \(coach.name) as your coach and plays a hello.")
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return GlassSurface(shape: shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(accent, lineWidth: 1.5)
                }
            }
    }
}
