import ChessKit
import SwiftUI

/// Coordinates: a square is named and the player taps it on a board with no letters or
/// numbers on it. Thirty seconds, as many as they can, from White's side or Black's.
struct CoordinatesView: View {
    let theme: BoardTheme
    @State private var drill: CoordinatesDrill
    @Environment(\.dismiss) private var dismiss
    @AppStorage("haptics") private var hapticsOn = true

    init(theme: BoardTheme) {
        self.init(theme: theme, drill: CoordinatesDrill(store: .live()))
    }

    /// A drill already set up, for tests and pictures.
    init(theme: BoardTheme, drill: CoordinatesDrill) {
        self.theme = theme
        _drill = State(initialValue: drill)
    }

    var body: some View {
        GeometryReader { geo in
            let boardSide = max(200, min(geo.size.width - 32, geo.size.height * 0.47, 560))
            VStack(spacing: 0) {
                RoomHeader(title: "Coordinates", subtitle: subtitle) { close() }
                ScrollView {
                    VStack(spacing: 14) {
                        stage
                        VisionBoard(theme: theme, flipped: drill.side == .black, flashes: drill.flashes,
                                    onTap: drill.phase == .playing ? { (square: Square) in drill.tap(square) } : nil)
                            .frame(width: boardSide, height: boardSide)
                        if drill.phase == .finished {
                            RoomMessage(text: drill.message(sideName: sideName), tone: tone, theme: theme)
                                .padding(.horizontal, 16)
                        } else {
                            orientation
                        }
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                if drill.phase == .ready || drill.phase == .finished {
                    footer
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background { TrainingBackdrop(theme: theme) }
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .tint(theme.trainingAccent)
        .animation(.snappy(duration: 0.25), value: drill.phase)
        .sensoryFeedback(.selection, trigger: drill.round.score) { old, new in hapticsOn && new > old }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.7), trigger: drill.round.misses) { old, new in
            hapticsOn && new > old
        }
        .sensoryFeedback(.impact(weight: .light), trigger: drill.phase) { _, new in hapticsOn && new != .ready }
        .onDisappear { drill.stop() }
    }

    // MARK: Pieces of the screen

    private var sideName: String { theme.name(of: drill.side) }

    private var subtitle: String {
        switch drill.phase {
        case .ready, .finished: return "Know every square at a glance"
        case .countdown, .playing: return "Playing as \(sideName)"
        }
    }

    private var tone: DrillRunner.Tone {
        drill.phase == .finished && drill.newBest ? .success : .coach
    }

    /// Above the board: Coach Leo before a round, then the countdown, the square to find,
    /// and the score. Always the same height, so the board stays put.
    private var stage: some View {
        Group {
            switch drill.phase {
            case .ready:
                RoomMessage(text: drill.message(sideName: sideName), tone: .coach, theme: theme)
            case .countdown(let count):
                Text("\(count)")
                    .font(.system(size: 64, weight: .bold, design: .themed).monospacedDigit())
                    .foregroundStyle(theme.trainingAccent)
                    .id(count)
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
                    .accessibilityLabel("Starting in \(count)")
            case .playing:
                playing
            case .finished:
                result
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .padding(.horizontal, 16)
    }

    /// During a round: the clock, the score, the square to find and, smaller, the one after it.
    private var playing: some View {
        let round = drill.round
        return VStack(spacing: 6) {
            HStack {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let left = round.timeLeft(at: context.date)
                    Label("\(Int(left.rounded(.up)))", systemImage: "timer")
                        .foregroundStyle(left <= 5 ? TrainingColor.red.color(on: theme) : Color.secondary)
                        .accessibilityLabel("\(Int(left.rounded(.up))) seconds left")
                }
                Spacer()
                Label("\(round.score)", systemImage: "checkmark")
                    .foregroundStyle(theme.trainingAccent)
                    .contentTransition(.numericText(value: Double(round.score)))
                    .accessibilityLabel("\(round.score) found")
            }
            .font(.system(.headline, design: .themed).monospacedDigit())
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(round.target.notation)
                    .font(.system(size: 64, weight: .bold, design: .themed).monospacedDigit())
                Text(round.upcoming.notation)
                    .font(.system(size: 26, weight: .semibold, design: .themed).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .opacity(0.7)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Find \(round.target.notation). Next, \(round.upcoming.notation).")
        }
    }

    /// After a round: the score, and a new best when it is one.
    private var result: some View {
        let round = drill.round
        return VStack(spacing: 6) {
            Text("\(round.score)")
                .font(.system(size: 64, weight: .bold, design: .themed).monospacedDigit())
                .foregroundStyle(theme.trainingAccent)
            HStack(spacing: 8) {
                Text(round.score == 1 ? "square in 30 seconds" : "squares in 30 seconds")
                    .font(.system(.subheadline, design: .themed))
                    .foregroundStyle(.secondary)
                if drill.newBest {
                    TrainingChip(text: "New best", symbol: "star.fill", color: theme.trainingAccent)
                }
            }
            if round.misses > 0, let accuracy = round.accuracy {
                Text("\(accuracy)% of your taps were right")
                    .font(.system(.footnote, design: .themed))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Which side is at the bottom: on a board with no letters, the only clue.
    private var orientation: some View {
        HStack(spacing: 6) {
            PieceImage(piece: Piece(.king, color: drill.side, square: .e1), theme: theme, size: 20)
                .accessibilityHidden(true)
            Text("\(sideName) at the bottom")
                .font(.system(.footnote, design: .themed).weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Before and after a round: which side to play, and Start.
    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                sideButton(.white)
                sideButton(.black)
            }
            Button {
                drill.start()
            } label: {
                Label(drill.phase == .finished ? "Again" : "Start",
                      systemImage: drill.phase == .finished ? "arrow.counterclockwise" : "play.fill")
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func sideButton(_ side: Piece.Color) -> some View {
        let selected = drill.side == side
        let best = drill.store.coordinatesBest(as: side)
        let record = best > 0 ? "Best \(best)" : "No score yet"
        let accent = theme.trainingAccent
        return Button {
            drill.choose(side)
        } label: {
            HStack(spacing: 10) {
                PieceImage(piece: Piece(.king, color: side, square: side == .white ? .e1 : .e8), theme: theme, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.name(of: side))
                        .font(.system(.subheadline, design: .themed).weight(.semibold))
                        .lineLimit(1)
                    Text(record)
                        .font(.system(.caption, design: .themed).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? accent : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .trainingCard(theme, tint: selected ? accent : nil, cornerRadius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play as \(theme.name(of: side)). \(record)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func close() {
        drill.stop()
        dismiss()
    }
}
