import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The challenge's link as a QR code, dark on ivory, for a friend next to you to scan with their camera.
struct InviteQRCode: View {
    let url: URL

    var body: some View {
        Group {
            if let image = Self.image(for: url.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xF3EEE6)))
    }

    /// The QR code at one point a module; the view scales it up without smoothing.
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Dark modules in the page's near-black, the rest clear (the ivory card shows through).
        let colored = output.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(red: 0.106, green: 0.102, blue: 0.098, alpha: 1),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
        ])
        guard let cg = CIContext().createCGImage(colored, from: colored.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Picking (or changing) the player's @username, so friends can find them.
struct UsernamePicker: View {
    let name: String
    let theme: BoardTheme

    @Environment(ChallengeCenter.self) private var center
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var problem: String?
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(center.friends.you == nil ? "Pick your username" : "Change your username")
                    .font(.display(size: 26, weight: .medium))
                Text("Friends find you by it and send you challenges. Letters, numbers, _ and . only.")
                    .font(theme.challengeFont(15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text("@")
                    .font(theme.challengeFont(19, .semibold))
                    .foregroundStyle(theme.challengeAccent)
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .font(theme.challengeFont(19, .medium))
                    .focused($focused)
                    .onSubmit(save)
                    .onChange(of: username) { _, new in
                        let lowered = new.lowercased().replacingOccurrences(of: "@", with: "")
                        let trimmed = String(lowered.prefix(20))
                        if trimmed != new { username = trimmed }
                        problem = nil
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .challengeGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if let problem {
                Text(problem)
                    .font(theme.challengeFont(13))
                    .foregroundStyle(ChallengeColors.danger)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            Button(action: save) {
                ZStack {
                    Text("Save").opacity(saving ? 0 : 1)
                    if saving { ProgressView() }
                }
            }
            .buttonStyle(ChallengeButtonStyle(kind: .primary, theme: theme))
            .disabled(saving || username.count < 3)
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .tint(theme.challengeAccent)
        .screenScheme(theme)
        .animation(.snappy(duration: 0.2), value: problem)
        .onAppear {
            username = center.friends.you?.username ?? FriendDirectory.suggestion(from: name)
            focused = true
        }
    }

    private func save() {
        guard !saving, username.count >= 3 else { return }
        saving = true
        Task {
            let why = await center.friends.claim(username, name: name.isEmpty ? username : name)
            saving = false
            if let why {
                problem = why
            } else {
                dismiss()
            }
        }
    }
}

/// A challenge a friend sent by username, floating at the top of the app: open it, or let it go.
struct FriendInviteBanner: View {
    let note: FriendInviteNote
    let theme: BoardTheme
    let open: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatar(person: note.from, size: 40, theme: theme)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(note.from.name) challenges you")
                    .font(theme.challengeFont(15, .semibold))
                    .lineLimit(1)
                Text(note.detail)
                    .font(theme.challengeFont(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button("Play", action: open)
                .font(theme.challengeFont(15, .semibold))
                .foregroundStyle(theme.screenTone != nil ? Polish.onMetal : theme.onChallengeAccent)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background { MainPillFill(gilded: theme.screenTone != nil, plain: theme.challengeAccent) }
                .buttonStyle(ChallengePressStyle())
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not now")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            ZStack {
                // The lift is drawn under the pane only, so nothing inside the glass casts its own.
                shape.fill(Polish.cast(dark: theme.screenIsDark, strength: 1.75))
                    .blur(radius: 12)
                    .offset(y: 8)
                    // A shadow takes no touches: the banner floats over the whole app.
                    .allowsHitTesting(false)
                shape.fill(.ultraThinMaterial)
            }
        }
        // A friend is asking: the bright edge.
        .overlay { PolishedEdge(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), edge: .lit) }
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
    }
}
