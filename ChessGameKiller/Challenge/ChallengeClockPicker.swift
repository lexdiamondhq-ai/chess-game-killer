import SwiftUI

/// The clock for a game with another player, on Play online and Challenge a friend alike: the quick
/// picks (∞ first), More times folding open Bullet, Blitz, Rapid and Classical, and with ∞ picked,
/// the days per move of a daily game on a glass − / + line. The line under it says what the pick means.
struct ChallengeClockPicker: View {
    /// The picked clock, as `OnlineLobby.clockID` keeps it ("5+0", or "none" for ∞).
    @Binding var clockID: String
    /// With ∞ picked: the days per move, or 0 for no limit.
    @Binding var dailyDays: Int
    let theme: BoardTheme
    /// Waiting for a game: the pick can't change.
    var locked = false
    /// The line under the picks, for a clock (nil: none) and, with none, the days per move.
    let detail: (FriendClock?, Int?) -> String

    /// More times is folded open. It starts open when the picked clock lives there.
    @State private var showsMore: Bool?

    private var clock: FriendClock? { OnlineLobby.clock(id: clockID) }
    private var days: Int? { clock == nil && DailyDays.options.contains(dailyDays) ? dailyDays : nil }
    private var isMoreOpen: Bool { showsMore ?? !OnlineLobby.quickPicks.contains(clock) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChallengeSectionTitle(title: "Clock")
            HStack(spacing: 8) {
                ForEach(OnlineLobby.quickPicks, id: \.self) { option in
                    clockChip(option)
                }
            }
            Button {
                withAnimation(.snappy(duration: 0.3)) { showsMore = !isMoreOpen }
            } label: {
                HStack(spacing: 4) {
                    Text("More times")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(isMoreOpen ? 180 : 0))
                }
                .font(theme.challengeFont(14, .semibold))
                .foregroundStyle(theme.challengeAccent)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMoreOpen ? "Fewer times" : "More times")
            if clock == nil {
                OnlineDaysStepper(days: $dailyDays, theme: theme)
                    .disabled(locked)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if isMoreOpen {
                moreClocks
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Text(detail(clock, days))
                .font(theme.challengeFont(12))
                .foregroundStyle(.secondary)
        }
        .animation(.snappy(duration: 0.3), value: clock == nil)
    }

    /// Bullet, Blitz, Rapid and Classical, each a row of chips, on a glass card.
    private var moreClocks: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(OnlineLobby.moreClocks) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name.uppercased())
                        .font(theme.challengeFont(11.5, .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 6) {
                        ForEach(group.clocks, id: \.self) { option in
                            clockChip(option, size: 14)
                        }
                    }
                }
            }
        }
        .padding(14)
        .challengeGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func clockChip(_ option: FriendClock?, size: CGFloat = 15) -> some View {
        ChallengeChip(title: option?.label ?? "∞", isOn: clock == option, theme: theme,
                      size: option == nil ? 24 : size) {
            withAnimation(.snappy(duration: 0.3)) { clockID = OnlineLobby.clockID(option) }
        }
        .accessibilityLabel(detail(option, nil))
        .disabled(locked)
    }
}
