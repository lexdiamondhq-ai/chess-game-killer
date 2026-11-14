import SwiftUI

/// Coach Leo's story for each famous game: a line before the first move, and lines that show
/// as the key moves are played, keyed by the move's index in `ClassicGame.moves` (0 is White's
/// first move). Checked against the games' moves by FamousGameStoryTests.
enum FamousGameStory {
    struct Story {
        let opening: String
        let moments: [Int: String]
    }

    static let stories: [String: Story] = [
        "opera": Story(
            opening: "Paris, 1858. Paul Morphy plays in a box at the opera, against two noblemen thinking together.",
            moments: [18: "Morphy gives a knight away to open lines to the black king.",
                      24: "Now a rook. Every white piece is joining the attack.",
                      30: "The queen sacrifice! Black has to take it.",
                      32: "Mate with the last two pieces. Seventeen moves, and still the most loved game ever."]),
        "immortal": Story(
            opening: "London, 1851. A friendly game between Anderssen and Kieseritzky, soon called the Immortal Game.",
            moments: [20: "Anderssen leaves his rook to be taken. He wants time, not material.",
                      35: "Black takes the second rook too.",
                      42: "And now the queen is given away.",
                      44: "Three small pieces mate the king. White gave up almost everything to win."]),
        "evergreen": Story(
            opening: "Berlin, 1852. Anderssen again, against Dufresne.",
            moments: [6: "The Evans Gambit: a pawn given for a fast attack.",
                      38: "A rook sacrifice rips open the king.",
                      40: "Then the queen goes too.",
                      46: "Two bishops finish it. An attack that never let go."]),
        "century": Story(
            opening: "New York, 1956. Bobby Fischer is 13 years old. His opponent, Donald Byrne, is a strong master.",
            moments: [21: "A knight jumps to the edge. It looks odd, but it is the start of a trap.",
                      33: "Fischer leaves his queen hanging, on purpose.",
                      35: "Byrne took the queen. Now Fischer's pieces start a windmill of checks.",
                      81: "Mate. A boy beat a master, and they called it the Game of the Century."]),
        "kasparov-topalov": Story(
            opening: "Wijk aan Zee, 1999. Garry Kasparov, the world champion, against Veselin Topalov.",
            moments: [46: "Kasparov gives up a whole rook to drag the king out.",
                      51: "The black king is pulled out of its home.",
                      61: "It runs across the board, but there is nowhere safe.",
                      86: "Topalov resigned. One of the greatest attacks ever played."]),
        "reti-tartakower": Story(
            opening: "Vienna, 1910. A short game every player should know.",
            moments: [16: "Réti gives his queen with check. The king must take it.",
                      18: "Double check! Two pieces give check at once, so the king can only run.",
                      20: "Mate, with the bishop on the very square where the queen died."]),
        "lasker-thomas": Story(
            opening: "London, 1912. Edward Lasker against George Thomas.",
            moments: [20: "Lasker gives his queen with check.",
                      21: "The king takes it, and now it has to walk.",
                      33: "Checked all the way down the board, the king lands on g1.",
                      34: "A quiet king move gives mate. The longest king hunt you'll ever see."]),
        "fischer-spassky-6": Story(
            opening: "Reykjavik, 1972, the world title match. Fischer almost always opens with the king's pawn.",
            moments: [0: "Not today. 1.c4, a surprise for everyone in the hall.",
                      74: "A rook for a knight breaks the wall around the king.",
                      80: "Spassky resigned, and then stood and clapped for his opponent."]),
        "rotlewi-rubinstein": Story(
            opening: "Łódź, 1907. Akiba Rubinstein has Black.",
            moments: [41: "Rubinstein puts his queen where a pawn can take it.",
                      43: "He lets the queen go and takes a knight instead.",
                      45: "Another piece offered. His bishops rake the white king.",
                      49: "Mate can't be stopped, and White resigned."]),
        "deepblue-kasparov-6": Story(
            opening: "New York, 1997. The last game of the match: Deep Blue, a computer, against the world champion.",
            moments: [14: "The machine gives a knight to break open the king.",
                      36: "Kasparov resigned after 19 moves. A computer had beaten the world champion in a match."]),
        "short-timman": Story(
            opening: "Tilburg, 1991. Nigel Short against Jan Timman.",
            moments: [61: "With queens on the board, White's king starts walking forward.",
                      66: "The king reaches g5 to help with mate. Timman resigned."]),
    ]

    static func line(for game: ClassicGame, at index: Int) -> String? {
        stories[game.id]?.moments[index]
    }

    static func opening(for game: ClassicGame) -> String {
        stories[game.id]?.opening ?? game.blurb
    }
}

/// Famous Games (Alex's pick, 2026-11-14): the great games of chess, each played out on the
/// board by itself while Coach Leo tells the story.
struct FamousGamesView: View {
    let theme: BoardTheme
    @State private var watching: ClassicGame?

