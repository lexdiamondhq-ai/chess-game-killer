import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                BoardView(board: .starting)
                    .padding()
            }
            .navigationTitle("Chess Game Killer")
        }
    }
}

#Preview { ContentView() }
