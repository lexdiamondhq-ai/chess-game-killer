import ChessKit
import PhotosUI
import SwiftUI

/// The analyzer, where every Analyze button opens: start from a photo, a screenshot, an empty
/// board or the current game, then see Stockfish's two best moves and play them out.
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

    /// The app's one session, so the board is still there when Analyze opens again.
    @Bindable var session: ScanSession
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var showingCamera = false
    /// Photo scans run out (3 a week free; Premium only meets a high fair-use guard): then the offer shows.
    @State private var offer: PremiumFeature?
    @Environment(\.dismiss) private var dismiss

    init(
        theme: BoardTheme,
        currentFEN: String?,
        engine: ChessEngine?,
        session: ScanSession,
        rival: String,
        clock: TimeControl,
        forfeits: String? = nil,
        onAnalyzeGame: (() -> Void)? = nil,
        onPlay: @escaping (PositionDraft) -> Void
    ) {
        self.theme = theme
        self.currentFEN = currentFEN
        self.engine = engine
        self.rival = rival
        self.clock = clock
        self.forfeits = forfeits
        self.onAnalyzeGame = onAnalyzeGame
        self.onPlay = onPlay
        self.session = session
    }

    private var accent: Color { theme.trainingAccent }
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
        // Premium feels unlimited: no countdown, the fair-use guard only speaks if it's reached.
        if Premium.shared.isPremium, Premium.shared.canUse(.scan) { return line }
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
                    Text("Snap a real board, pick a screenshot or set one up. I'll find the best moves, and you can play them out.")
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
                destination(step)
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
        .premiumOffer($offer)
        .tint(accent)
        .presentationBackground {
            TrainingBackdrop(theme: theme)
        }
        .screenScheme(theme)
    }
}

extension AnalyzeSheet {
    @ViewBuilder
    fileprivate func destination(_ step: ScanSession.Step) -> some View {
        switch step {
        case .reading:
            PhotoReadingView(session: session, theme: theme)
        case .editor:
            BoardEditorView(session: session, theme: theme)
        case .analysis:
            // A photo's analysis can open the editor to fix a piece; coming back starts it over.
            AnalysisView(draft: session.analyzed, theme: theme, engine: engine, model: session.analysis,
                         rival: rival, clock: clock, forfeits: forfeits,
                         photo: session.photo, photoDoubts: session.photoDoubts,
                         onEditPieces: { session.editPieces($0) },
                         onSwitchTurn: { session.switchTurn(of: $0) },
                         photoButtons: photoButtons) { draft in
                onPlay(draft)
                dismiss()
            }
            .id(session.analysisRun)
        }
    }

    /// Take a photo and Upload a photo, lower right on the analysis, so a new board can come in
    /// from there without going back (Alex, 2026-11-08). Same scans and limit as the first screen.
    fileprivate var photoButtons: AnalysisPhotoButtons {
        AnalysisPhotoButtons(hasCamera: hasCamera, canScan: canScan, item: $photoItem,
                             isLoading: isLoadingPhoto) {
            if canScan { showingCamera = true } else { offer = .scan }
        } onNoScans: {
            offer = .scan
        }
    }
}

/// The analysis's two photo buttons: the camera, and a picture or screenshot from Photos.
/// Either one reads the new board and opens its analysis, as from the analyzer's first screen.
struct AnalysisPhotoButtons: View {
    let hasCamera: Bool
    let canScan: Bool
    @Binding var item: PhotosPickerItem?
    let isLoading: Bool
    let onCamera: () -> Void
    let onNoScans: () -> Void

    var body: some View {
        if hasCamera {
            Button(action: onCamera) {
                Label("Take a photo", systemImage: "camera")
            }
            .accessibilityHint("Snap a real board to analyze it")
        }
        if canScan {
            PhotosPicker(selection: $item, matching: .images) {
                Label("Upload a photo", systemImage: "photo.on.rectangle")
            }
            .disabled(isLoading)
            .accessibilityHint("A picture or a screenshot of a board, to analyze it")
        } else {
            Button(action: onNoScans) {
                Label("Upload a photo", systemImage: "photo.on.rectangle")
            }
        }
    }
}

