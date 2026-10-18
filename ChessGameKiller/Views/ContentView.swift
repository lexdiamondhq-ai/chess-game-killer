import SwiftUI

struct ContentView: View {
    @State private var game = GameModel()
    @State private var confirmingNewGame = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                StatusBar(game: game)
                BoardView(game: game)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Chess Game Killer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                    Spacer()
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { game.undo() }
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!game.canUndo)
                }
            }
            .labelStyle(.titleAndIcon)
            .confirmationDialog("Start a new game?", isPresented: $confirmingNewGame, titleVisibility: .visible) {
                Button("New Game", role: .destructive) {
                    withAnimation(.snappy) { game.newGame() }
                }
            } message: {
                Text("The current game will be lost.")
            }
        }
    }
}

/// Whose turn it is, or how the game ended.
private struct StatusBar: View {
    let game: GameModel

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(game.sideToMove == .white ? Color.white : Color.black)
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1))
                .frame(width: 14, height: 14)
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
