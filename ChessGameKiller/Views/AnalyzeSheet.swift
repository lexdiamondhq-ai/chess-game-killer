import ChessKit
import PhotosUI
import SwiftUI

/// The analyzer: start from a photo, a screenshot, an empty board or the
/// current game, fix the position, then see Stockfish's two best moves.
struct AnalyzeSheet: View {
    let theme: BoardTheme
    let currentFEN: String
    let engine: ChessEngine?
    let onPlay: (PositionDraft) -> Void

    @State private var session: ScanSession
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @Environment(\.dismiss) private var dismiss

    init(
        theme: BoardTheme,
        currentFEN: String,
        engine: ChessEngine?,
        reader: BoardReader,
        onPlay: @escaping (PositionDraft) -> Void
    ) {
        self.theme = theme
        self.currentFEN = currentFEN
        self.engine = engine
        self.onPlay = onPlay
        _session = State(initialValue: ScanSession(reader: reader))
    }

    private var accent: Color { theme.accent ?? .accentColor }
    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack(path: $session.path) {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Snap a real board, pick a screenshot or set one up. I'll find the two best moves.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    if hasCamera {
                        Button { showingCamera = true } label: {
                            StartCard(symbol: "camera.fill", title: "Take a Photo",
                                      detail: "Point your camera at a real board", theme: theme)
                        }
                        .buttonStyle(.plain)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        StartCard(symbol: "photo.on.rectangle.angled", title: "Choose a Photo",
                                  detail: "A picture or a screenshot of a board", theme: theme)
                    }
                    .buttonStyle(.plain)
                    Button { session.setUpByHand() } label: {
                        StartCard(symbol: "square.grid.3x3.fill", title: "Set Up a Board",
                                  detail: "Place the pieces yourself", theme: theme)
                    }
                    .buttonStyle(.plain)
                    Button { session.analyze(fen: currentFEN) } label: {
                        StartCard(symbol: "arrow.triangle.branch", title: "This Game",
                                  detail: "Analyze the position on your board now", theme: theme)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationTitle("Analyze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(for: ScanSession.Step.self) { step in
                switch step {
                case .editor:
                    BoardEditorView(session: session, theme: theme)
                case .analysis:
                    AnalysisView(draft: session.draft, theme: theme, engine: engine) { draft in
                        onPlay(draft)
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    session.read(image)
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in session.read(image) }
                .ignoresSafeArea()
        }
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(theme.accent ?? .accentColor)
                .frame(width: 44, height: 44)
                .background((theme.accent ?? .accentColor).opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Panel(theme: theme))
        .contentShape(Rectangle())
    }
}

/// The rounded glass panel used across the analyzer.
struct Panel: View {
    let theme: BoardTheme
    var highlight: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        shape
            .fill(theme.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            .overlay {
                shape.strokeBorder(highlight ?? Color.secondary.opacity(theme.isDark ? 0.25 : 0.12),
                                   lineWidth: highlight == nil ? 1 : 2)
            }
            .shadow(color: theme.glows ? (highlight ?? .clear).opacity(0.45) : .black.opacity(0.06),
                    radius: theme.glows ? 10 : 6, y: theme.glows ? 0 : 2)
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
        session.draft.problems.first?.message(white: theme.whiteName, black: theme.blackName)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if session.photo != nil || session.isReading {
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

                Picker("Turn", selection: $session.draft.sideToMove) {
                    Text("\(theme.whiteName) to move").tag(Piece.Color.white)
                    Text("\(theme.blackName) to move").tag(Piece.Color.black)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    editButton("Turn Board", symbol: "arrow.triangle.2.circlepath") { session.draft.rotate() }
                    editButton("Clear", symbol: "trash") { session.draft.clear() }
                    editButton("Start", symbol: "arrow.counterclockwise") {
                        let turn = session.draft.sideToMove
                        session.draft = .standard
                        session.draft.sideToMove = turn
                    }
                }

                if let problem, !session.isReading {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex: 0xFF9A3C))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(16)
            .animation(.snappy, value: problem)
        }
        .navigationTitle("Set Up Position")
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
                    .font(.headline)
                Text(session.isReading ? "This takes a few seconds." : session.readingNote ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Panel(theme: theme, highlight: session.readingFailed ? Color(hex: 0xFF9A3C) : nil))
    }

    private var palette: some View {
        VStack(spacing: 8) {
            ForEach([Piece.Color.white, .black], id: \.self) { color in
                HStack(spacing: 6) {
                    ForEach([Piece.Kind.king, .queen, .rook, .bishop, .knight, .pawn], id: \.self) { kind in
                        let token = PositionDraft.Token(kind, color)
                        toolButton(.piece(token)) {
                            PieceImage(piece: token.piece(at: .a1), theme: theme, size: 40)
                        }
                        .accessibilityLabel("\(color == .white ? theme.whiteName : theme.blackName) \(String(describing: kind))")
                    }
                    if color == .white {
                        toolButton(.eraser) {
                            Image(systemName: "eraser.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, height: 40)
                        }
                        .accessibilityLabel("Eraser")
                    } else {
                        Color.clear.frame(width: 48, height: 48)
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
                .frame(width: 48, height: 48)
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
                .font(.subheadline.weight(.medium))
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
    let onPlay: (PositionDraft) -> Void

    @State private var model: AnalysisModel
    @State private var flipped: Bool

    init(draft: PositionDraft, theme: BoardTheme, engine: ChessEngine?, onPlay: @escaping (PositionDraft) -> Void) {
        self.theme = theme
        self.onPlay = onPlay
        _model = State(initialValue: AnalysisModel(draft: draft, engine: engine))
        _flipped = State(initialValue: draft.sideToMove == .black)
    }

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                PositionBoard(draft: model.draft, theme: theme, flipped: flipped, hints: model.hints)
                    .animation(.snappy(duration: 0.4), value: flipped)
                lines
                Button {
                    onPlay(model.draft)
                } label: {
                    Label("Play From Here", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .foregroundStyle(theme.isDark ? Color.black : Color.white)
                .disabled(model.ending != nil)
            }
            .padding(16)
            .animation(.snappy, value: model.lines)
        }
        .navigationTitle("Best Moves")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { flipped.toggle() } label: {
                    Label("Flip Board", systemImage: "arrow.up.arrow.down")
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
                .font(.title2.weight(.bold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.evaluationForWhite == nil ? "Thinking" : model.verdict(white: theme.whiteName, black: theme.blackName))
                        .font(.headline)
                    Spacer()
                    if let evaluation = model.evaluationForWhite {
                        Text(evaluation.label)
                            .font(.system(.headline, design: .themed).monospacedDigit())
                    }
                }
                EvaluationBar(winningChances: model.evaluationForWhite?.winningChances ?? 0, theme: theme)
            }
        }
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
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if index < model.hints.count {
                                Text(model.hints[index].san)
                                    .font(.system(.headline, design: .themed))
                            }
                            Spacer()
                            Text(scoreLabel(line))
                                .font(.system(.subheadline, design: .themed).weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(model.readable(line))
                            .font(.footnote)
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
                        Text("Stockfish couldn't look at this position.")
                    } else if model.depth > 0 {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(accent)
                        Text("Stockfish 17, depth \(model.depth)")
                    }
                }
                .font(.footnote)
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