    private var games: [ClassicGame] { GrandmasterContent.shared.games.sorted { $0.year < $1.year } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Pick a game and watch it play out while Leo tells the story.")
                    .font(.app(.subheadline, weight: .medium))
                    .foregroundStyle(CastleStyle.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                CastleCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                            Button { watching = game } label: { row(game) }
                                .buttonStyle(.plain)
                            if index < games.count - 1 {
                                Rectangle().fill(CastleStyle.edge).frame(height: 0.5).padding(.leading, 70)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(item: $watching) { game in
            FamousGameTheater(game: game, theme: theme)
        }
    }

    private func row(_ game: ClassicGame) -> some View {
        HStack(spacing: 14) {
            Text(game.year > 0 ? String(game.year) : "")
                .font(.custom(CastleStyle.titleFont, size: 14, relativeTo: .subheadline))
                .foregroundStyle(CastleStyle.gold)
                .frame(width: 42, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.title)
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(CastleStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(game.blurb)
                    .font(.app(.caption))
                    .foregroundStyle(CastleStyle.ink2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(CastleStyle.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Watch the game")
    }
}

/// Plays a famous game by itself, a move every little while, with Leo's story under the board.
/// Pause, step back and forward, or start again.
@MainActor
@Observable
final class FamousGamePlayer {
    let game: ClassicGame
    private(set) var board = FamousGamePlayer.freshBoard()
    /// How many moves are on the board.
    private(set) var index = 0
    private(set) var playing = false
    private(set) var story: String
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Time between moves; longer after a story line, so it can be read.
    static let pace: Duration = .milliseconds(1100)
    static let storyPause: Duration = .milliseconds(3200)

    init(game: ClassicGame) {
        self.game = game
        story = FamousGameStory.opening(for: game)
    }

    var finished: Bool { index >= game.moves.count }

    private static func freshBoard() -> GameModel {
        let model = GameModel()
        model.humanColors = []
        return model
    }

    func play() {
        if finished { restart() }
        playing = true
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            while let self, !Task.isCancelled, !self.finished {
                let told = self.stepForward(sound: true)
                try? await Task.sleep(for: told ? FamousGamePlayer.storyPause : FamousGamePlayer.pace)
            }
            self?.playing = false
        }
    }

    func pause() {
        task?.cancel()
        task = nil
        playing = false
    }

    func restart() {
        pause()
        board = Self.freshBoard()
        index = 0
        story = FamousGameStory.opening(for: game)
    }

    /// Plays the next move; true when it brought a story line.
    @discardableResult
    func stepForward(sound: Bool = true) -> Bool {
        guard !finished else { return false }
        board.playEngineMove(game.moves[index])
        if sound { SoundPlayer.shared.play(.move) }
        let played = index
        index += 1
        if let line = FamousGameStory.line(for: game, at: played) {
            story = line
            return true
        }
        if finished { story = ending }
        return false
    }

    /// Takes back one move by playing the game again up to the move before.
    func stepBack() {
        guard index > 0 else { return }
        pause()
        let target = index - 1
        board = Self.freshBoard()
        index = 0
        story = FamousGameStory.opening(for: game)
        while index < target { stepForward(sound: false) }
    }

    private var ending: String {
        switch game.result {
        case "1-0": return "\(game.white) wins."
        case "0-1": return "\(game.black) wins."
        default: return "A draw."
        }
    }

    func cancel() { task?.cancel() }
}

struct FamousGameTheater: View {
    let game: ClassicGame
    let theme: BoardTheme
    @State private var player: FamousGamePlayer
    @Environment(\.dismiss) private var dismiss

    init(game: ClassicGame, theme: BoardTheme) {
        self.game = game
        self.theme = theme
        _player = State(initialValue: FamousGamePlayer(game: game))
    }

    var body: some View {
        GeometryReader { geo in
            let side = max(200, min(geo.size.width - TrainingBoardView.sideRoom, geo.size.height - 330))
            VStack(spacing: 12) {
                RoomHeader(title: game.title, subtitle: game.playedAt) { dismiss() }
                TrainerBoard(game: player.board, theme: theme, side: side, flipped: game.hero == .black)
                RoomMessage(text: player.story, tone: .coach, theme: theme)
                    .padding(.horizontal, 16)
                controls
                    .padding(.horizontal, 16)
                Text("Move \((player.index + 1) / 2) of \((game.moves.count + 1) / 2)")
                    .font(.app(.caption).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width)
        }
        .background { TrainingBackdrop(theme: theme) }
        .onAppear { player.play() }
        .onDisappear { player.cancel() }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { player.stepBack() } label: {
                Image(systemName: "backward.frame.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
            .disabled(player.index == 0)
            .accessibilityLabel("Back one move")
            Button {
                player.playing ? player.pause() : player.play()
            } label: {
                Label(player.playing ? "Pause" : player.finished ? "Watch again" : "Play",
                      systemImage: player.playing ? "pause.fill" : player.finished ? "arrow.counterclockwise" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
            Button {
                player.pause()
                player.stepForward()
            } label: {
                Image(systemName: "forward.frame.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
            .disabled(player.finished)
            .accessibilityLabel("Next move")
        }
    }
}
