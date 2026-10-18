import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                BoardView(board: .starting)
                    .padding(16)
            }
            .navigationTitle("Chess Game Killer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview { ContentView() }
