import ChessKit
import SwiftUI

/// A different famous game each day, its finish playing itself out on a small board on
/// Today: the Opera Game's queen sacrifice, the Immortal Game's mate, Fischer's Game of the
/// Century. A tap opens it in Analyze at the start of the finish, to play through and test
/// against Stockfish.
struct HomeMasterpiece: Equatable {
    let game: ClassicGame
    /// The position the finish starts from, then the one after each move of it.
    let frames: [String]
    /// The finish's moves, in engine notation: `frames[i + 1]` is `frames[i]` with `moves[i]`.
    let moves: [String]

    /// How many moves (both sides) of each game's end it plays.
    static let finish = 7

    /// The name it is known by ("The Opera Game"), or the players.
    var title: String {
        name ?? "\(Self.surname(game.white)) – \(Self.surname(game.black))"
    }

    /// What happens in it: the blurb after the name.
    var story: String {
        guard name != nil, let colon = game.blurb.firstIndex(of: ":") else { return game.blurb }
        let rest: String = game.blurb[game.blurb.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    /// The name before the blurb's colon, when it has a short one.
    private var name: String? {
        guard let colon = game.blurb.firstIndex(of: ":") else { return nil }
        let name = String(game.blurb[..<colon])
        return name.count <= 34 ? name : nil
    }

    /// "Morphy v Duke Karl & Count Isouard · 1858".
    var players: String {
        let year: String = game.year > 0 ? " · \(game.year)" : ""
        return "\(Self.surname(game.white)) v \(Self.surname(game.black))\(year)"
    }

    /// The winner plays toward the camera.
    var flipped: Bool { game.result == "0-1" }

    /// Today's game, the same all day, a new one at midnight.
    static func of(_ date: Date = .now, games: [ClassicGame] = GrandmasterContent.shared.games,
                   calendar: Calendar = .current) -> HomeMasterpiece? {
        let playable: [ClassicGame] = games.filter { $0.moves.count > finish }
        guard !playable.isEmpty else { return nil }
        let day: Int = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return HomeMasterpiece(playable[day % playable.count])
    }

    init?(_ game: ClassicGame) {
        guard var board = TrainingChess.board(after: [], from: Position.standard.fen) else { return nil }
        var day: [String] = [board.position.fen]
        for uci in game.moves {
            guard TrainingChess.play(uci, on: &board) != nil else { return nil }
            day.append(board.position.fen)
        }
        let count: Int = min(Self.finish, game.moves.count)
        self.game = game
        self.dayFrames = day
        self.frames = Array(day.suffix(count + 1))
        self.moves = Array(game.moves.suffix(count))
    }

    // MARK: The game across the day

    /// The whole game from the opening position, one frame after each move: the Home board plays
    /// it across the day, a full set in the morning and the famous finish by night (Alex,
    /// 2026-11-11: "throughout each day pieces fall").
    let dayFrames: [String]

    /// The day's game starts at 7 am and reaches its last move at 11 pm.
    static let dayStarts: TimeInterval = 7 * 3600
    static let dayEnds: TimeInterval = 23 * 3600

    /// How far into the game the board is at `date`: 0 (the opening position) before 7 am, the
    /// last move from 11 pm, evenly between.
    func dayFrame(at date: Date = .now, calendar: Calendar = .current) -> Int {
        let last: Int = dayFrames.count - 1
        let seconds: TimeInterval = date.timeIntervalSince(calendar.startOfDay(for: date))
        let progress: Double = (seconds - Self.dayStarts) / (Self.dayEnds - Self.dayStarts)
        return min(max(Int((progress * Double(last)).rounded(.down)), 0), last)
    }

    /// "Morphy" from "Paul Morphy"; names that are more than a person's stay whole.
    private static func surname(_ name: String) -> String {
        if name.contains("&") || name.contains("Deep Blue") { return name }
        return name.split(separator: " ").last.map(String.init) ?? name
    }
}

/// Today's masterpiece as a tile: the finish plays on a small board, a move every beat, then
/// holds on the final position and begins again.
struct HomeMasterpieceTile: View {
    let masterpiece: HomeMasterpiece
    let tone: HomeTone
    let pieceTheme: BoardTheme
    let open: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var boardSize: CGFloat = 112
    /// Which frame is on the board.
    @State private var frame = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: HomeMetrics.tileRadius, style: .continuous)
        Button { open(masterpiece.frames[0]) } label: {
            HStack(alignment: .center, spacing: 14) {
                board
                VStack(alignment: .leading, spacing: 4) {
                    Text("Masterpiece of the day")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(tone.metal)
                    Text(masterpiece.title)
                        .font(.app(.headline))
                        .foregroundStyle(tone.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(masterpiece.players)
                        .font(.app(.footnote))
                        .foregroundStyle(tone.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(masterpiece.story)
                        .font(.app(.footnote))
                        .foregroundStyle(tone.ink2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        Text("Play it through")
                        Image(systemName: "chevron.forward")
                            .font(.app(.caption2, weight: .bold))
                    }
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(tone.metal)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(alignment: .topLeading) {
                HomeTileGlow(color: tone.metal, strength: 0.28)
                    .offset(x: -50, y: -60)
            }
            .clipShape(shape)
            .homePane(shape, tone: tone)
            .contentShape(shape)
        }
        .buttonStyle(HomeLiftStyle(tone: tone))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Masterpiece of the day: \(masterpiece.title)")
        .accessibilityValue("\(masterpiece.players). \(masterpiece.story)")
        .accessibilityHint("Opens its finish in Analyze, to play through")
        .accessibilityAddTraits(.isButton)
        .task(id: masterpiece.game.id) { await play() }
    }

    private var board: some View {
        let size: CGFloat = min(boardSize, 140)
        let shown: Int = min(frame, masterpiece.frames.count - 1)
        var marked: Set<Square> = []
        if shown > 0, let squares = Notation.squares(of: masterpiece.moves[shown - 1]) {
            marked = [squares.from, squares.to]
        }
        return HomeMiniBoard(fen: masterpiece.frames[shown], flipped: masterpiece.flipped, theme: pieceTheme,
                             tone: tone, lit: true, marked: marked)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            .animation(.easeInOut(duration: 0.3), value: shown)
    }

    /// Plays the finish, holds the final position, and begins again; with reduced motion it
    /// shows the final position and stays.
    private func play() async {
        let last: Int = masterpiece.frames.count - 1
        guard !reduceMotion else {
            frame = last
            return
        }
        frame = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(frame == 0 ? 1.6 : 1.1))
            if Task.isCancelled { return }
            if frame >= last {
                try? await Task.sleep(for: .seconds(2.4))
                if Task.isCancelled { return }
                frame = 0
            } else {
                frame += 1
            }
        }
    }
}
