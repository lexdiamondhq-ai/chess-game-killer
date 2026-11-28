import SwiftUI

/// Play a friend, a slim row right under the gold bar on the Aurora home (Alex, 2026-11-20:
/// "How do I start a game? I thought it was on the homepage"; picked A). The faces of up to
/// three of your people sit on the left: a tap on one sends them a game at once. The rest of
/// the row, and Invite, open Play a friend to pick anyone.
struct HomeAuroraFriendRow: View {
    let people: [FriendPerson]
    let palette: HomeAuroraPalette
    let open: () -> Void
    let challenge: (FriendPerson) -> Void

    @AppStorage("haptics") private var hapticsOn = true
    @State private var tapped: FriendPerson?

    static let faceCount = 3

    /// "Sam, Mia or anyone", "Sam or anyone", or the plain line when you have nobody yet.
    static func detail(_ people: [FriendPerson]) -> String {
        let names: [String] = people.prefix(faceCount).map { $0.name.split(separator: " ").first.map(String.init) ?? $0.name }
        guard !names.isEmpty else { return "Send a game to anyone you know" }
        return names.joined(separator: ", ") + " or anyone"
    }

    private var faces: [FriendPerson] { Array(people.prefix(Self.faceCount)) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(spacing: 10) {
            if faces.isEmpty {
                Glyph(name: Glyphs.challenge, size: 20)
                    .foregroundStyle(palette.gold)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(palette.gold.opacity(0.55), lineWidth: 1))
                    .accessibilityHidden(true)
            } else {
                HStack(spacing: -9) {
                    ForEach(faces) { person in
                        Button {
                            tapped = person
                            challenge(person)
                        } label: {
                            face(person)
                        }
                        .buttonStyle(HomeStagePress())
                        .accessibilityLabel("Send \(person.name) a game")
                    }
                }
            }
            Button(action: open) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Play a friend")
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                        Text(Self.detail(people))
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.ink2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        Text("Invite")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(palette.gold)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .overlay(Capsule().strokeBorder(palette.gold.opacity(0.8), lineWidth: 1.2))
                    .layoutPriority(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HomeStagePress())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Play a friend, \(Self.detail(people))")
            .accessibilityHint("Opens Play a friend")
        }
        .padding(.leading, faces.isEmpty ? 12 : 21)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, minHeight: 58)
        .auroraCard(shape, palette: palette, fill: palette.dark ? 0.8 : 0.9)
        .sensoryFeedback(.impact(weight: .light), trigger: tapped) { _, new in hapticsOn && new != nil }
    }

    private func face(_ person: FriendPerson) -> some View {
        Text(person.initial)
            .font(.system(size: 12, weight: .bold, design: .serif))
            .foregroundStyle(Color(hex: 0x2A1E0F))
            .frame(width: 30, height: 30)
            .background(Circle().fill(LinearGradient(colors: [Color(hex: 0xF3D99A), Color(hex: 0xB0763A)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(Circle().strokeBorder(palette.card, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                if person.online {
                    Circle().fill(palette.dark ? StoneInk.emerald.color(dark: true) : HomeTone.liveOnLight)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(palette.card, lineWidth: 1.5))
                }
            }
    }
}
