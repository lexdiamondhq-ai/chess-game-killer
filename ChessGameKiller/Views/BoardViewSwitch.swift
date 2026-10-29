import SwiftUI

/// Under the board, beside the moves: Tilted or Flat, one tap. Tilted plays the carved 3D pieces
/// standing on a tilted board; Flat looks straight down on the flat pieces. Either one turns the
/// 3D board on, and a board without a 3D version moves to one that has it.
struct BoardViewSwitch: View {
    /// The board in play: the player's look, or a rival's board.
    let theme: BoardTheme
    /// Big Board, where Auto lays the board flat.
    var bigBoard = false

    @AppStorage("sculpted3D") private var sculpted3D = true
    @AppStorage(BoardTilt.storageKey) private var tilt = BoardTilt.auto
    @AppStorage("boardTheme") private var themeID: BoardTheme.ID = .gilded
    @AppStorage("matchRival") private var matchRival = false
    @Namespace private var marker

    private var accent: Color { theme.accent ?? .accentColor }

    private var current: BoardTilt? {
        Self.showing(theme, threeD: sculpted3D, framing: tilt.framing(bigBoard: bigBoard))
    }

    var body: some View {
        HStack(spacing: 0) {
            segment(.tilted, symbol: "perspective")
            segment(.flat, symbol: "square.grid.2x2")
        }
        .padding(2)
        .frame(height: 26)
        .glassPane(Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board view")
    }

    private func segment(_ choice: BoardTilt, symbol: String) -> some View {
        let isOn = current == choice
        return Button {
            pick(choice)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .imageScale(.small)
                Text(choice.title)
            }
            .font(.system(.footnote, design: .themed).weight(.semibold))
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .background {
                if isOn {
                    Capsule()
                        .fill(accent.opacity(0.22))
                        .overlay { Capsule().strokeBorder(accent.opacity(0.5), lineWidth: 0.75) }
                        .matchedGeometryEffect(id: "on", in: marker)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func pick(_ choice: BoardTilt) {
        let change = Self.change(inPlay: theme, chosen: .named(themeID))
        withAnimation(.snappy) {
            if change.leavesRivalBoard { matchRival = false }
            if let look = change.look { themeID = look }
            sculpted3D = true
            tilt = choice
        }
    }

    /// The view on show, or nil while the board is drawn flat in 2D (3D pieces off, or a look
    /// without a 3D board).
    static func showing(_ theme: BoardTheme, threeD: Bool, framing: SculptedCamera.Framing) -> BoardTilt? {
        guard BoardView.playsIn3D(theme, setting: threeD) else { return nil }
        return framing == .seated ? .flat : .tilted
    }

    /// What else a pick changes, so a 3D board is in play afterwards.
    struct Change: Equatable {
        /// Match rival goes off: the rival's board, which has no 3D version, gives way to the player's look.
        var leavesRivalBoard = false
        /// The player's look has no 3D version either: the game moves to Gilded.
        var look: BoardTheme.ID?
    }

    static func change(inPlay theme: BoardTheme, chosen: BoardTheme) -> Change {
        guard theme.sculptedLook == nil else { return Change() }
        var change = Change()
        // A board in play other than the player's own is the rival's, there through Match rival.
        change.leavesRivalBoard = theme.id != chosen.id
        if chosen.sculptedLook == nil { change.look = .gilded }
        return change
    }
}
