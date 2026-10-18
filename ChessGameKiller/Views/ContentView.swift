import SwiftUI

struct ContentView: View {
    @State private var game = GameModel()
    @State private var confirmingNewGame = false
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .walnut

    private var theme: BoardTheme { .named(themeID) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                StatusBar(game: game, theme: theme)
                BoardView(game: game, theme: theme)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if theme.isDark {
                    NeonBackdrop()
                } else {
                    Color(.systemGroupedBackground).ignoresSafeArea()
                }
            }
            .navigationTitle("Chess Game Killer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ThemeMenu(themeID: $themeID)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        if game.canUndo && !game.isGameOver {
                            confirmingNewGame = true
                        } else {
                            withAnimation(.snappy) { game.newGame() }
                        }
                    } label: {
                        Label("New Game", systemImage: "plus.circle")
                    }
                    .labelStyle(.titleAndIcon)
                    Spacer()
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { game.undo() }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .labelStyle(.titleAndIcon)
                    .disabled(!game.canUndo)
                }
            }
            .toolbarBackground(theme.isDark ? .visible : .automatic, for: .bottomBar)
            .confirmationDialog("Start a new game?", isPresented: $confirmingNewGame, titleVisibility: .visible) {
                Button("New Game", role: .destructive) {
                    withAnimation(.snappy) { game.newGame() }
                }
            } message: {
                Text("The current game will be lost.")
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.isDark ? .dark : nil)
        .animation(.easeInOut(duration: 0.35), value: themeID)
    }
}

/// Top-right menu for picking the board look. The choice is remembered.
private struct ThemeMenu: View {
    @Binding var themeID: BoardTheme.ID

    var body: some View {
        Menu {
            Picker("Board", selection: $themeID) {
                ForEach(BoardTheme.all) { theme in
                    Label(theme.name, systemImage: theme.symbol).tag(theme.id)
                }
            }
        } label: {
            Label("Board style", systemImage: "paintpalette")
        }
    }
}

/// Whose turn it is, or how the game ended.
private struct StatusBar: View {
    let game: GameModel
    let theme: BoardTheme

    var body: some View {
        let sideColor = game.sideToMove == .white ? theme.whiteSide : theme.blackSide
        HStack(spacing: 10) {
            Circle()
                .fill(sideColor)
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: theme.isDark ? 0 : 1))
                .frame(width: 14, height: 14)
                .shadow(color: theme.isDark ? sideColor : .clear, radius: 5)
            Text(game.status)
                .font(.headline)
                .foregroundStyle(game.isGameOver ? Color.accentColor : Color.primary)
                .contentTransition(.opacity)
            Spacer()
        }
        .padding(.horizontal, 4)
        .animation(.snappy, value: game.status)
        .accessibilityElement(children: .combine)
    }
}

#Preview { ContentView() }
