import AVFoundation
import SwiftUI

/// The castle's rooms, behind Rooms on Home (Alex, 2026-11-14: "5, 7, 8. Make sure there's an
/// introductory video"): the Trophy Hall, Famous Games and the Dungeon. All free. Each opens on
/// its own short film the first time; after that the room opens at once, with a small button to
/// watch the film again. Films are bundled in Rooms/Films: `room-<slug>-film.mp4` (9:16, five
/// seconds, silent) and `room-<slug>-card.jpg` (its last frame, the room's backdrop).
enum CastleRoom: String, Identifiable, CaseIterable {
    case trophies, famous, dungeon

    var id: String { rawValue }

    var slug: String {
        switch self {
        case .trophies: return "trophy-hall"
        case .famous: return "famous-games"
        case .dungeon: return "dungeon"
        }
    }

    var title: String {
        switch self {
        case .trophies: return "Trophy Hall"
        case .famous: return "Famous Games"
        case .dungeon: return "The Dungeon"
        }
    }

    var filmURL: URL? { Bundle.main.url(forResource: "room-\(slug)-film", withExtension: "mp4") }
    var cardImage: UIImage? {
        Bundle.main.path(forResource: "room-\(slug)-card", ofType: "jpg").flatMap(UIImage.init(contentsOfFile:))
    }

    // MARK: Films seen

    static let seenKey = "rooms.filmsSeen"

    func filmSeen(_ defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: Self.seenKey) ?? []).contains(rawValue)
    }

    func markFilmSeen(_ defaults: UserDefaults = .standard) {
        var all = defaults.stringArray(forKey: Self.seenKey) ?? []
        guard !all.contains(rawValue) else { return }
        all.append(rawValue)
        defaults.set(all, forKey: Self.seenKey)
    }
}

/// The castle's colors: torch gold on stone dark, the same in light and dark mode, as the
/// rivals' hall is.
enum CastleStyle {
    static let stone = Color(red: 0.07, green: 0.06, blue: 0.05)
    static let panel = Color.white.opacity(0.07)
    static let edge = Color(red: 0.86, green: 0.70, blue: 0.40).opacity(0.28)
    static let gold = Color(red: 0.90, green: 0.75, blue: 0.45)
    static let ink = Color(red: 0.96, green: 0.93, blue: 0.87)
    static let ink2 = Color(red: 0.96, green: 0.93, blue: 0.87).opacity(0.62)
    static let titleFont = "Cinzel-Bold"
}

/// One room, full screen: its film the first time, then the room over its backdrop.
struct CastleRoomScreen: View {
    let room: CastleRoom
    let theme: BoardTheme
    @State private var filmPlaying: Bool
    @Environment(\.dismiss) private var dismiss

    init(room: CastleRoom, theme: BoardTheme) {
        self.room = room
        self.theme = theme
        _filmPlaying = State(initialValue: !room.filmSeen() && room.filmURL != nil)
    }

    var body: some View {
        ZStack {
            CastleBackdrop(room: room)
            VStack(spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .opacity(filmPlaying ? 0 : 1)
            if filmPlaying {
                RoomFilm(room: room) {
                    room.markFilmSeen()
                    withAnimation(.easeOut(duration: 0.5)) { filmPlaying = false }
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .tint(CastleStyle.gold)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CastleStyle.ink)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Text(room.title.uppercased())
                .font(.custom(CastleStyle.titleFont, size: 20, relativeTo: .headline))
                .tracking(2)
                .foregroundStyle(CastleStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if room.filmURL != nil {
                Button {
                    withAnimation(.easeIn(duration: 0.3)) { filmPlaying = true }
                } label: {
                    Label("Watch again", systemImage: "play.fill")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(CastleStyle.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(.ultraThinMaterial, in: Capsule())
                        .frame(height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var content: some View {
        switch room {
        case .trophies: TrophyHallView(theme: theme)
        case .famous: FamousGamesView(theme: theme)
        case .dungeon: DungeonView(theme: theme)
        }
    }
}

/// The room's last film frame, darkened toward the bottom so the room reads over it.
struct CastleBackdrop: View {
    let room: CastleRoom

    var body: some View {
        CastleStyle.stone
            .overlay(alignment: .top) {
                if let image = room.cardImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .opacity(0.55)
                }
            }
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0),
                                       .init(color: .black.opacity(0.55), location: 0.35),
                                       .init(color: CastleStyle.stone.opacity(0.94), location: 0.7)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The room's film, full screen. A tap skips it; at its end it gives way to the room.
struct RoomFilm: View {
    let room: CastleRoom
    let done: () -> Void
    @State private var player: AVPlayer?
    @State private var titleShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.black
            .overlay {
                if let image = room.cardImage {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .overlay {
                if let player {
                    RivalFilmLayer(player: player)
                }
            }
            .overlay(alignment: .bottom) {
                Text(room.title.uppercased())
                    .font(.custom(CastleStyle.titleFont, size: 30, relativeTo: .largeTitle))
                    .tracking(4)
                    .foregroundStyle(CastleStyle.ink)
                    .shadow(color: .black.opacity(0.8), radius: 12)
                    .padding(.bottom, 90)
                    .opacity(titleShown ? 1 : 0)
                    .offset(y: titleShown ? 0 : 12)
            }
            .clipped()
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { finish() }
            .accessibilityElement()
            .accessibilityLabel("\(room.title) film")
            .accessibilityHint("Tap to skip")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { finish() }
            .onAppear(perform: start)
            .onDisappear { player?.pause() }
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
                guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
                finish()
            }
    }

    private func start() {
        guard let url = room.filmURL else {
            done()
            return
        }
        // The film is silent: it never stops music the player has on.
        let made = AVPlayer(url: url)
        made.isMuted = true
        made.preventsDisplaySleepDuringVideoPlayback = true
        player = made
        made.play()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 1.2).delay(1.6)) { titleShown = true }
    }

    private func finish() {
        guard player != nil else { return }
        player?.pause()
        player = nil
        done()
    }
}

/// A rounded dark glass card with a fine gold edge, the rooms' one surface.
struct CastleCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.6), in: shape)
            .background(CastleStyle.panel, in: shape)
            .overlay { shape.strokeBorder(CastleStyle.edge, lineWidth: 0.75) }
    }
}

/// A small gold heading between rules, for a room's sections.
struct CastleSectionTitle: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(CastleStyle.edge).frame(height: 0.75)
            Text(text.uppercased())
                .font(.custom(CastleStyle.titleFont, size: 13, relativeTo: .caption))
                .tracking(2)
                .foregroundStyle(CastleStyle.gold)
                .fixedSize()
            Rectangle().fill(CastleStyle.edge).frame(height: 0.75)
        }
        .padding(.top, 8)
        .accessibilityAddTraits(.isHeader)
    }
}
