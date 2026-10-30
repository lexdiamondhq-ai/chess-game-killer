import ChessKit
import PhotosUI
import SwiftUI

/// The analyzer: start from a photo, a screenshot, an empty board or the
/// current game, fix the position, then see Stockfish's two best moves.
struct AnalyzeSheet: View {
    let theme: BoardTheme
    /// The game on the board, if one has started.
    let currentFEN: String?
    let engine: ChessEngine?
    /// Who "Play from here" plays, and on what clock.
    let rival: String
    let clock: TimeControl
    /// The rival of a game that starting another would cost, so the person is asked first.
    let forfeits: String?
    /// Called when the person analyzes a game still being played: that counts as help, like Undo.
    let onAnalyzeGame: (() -> Void)?
    let onPlay: (PositionDraft) -> Void
    /// Opened from the home's Scan a board shortcut: the camera comes up straight away.
    let startsWithCamera: Bool

    @State private var session: ScanSession
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var showingCamera = false
    /// Photo scans run out (3 a week free, 3 a day with Premium): then the offer shows.
    @State private var offer: PremiumFeature?
    @Environment(\.dismiss) private var dismiss

    init(
        theme: BoardTheme,
        currentFEN: String?,
        engine: ChessEngine?,
        reader: BoardReader,
        rival: String,
        clock: TimeControl,
        forfeits: String? = nil,
        onAnalyzeGame: (() -> Void)? = nil,
        startsWithCamera: Bool = false,
        onPlay: @escaping (PositionDraft) -> Void
    ) {
        self.theme = theme
        self.currentFEN = currentFEN
        self.engine = engine
        self.rival = rival
        self.clock = clock
        self.forfeits = forfeits
        self.onAnalyzeGame = onAnalyzeGame
        self.startsWithCamera = startsWithCamera
        self.onPlay = onPlay
        _session = State(initialValue: ScanSession(reader: reader))
    }

    private var accent: Color { theme.accent ?? .accentColor }
    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    /// The game on the board when it has moves to look at (opened from Home there may be none).
    private var gameFEN: String? {
        guard let currentFEN,
              currentFEN.split(separator: " ").first != Position.standard.fen.split(separator: " ").first else { return nil }
        return currentFEN
    }

    private var canScan: Bool { Premium.shared.canUse(.scan) }

    /// The card's line, with the scans left when there's a limit.
    private func scanDetail(_ line: String) -> String {
        guard let left = Premium.shared.remaining(.scan),
              let allowance = Premium.shared.allowance(.scan) else { return line }
        let when: String = allowance.period == .day ? "today" : "this week"
        return left == 0 ? "\(line). No scans left \(when)" : "\(line). \(left) left \(when)"
    }

    /// Reads a picture, if a scan is left; otherwise the offer.
    private func scan(_ image: UIImage) {
        guard Premium.shared.use(.scan) else {
            offer = .scan
            return
        }
        session.read(image)
    }

