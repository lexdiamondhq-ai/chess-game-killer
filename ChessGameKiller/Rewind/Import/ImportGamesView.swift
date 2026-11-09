import SwiftUI

/// Brings the player's recent games in from Chess.com or Lichess: pick the site, type the
/// username, and Coach Leo reads each game. They land in Rewind with the games played here.
struct ImportGamesView: View {
    let theme: BoardTheme
    @Environment(GameVault.self) private var vault
    @Environment(TrainingStore.self) private var store
    @State private var importer = GameImporter()
    @State private var site: OnlineSite = .chessCom
    @State private var username = ""
    @FocusState private var typing: Bool

    var body: some View {
        TrainScreen(theme: theme, title: "Your online games",
                    intro: "Bring in your last \(OnlineGames.importCount) games from Chess.com or Lichess. \(Coach.current.title) reads every move, and your mistakes become puzzles.") {
            form
            status
        }
        .onAppear {
            if let account = importer.account {
                site = account.site
                username = account.username
            }
        }
        // Leaving stops the reading; every game already read stays.
        .onDisappear { importer.cancel() }
    }

    // MARK: The form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Site", selection: $site) {
                ForEach(OnlineSite.allCases) { site in
                    Text(site.title).tag(site)
                }
            }
            .pickerStyle(.segmented)
            .disabled(importer.phase.isWorking)

            TextField("\(site.title) username", text: $username)
                .font(.app(.body))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .submitLabel(.go)
                .focused($typing)
                .onSubmit(begin)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
                .disabled(importer.phase.isWorking)

            if importer.phase.isWorking {
                Button(role: .cancel) {
                    importer.cancel()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TrainingButtonStyle(theme: theme, prominent: false))
            } else {
                Button(action: begin) {
                    Label(isSameAccount ? "Check for new games" : "Bring in my games", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TrainingButtonStyle(theme: theme))
                .disabled(OnlineGames.cleaned(username) == nil)
            }
        }
        .padding(18)
        .trainingCard(theme)
    }

    private var isSameAccount: Bool {
        guard let account = importer.account else { return false }
        return account.site == site && account.username.lowercased() == username.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func begin() {
        guard OnlineGames.cleaned(username) != nil, !importer.phase.isWorking else { return }
        typing = false
        importer.start(site: site, username: username, vault: vault, store: store)
    }

    // MARK: How it's going

    @ViewBuilder
    private var status: some View {
        switch importer.phase {
        case .idle:
            EmptyView()
        case .fetching(let site):
            statusCard(title: "Asking \(site.title)…", detail: "Finding your most recent finished games.", progress: nil)
        case .reading(let done, let total):
            statusCard(title: "Reading game \(done + 1) of \(total)",
                       detail: "\(Coach.current.title) checks each of your moves with Stockfish. Games read so far are kept if you leave.",
                       progress: total == 0 ? nil : Double(done) / Double(total))
        case .finished(let added, let mistakes):
            finishedCard(added: added, mistakes: mistakes)
        case .failed(let message):
            statusCard(title: "Couldn't bring them in", detail: message, progress: nil, symbol: "exclamationmark.triangle.fill")
        }
    }

    private func statusCard(title: String, detail: String, progress: Double?, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(theme.trainingAccent)
                        .accessibilityHidden(true)
                } else {
                    ProgressView()
                }
                Text(title)
                    .font(.app(.headline))
            }
            Text(detail)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let progress {
                ProgressView(value: progress)
                    .tint(theme.trainingAccent)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme)
        .accessibilityElement(children: .combine)
    }

    private func finishedCard(added: Int, mistakes: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CoachAvatar(theme: theme, size: 40)
            Text(added == 0 ? "You're up to date" : added == 1 ? "1 game brought in" : "\(added) games brought in")
                .font(.app(.title3, weight: .bold))
            Text(finishedDetail(added: added, mistakes: mistakes))
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingCard(theme, tint: theme.trainingAccent)
        .accessibilityElement(children: .combine)
    }

    private func finishedDetail(added: Int, mistakes: Int) -> String {
        if added == 0 { return "Every recent game is already here. Play a few more and check again." }
        let saved = mistakes == 0 ? "" : mistakes == 1
            ? " One position went to Fix your mistakes."
            : " \(mistakes) positions went to Fix your mistakes."
        return "They're in Rewind with your other games, and in what I see about your play.\(saved)"
    }
}

/// The way into the import from the "Your games" door.
struct ImportGamesRow: View {
    let theme: BoardTheme

    private var account: GameImporter.Account? {
        UserDefaults.standard.data(forKey: GameImporter.accountKey)
            .flatMap { try? JSONDecoder().decode(GameImporter.Account.self, from: $0) }
    }

    var body: some View {
        NavigationLink {
            ImportGamesView(theme: theme)
        } label: {
            TrainRow(symbol: "arrow.down.circle",
                     title: account.map { "Your \($0.site.title) games" } ?? "Bring in your online games",
                     detail: account.map { "Check \($0.username)'s newest games for \(Coach.current.title) to read." }
                        ?? "Chess.com or Lichess: \(Coach.current.title) reads them like the games you play here.",
                     value: nil, badge: 0, theme: theme)
        }
        .buttonStyle(.plain)
    }
}