/// One half of the analysis's photo pill, lower right.
private struct PhotoPillStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(.title3, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 58, height: 46)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
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
                .foregroundStyle(theme.trainingAccent)
                .frame(width: 44, height: 44)
                .background(theme.trainingAccent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

// MARK: - Reading

/// While the reader checks every square: the Gilded knight drawn in light on a glass card,
/// "Processing" below (KnightLoadingView, Alex 2026-11-10). Its analysis follows by itself;
/// Stop goes to the editor to set the pieces by hand.
struct PhotoReadingView: View {
    let session: ScanSession
    let theme: BoardTheme

    var body: some View {
        KnightLoadingView()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stop") { withAnimation(.snappy) { session.stopReading() } }
                        .accessibilityLabel("Stop reading the photo")
                        .accessibilityHint("Then set up the pieces by hand")
                }
            }
            // Backing out while it's read drops the read, so its analysis can't open later.
            .onDisappear { session.leaveReading() }
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
    @AppStorage("sculpted3D") private var sculpted3D = true
    @AppStorage(BoardTilt.storageKey) private var tilt = BoardTilt.tilted

    private var accent: Color { theme.trainingAccent }
    private var problem: String? {
        session.draft.problems.first?.message(white: "White", black: "Black")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if session.photo != nil || session.readingFailed {
                    readingBanner
                }

                board

                palette

                Picker("Turn", selection: $session.draft.sideToMove) {
                    Text("White to move").tag(Piece.Color.white)
                    Text("Black to move").tag(Piece.Color.black)
                }
                .pickerStyle(.segmented)

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

                if let problem {
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
                Button("Analyze") { session.analyzeDraft() }
                    .fontWeight(.semibold)
                    .disabled(!session.draft.isValid)
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
                Text(session.readingFailed ? "Couldn't read it" : "Your photo")
                    .font(.app(.headline))
                if let note = session.readingNote {
                    Text(note)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Panel(theme: theme, highlight: session.readingFailed ? Color(hex: 0xFF9A3C) : nil))
    }

    /// The same board as the analysis and the games: the real 3D board, tilted or flat from above,
    /// with the Tilted / Flat switch under it, when the look has one and 3D pieces are on;
    /// otherwise the flat board. A tap on a square places the chosen piece, as before.
    @ViewBuilder
    private var board: some View {
        if BoardView.playsIn3D(theme, setting: sculpted3D) {
            VStack(spacing: 6) {
                SculptedPositionBoard(pieces: session.draft.pieces, theme: theme,
                                      onTap: { square in place(on: square) },
                                      framing: tilt.framing)
                    .aspectRatio(tilt == .tilted ? CGFloat(SculptedCamera.snugAspect(tilt: AnalysisView.analysisTilt)) : tilt.framing.aspect,
                                 contentMode: .fit)
                    .padding(.horizontal, -16)
                HStack {
                    Spacer(minLength: 0)
                    BoardViewSwitch(theme: theme)
                }
            }
        } else {
            PositionBoard(draft: session.draft, theme: theme) { square in
                place(on: square)
            }
        }
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

/// Stockfish's two best moves for the position, drawn as arrows, on a board to explore: move
/// any piece and see the best answer, step through the moves, or play out the best line.
struct AnalysisView: View {
    let theme: BoardTheme
    /// Who "Play from here" plays, and on what clock.
    var rival = "the computer"
    var clock: TimeControl = .unlimited
    /// The rival of a game in progress that starting this one would cost.
    var forfeits: String?
    /// The photo the position was read from, and what the reader wasn't sure of.
    var photo: UIImage?
    var photoDoubts: String?
    /// Opens the editor on the board's pieces, to fix one the reader got wrong. Offered with the photo.
    var onEditPieces: ((PositionDraft) -> Void)?
    /// Gives the board's position to the other side to move, for a fresh analysis.
    var onSwitchTurn: ((PositionDraft) -> Void)?
    /// Take a photo and Upload a photo, for a new board, when the analyzer offers them.
    var photoButtons: AnalysisPhotoButtons?
    let onPlay: (PositionDraft) -> Void

    @State private var model: AnalysisModel
    @State private var flipped: Bool
    @State private var showingPhoto = false
    @State private var showingHelp = false
    @AppStorage("haptics") private var hapticsOn = true
    @AppStorage("sculpted3D") private var sculpted3D = true
    @AppStorage(BoardTilt.storageKey) private var tilt = BoardTilt.tilted

    /// `model` is the board to pick up where it was left, when there is one.
    init(draft: PositionDraft, theme: BoardTheme, engine: ChessEngine?, model: AnalysisModel? = nil,
         rival: String = "the computer",
         clock: TimeControl = .unlimited, forfeits: String? = nil,
         photo: UIImage? = nil, photoDoubts: String? = nil, onEditPieces: ((PositionDraft) -> Void)? = nil,
         onSwitchTurn: ((PositionDraft) -> Void)? = nil,
         photoButtons: AnalysisPhotoButtons? = nil,
         onPlay: @escaping (PositionDraft) -> Void) {
        self.theme = theme
        self.rival = rival
        self.clock = clock
        self.forfeits = forfeits
        self.photo = photo
        self.photoDoubts = photoDoubts
        self.onEditPieces = onEditPieces
        self.onSwitchTurn = onSwitchTurn
        self.photoButtons = photoButtons
        self.onPlay = onPlay
        let sounds: SoundPlaying? = engine == nil ? nil : SoundPlayer.shared
        _model = State(initialValue: model ?? AnalysisModel(draft: draft, engine: engine, sounds: sounds))
        _flipped = State(initialValue: draft.sideToMove == .black)
    }

    /// A board already part way through, for pictures in the tests.
    init(model: AnalysisModel, theme: BoardTheme, photo: UIImage? = nil, photoDoubts: String? = nil,
         onEditPieces: ((PositionDraft) -> Void)? = nil, onSwitchTurn: ((PositionDraft) -> Void)? = nil,
         onPlay: @escaping (PositionDraft) -> Void = { _ in }) {
        self.theme = theme
        self.photo = photo
        self.photoDoubts = photoDoubts
        self.onEditPieces = onEditPieces
        self.onSwitchTurn = onSwitchTurn
        self.onPlay = onPlay
        _model = State(initialValue: model)
        _flipped = State(initialValue: model.start.sideToMove == .black)
    }

    /// The side the person takes from here: the one to move.
    private var sideName: String { model.draft.sideToMove == .white ? "White" : "Black" }
    private var otherSideName: String { model.draft.sideToMove == .white ? "Black" : "White" }

    private var accent: Color { theme.trainingAccent }

    /// The last move's squares and the piece picked up, tinted.
    private var tints: [Square: Color] {
        var tints: [Square: Color] = [:]
        if let last = model.lastMove {
            tints[last.from] = accent.opacity(0.22)
            tints[last.to] = accent.opacity(0.34)
        }
        if let selected = model.selected {
            tints[selected] = accent.opacity(0.45)
        }
        return tints
    }

    /// What a pawn the person moved to the last rank becomes: Queen, Rook, Bishop or Knight,
    /// as in a game. A tap beside the pieces leaves the pawn where it was.
    @ViewBuilder
    private var promotionPicker: some View {
        if let promotion = model.promoting {
            GeometryReader { geo in
                PromotionPicker(
                    color: promotion.color, theme: theme,
                    squareSize: min(geo.size.width / 8, geo.size.height / 6),
                    cancel: { withAnimation(.snappy(duration: 0.2)) { model.cancelPromotion() } },
                    choose: { kind in withAnimation(.snappy(duration: 0.2)) { model.promote(to: kind) } }
                )
            }
            .transition(.opacity)
        }
    }

    /// The standing board's tilt here, in degrees: up from the lowest (50), which a scroll
    /// view would otherwise give it, toward the highest (62).
    static let analysisTilt: Float = 58

    /// The board, as in a game: the real 3D board, tilted or flat from above, with the Tilted /
    /// Flat switch under it, when the look has one and 3D pieces are on; otherwise the flat board.
    /// Seen from the side to move at first (the toolbar's button turns it round).
    @ViewBuilder
    private var board: some View {
        let hints = model.selected == nil ? model.hints : []
        if BoardView.playsIn3D(theme, setting: sculpted3D) {
            VStack(spacing: 6) {
                SculptedPositionBoard(pieces: model.draft.pieces, theme: theme, flipped: flipped, hints: hints,
                                      selected: model.selected, targets: model.targets,
                                      lastMove: model.lastMove.map { LastMove(from: $0.from, to: $0.to) },
                                      onTap: { square in model.tap(square) },
                                      framing: tilt.framing)
                    // Standing, a little taller than the scroll view would leave it: the camera
                    // tips higher, so the board and its pieces come out larger (Alex, 2026-11-08).
                    .aspectRatio(tilt == .tilted ? CGFloat(SculptedCamera.snugAspect(tilt: Self.analysisTilt)) : tilt.framing.aspect,
                                 contentMode: .fit)
                    .overlay { promotionPicker }
                    // Edge to edge, as the game's board runs: out past the screen's own padding.
                    .padding(.horizontal, -16)
                HStack {
                    turn
                    Spacer(minLength: 0)
                    BoardViewSwitch(theme: theme)
                }
            }
        } else {
            VStack(spacing: 6) {
                PositionBoard(draft: model.draft, theme: theme, flipped: flipped,
                              hints: hints,
                              onTap: { square in model.tap(square) }, tints: tints,
                              selected: model.selected, targets: model.targets)
                    .overlay { promotionPicker }
                    .animation(.snappy(duration: 0.4), value: flipped)
                    .animation(.snappy(duration: 0.22), value: model.draft.fen)
                if onSwitchTurn != nil {
                    HStack {
                        turn
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// Whose move it is. Before any move is made on the board it's a button that gives the move
    /// to the other side and starts the analysis over (Alex, 2026-11-07: "I can't switch from
    /// white to black", on a photo read as White's move).
    @ViewBuilder
    private var turn: some View {
        if let onSwitchTurn, !model.canGoBack {
            Button {
                model.stopLine()
                onSwitchTurn(model.draft)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .imageScale(.small)
                    Text("\(sideName) to move")
                }
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .glassPane(Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .accessibilityLabel("\(sideName) to move")
            .accessibilityHint("Gives the move to \(otherSideName) and analyzes again")
        } else {
            Text("\(sideName) to move")
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                photoRow
                header
                board
                    .sensoryFeedback(.selection, trigger: model.selected) { _, new in hapticsOn && new != nil }
                stepper
                madeMoves
                lines
                help
            }
            .padding(16)
            .animation(.snappy, value: model.lines)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Lower right (Alex, 2026-11-08), docked in its own strip so the page scrolls
            // above it and it never covers a score.
            if let photoButtons {
                HStack {
                    Spacer()
                    HStack(spacing: 0) {
                        photoButtons
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(PhotoPillStyle(accent: accent))
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(accent.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.9), ignoresSafeAreaEdges: .bottom)
            }
        }
        .navigationTitle("Analysis")
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
        .onDisappear { model.stopLine() }
        .sheet(isPresented: $showingPhoto) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Help

    /// At the foot of the page, the short directions for Analyze (Alex, 2026-11-09: "so people
    /// don't get confused"), unrolled as a scroll in the app (2026-11-11), not the website.
    private var help: some View {
        Button { showingHelp = true } label: {
            Label("How Analyze works", systemImage: "questionmark.circle")
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityHint("Shows how Analyze works")
        .sheet(isPresented: $showingHelp) { AnalyzeHelpScroll() }
    }

    // MARK: The photo

    /// The photo the position was read from, with the way to fix its pieces.
    @ViewBuilder
    private var photoRow: some View {
        if let photo, let onEditPieces {
            PhotoSourceRow(photo: photo, doubts: photoDoubts, theme: theme) {
                showingPhoto = true
            } onEdit: {
                model.stopLine()
                onEditPieces(model.draft)
            }
        }
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
                            .contentTransition(.numericText())
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

    // MARK: Stepping through

    /// Back to the start, a move back, play the best line, a move ahead.
    private var stepper: some View {
        HStack(spacing: 10) {
            stepButton("backward.end.fill", label: "Back to the start", enabled: model.canGoBack) { model.rewind() }
            stepButton("chevron.backward", label: "Move back", enabled: model.canGoBack) { model.back() }
            Button {
                if model.isPlayingLine { model.stopLine() } else { model.playLine() }
            } label: {
                Label(model.isPlayingLine ? "Pause" : "Play the line",
                      systemImage: model.isPlayingLine ? "pause.fill" : "play.fill")
                    .font(.app(.subheadline, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bordered)
            .disabled(!model.isPlayingLine && !model.canPlayLine)
            .accessibilityHint("Plays the engine's best line out on the board, a move at a time")
            stepButton("chevron.forward", label: "Move ahead", enabled: model.canGoForward) { model.forward() }
        }
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.app(.body, weight: .semibold))
                .frame(width: 48, height: 44)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// The moves made on the board, to jump back to; or how to make one.
    @ViewBuilder
    private var madeMoves: some View {
        let made = model.movesMade
        if made.isEmpty {
            Text(model.ending == nil
                 ? "Tap a piece to move it and see the best answer, or tap Play the line to watch the best moves play out."
                 : "Go back to try another move.")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        moveChip("Start", on: model.cursor == 0, ahead: false, id: -1) { model.rewind() }
                        ForEach(made, id: \.index) { move in
                            moveChip(move.label, on: model.cursor == move.index + 1, ahead: move.index >= model.cursor,
                                     id: move.index) { model.jump(to: move.index) }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.cursor) { _, cursor in
                    withAnimation(.snappy) { reader.scrollTo(cursor - 1, anchor: .center) }
                }
            }
        }
    }

    private func moveChip(_ text: String, on: Bool, ahead: Bool, id: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.app(.subheadline, weight: on ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(on ? accent : (ahead ? Color.secondary.opacity(0.7) : Color.primary))
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background {
                    Capsule().fill(on ? accent.opacity(0.18) : Color.secondary.opacity(0.1))
                }
        }
        .buttonStyle(.plain)
        .id(id)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: The two lines

    @ViewBuilder
    private var lines: some View {
        if model.ending == nil {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(model.lines.prefix(2).enumerated()), id: \.offset) { index, line in
                    Button {
                        if let uci = line.firstMove { model.play(uci, fromLine: true) }
                    } label: {
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
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Plays this move on the board")
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
                        Text("Checked by Stockfish 17. Tap a line to play its move.")
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

/// Over the analysis of a photo: the photo to compare with, what the reader wasn't sure of,
/// and the way to fix a piece it got wrong (Alex, 2026-11-06: "maybe have an option somewhere
/// to add pieces after analyze").
private struct PhotoSourceRow: View {
    let photo: UIImage
    let doubts: String?
    let theme: BoardTheme
    let onShowPhoto: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onShowPhoto) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show your photo")
            VStack(alignment: .leading, spacing: 2) {
                Text("From your photo")
                    .font(.app(.subheadline, weight: .semibold))
                if let doubts {
                    Text(doubts)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button(action: onEdit) {
                Label("Edit pieces", systemImage: "square.and.pencil")
                    .font(.app(.subheadline, weight: .semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Move, add or take off pieces, or change whose turn it is, then analyze again")
        }
        .padding(10)
        .background(Panel(theme: theme, highlight: doubts == nil ? nil : Color(hex: 0xFF9A3C)))
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