    var body: some View {
        NavigationStack(path: $session.path) {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Snap a real board, pick a screenshot or set one up. I'll find the two best moves.")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    if hasCamera {
                        Button {
                            if canScan { showingCamera = true } else { offer = .scan }
                        } label: {
                            StartCard(symbol: "camera.fill", title: "Take a photo",
                                      detail: scanDetail("Point your camera at a real board"), theme: theme)
                        }
                        .buttonStyle(.plain)
                    }
                    if canScan {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            StartCard(symbol: "photo.on.rectangle.angled", title: "Choose a photo",
                                      detail: scanDetail("A picture or a screenshot of a board"), theme: theme,
                                      isLoading: isLoadingPhoto)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingPhoto)
                    } else {
                        Button { offer = .scan } label: {
                            StartCard(symbol: "photo.on.rectangle.angled", title: "Choose a photo",
                                      detail: scanDetail("A picture or a screenshot of a board"), theme: theme)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { session.setUpByHand() } label: {
                        StartCard(symbol: "square.grid.3x3.fill", title: "Set up a board",
                                  detail: "Start from the opening position and change it", theme: theme)
                    }
                    .buttonStyle(.plain)
                    if let gameFEN {
                        Button {
                            onAnalyzeGame?()
                            session.analyze(fen: gameFEN)
                        } label: {
                            StartCard(symbol: Glyphs.analyze, title: "This game",
                                      detail: onAnalyzeGame == nil
                                          ? "The position in your game right now"
                                          : "Your game as it stands. Counts as help, like Undo.",
                                      theme: theme)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Analyze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(for: ScanSession.Step.self) { step in
                switch step {
                case .editor:
                    BoardEditorView(session: session, theme: theme)
                case .analysis:
                    AnalysisView(draft: session.draft, theme: theme, engine: engine,
                                 rival: rival, clock: clock, forfeits: forfeits) { draft in
                        onPlay(draft)
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                // Loading can mean an iCloud download, so show that something is happening.
                isLoadingPhoto = true
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    scan(image)
                } else {
                    session.failToLoadPhoto()
                }
                isLoadingPhoto = false
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in scan(image) }
                .ignoresSafeArea()
        }
        .task {
            // Scan a board: the camera once the sheet is up (or the offer, with no scans left).
            guard startsWithCamera, hasCamera else { return }
            try? await Task.sleep(for: .milliseconds(450))
            if canScan { showingCamera = true } else { offer = .scan }
        }
        .premiumOffer($offer)
        .tint(accent)
        .presentationBackground {
            ThemeBackdrop(theme: theme)
        }
        .preferredColorScheme(theme.isDark ? .dark : nil)
    }
}

/// A big tappable row on the analyzer's first screen.
private struct StartCard: View {
    let symbol: String
    let title: String
    let detail: String
    let theme: BoardTheme
    var isLoading = false

    var body: some View {
        HStack(spacing: 14) {
            Glyph(name: symbol, size: 28)
                .foregroundStyle(theme.accent ?? .accentColor)
                .frame(width: 44, height: 44)
                .background((theme.accent ?? .accentColor).opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.headline))
                Text(detail).font(.app(.subheadline)).foregroundStyle(.secondary)
            }
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Panel(theme: theme))
        .contentShape(Rectangle())
    }
}

/// The rounded glass panel used across the analyzer, outlined in color to draw the eye.
struct Panel: View {
    let theme: BoardTheme
    var highlight: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        GlassSurface(shape: shape)
            .overlay {
                if let highlight {
                    shape.strokeBorder(highlight, lineWidth: 1.5)
                        .shadow(color: highlight.opacity(theme.glows ? 0.45 : 0), radius: 10)
                }
            }
    }
}

// MARK: - Editor

/// Fix up the position: tap a piece below, then tap squares to place it.
struct BoardEditorView: View {
    @Bindable var session: ScanSession
    let theme: BoardTheme

    private enum Tool: Hashable {
        case piece(PositionDraft.Token)
        case eraser
    }

    @State private var tool: Tool = .piece(.init(.pawn, .white))
    @State private var showingPhoto = false

    private var accent: Color { theme.accent ?? .accentColor }
    private var problem: String? {
        session.draft.problems.first?.message(white: "White", black: "Black")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if session.photo != nil || session.isReading || session.readingFailed {
                    readingBanner
                }

                PositionBoard(draft: session.draft, theme: theme) { square in
                    place(on: square)
                }
                .overlay {
                    if session.isReading {
                        ProgressView("Reading the board")
                            .padding(16)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .disabled(session.isReading)

                palette

                // What the reader finds replaces the whole draft, so hold edits until it's done.
                Picker("Turn", selection: $session.draft.sideToMove) {
                    Text("White to move").tag(Piece.Color.white)
                    Text("Black to move").tag(Piece.Color.black)
                }
                .pickerStyle(.segmented)
                .disabled(session.isReading)

                HStack(spacing: 10) {
                    // Turns the pieces around, for a photo taken from the other side of the board.
                    editButton("Rotate", symbol: "rotate.right") { session.draft.rotate() }
                        .accessibilityLabel("Rotate the board")
                    editButton("Clear", symbol: "trash") { session.draft.clear() }
                        .accessibilityLabel("Clear the board")
                    editButton("Reset", symbol: "arrow.counterclockwise") {
                        let turn = session.draft.sideToMove
                        session.draft = .standard
                        session.draft.sideToMove = turn
                    }
                    .accessibilityLabel("Reset to the starting position")
                }
                .disabled(session.isReading)

                if let problem, !session.isReading {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.subheadline, weight: .medium))
                        .foregroundStyle(Color(hex: 0xFF9A3C))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(16)
            .animation(.snappy, value: problem)
        }
        .navigationTitle("Set up position")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Analyze") { session.path.append(.analysis) }
                    .fontWeight(.semibold)
                    .disabled(!session.draft.isValid || session.isReading)
            }
        }
        .sheet(isPresented: $showingPhoto) {
            if let photo = session.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var readingBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            if let photo = session.photo {
                Button { showingPhoto = true } label: {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show your photo")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(session.isReading ? "Reading your photo" : session.readingFailed ? "Couldn't read it" : "Board read")
                    .font(.app(.headline))
                Text(session.isReading ? "I'm checking every square. This can take up to a minute." : session.readingNote ?? "")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if session.isReading {
                Button("Stop") { withAnimation(.snappy) { session.stopReading() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Stop reading the photo")
            }
        }
        .padding(12)
        .background(Panel(theme: theme, highlight: session.readingFailed ? Color(hex: 0xFF9A3C) : nil))
    }

    private var palette: some View {
        VStack(spacing: 8) {
            ForEach([Piece.Color.white, .black], id: \.self) { color in
                HStack(spacing: 4) {
                    ForEach([Piece.Kind.king, .queen, .rook, .bishop, .knight, .pawn], id: \.self) { kind in
                        let token = PositionDraft.Token(kind, color)
                        toolButton(.piece(token)) {
                            PieceImage(piece: token.piece(at: .a1), theme: theme, size: 36)
                        }
                        .accessibilityLabel("\(color == .white ? "White" : "Black") \(String(describing: kind))")
                    }
                    if color == .white {
                        toolButton(.eraser) {
                            Image(systemName: "eraser.fill")
                                .font(.app(.title3))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                        }
                        .accessibilityLabel("Eraser")
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func toolButton<Content: View>(_ option: Tool, @ViewBuilder label: () -> Content) -> some View {
        let isSelected = tool == option
        return Button {
            tool = option
        } label: {
            label()
                .frame(width: 44, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? accent.opacity(0.22) : Color.secondary.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? accent : .clear, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func editButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Label(title, systemImage: symbol)
                .font(.app(.subheadline, weight: .medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    /// Places the chosen piece, or takes it off if it's already there.
    private func place(on square: Square) {
        withAnimation(.snappy(duration: 0.2)) {
            switch tool {
            case .eraser:
                session.draft[square] = nil
            case .piece(let token):
                session.draft[square] = session.draft[square] == token ? nil : token
            }
        }
    }
}

// MARK: - Analysis

/// Stockfish's two best moves for the position, drawn as arrows, with what follows.
struct AnalysisView: View {
    let theme: BoardTheme
    /// Who "Play from here" plays, and on what clock.
    var rival = "the computer"
    var clock: TimeControl = .unlimited
    /// The rival of a game in progress that starting this one would cost.
    var forfeits: String?
    let onPlay: (PositionDraft) -> Void

    @State private var model: AnalysisModel
    @State private var flipped: Bool
    @State private var confirmingForfeit = false

    init(draft: PositionDraft, theme: BoardTheme, engine: ChessEngine?, rival: String = "the computer",
         clock: TimeControl = .unlimited, forfeits: String? = nil, onPlay: @escaping (PositionDraft) -> Void) {
        self.theme = theme
        self.rival = rival
        self.clock = clock
        self.forfeits = forfeits
        self.onPlay = onPlay
        _model = State(initialValue: AnalysisModel(draft: draft, engine: engine))
        _flipped = State(initialValue: draft.sideToMove == .black)
    }

    /// The side the person takes from here: the one to move.
    private var sideName: String { model.draft.sideToMove == .white ? "White" : "Black" }

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                PositionBoard(draft: model.draft, theme: theme, flipped: flipped, hints: model.hints)
                    .animation(.snappy(duration: 0.4), value: flipped)
                lines
                VStack(spacing: 6) {
                    Button {
                        if forfeits == nil { onPlay(model.draft) } else { confirmingForfeit = true }
                    } label: {
                        Label("Play \(rival) from here", systemImage: "play.fill")
                            .font(.app(.headline))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .foregroundStyle(theme.isDark ? Color.black : Color.white)
                    .disabled(model.ending != nil || model.draft.position == nil)
                    Text("You play \(sideName) · \(clock.isTimed ? clock.name : "no clock")")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                }
                .confirmationDialog("Leave your game against \(forfeits ?? rival)?",
                                    isPresented: $confirmingForfeit, titleVisibility: .visible) {
                    Button("Resign and play \(rival)", role: .destructive) { onPlay(model.draft) }
                    Button("Keep playing", role: .cancel) {}
                } message: {
                    Text("It counts as a loss for your army.")
                }
            }
            .padding(16)
            .animation(.snappy, value: model.lines)
        }
        .navigationTitle("Best moves")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { flipped.toggle() } label: {
                    Label {
                        Text("Flip board")
                    } icon: {
                        Glyph(name: Glyphs.flip, size: 24)
                    }
                }
            }
        }
        .task { await model.run() }
    }

    // MARK: Who's better

    @ViewBuilder
    private var header: some View {
        if let ending = model.ending {
            Text(ending)
                .font(.app(.title2, weight: .bold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(headline)
                        .font(.app(.headline))
                    Spacer()
                    if let evaluation = model.evaluationForWhite {
                        Text(evaluation.label)
                            .font(.app(.headline).monospacedDigit())
                    }
                }
                EvaluationBar(winningChances: model.evaluationForWhite?.winningChances ?? 0, theme: theme)
            }
        }
    }

    /// The verdict, or why there isn't one.
    private var headline: String {
        if model.evaluationForWhite != nil {
            return model.verdict(white: "White", black: "Black")
        }
        if model.failed {
            return model.draft.problems.first?.message(white: "White", black: "Black") ?? "Couldn't evaluate this position"
        }
        return "Thinking"
    }

    // MARK: The two lines

    @ViewBuilder
    private var lines: some View {
        if model.ending == nil {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(model.lines.prefix(2).enumerated()), id: \.offset) { index, line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            ArrowSample(color: index == 0 ? theme.bestArrow : theme.secondArrow, dashed: index != 0)
                            Text(index == 0 ? "Best" : "Next best")
                                .font(.app(.subheadline))
                                .foregroundStyle(.secondary)
                            if index < model.hints.count {
                                Text(model.hints[index].san)
                                    .font(.app(.headline))
                            }
                            Spacer()
                            Text(scoreLabel(line))
                                .font(.app(.subheadline, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(model.readable(line))
                            .font(.app(.footnote))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                HStack(spacing: 8) {
                    if model.isThinking {
                        ProgressView().controlSize(.small)
                        Text(model.depth == 0 ? "Stockfish is thinking" : "Looking deeper")
                    } else if model.failed {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("The engine didn't answer. Go back and try again.")
                    } else if model.depth > 0 {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(accent)
                        Text("Checked by Stockfish 17")
                    }
                }
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Panel(theme: theme))
        }
    }

    private func scoreLabel(_ line: EngineLine) -> String {
        (model.draft.sideToMove == .white ? line.evaluation : line.evaluation.flipped).label
    }
}

/// A bar split between the two sides by how likely each is to win.
struct EvaluationBar: View {
    let winningChances: Double
    let theme: BoardTheme

    var body: some View {
        GeometryReader { geo in
            let share = CGFloat((winningChances + 1) / 2)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.blackSide.opacity(theme.isDark ? 0.85 : 1))
                Capsule()
                    .fill(theme.whiteSide)
                    .frame(width: max(8, geo.size.width * share))
                    .shadow(color: theme.glows ? theme.whiteSide.opacity(0.7) : .clear, radius: 6)
            }
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5))
        }
        .frame(height: 10)
        .animation(.snappy(duration: 0.5), value: winningChances)
        .accessibilityHidden(true)
    }
}

// MARK: - Camera

/// The system camera, for snapping a real board.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
