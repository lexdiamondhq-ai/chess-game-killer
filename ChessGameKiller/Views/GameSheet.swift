import SwiftUI

/// The game's dock in the board style (Alex's pick, 1A Sheet With Tabs, 2026-11-03): the same
/// glass sheet as the board home's, across the foot of the screen with its grabber, so the home
/// and the game read as one board with one sheet. It holds the dock's controls around the coach
/// orb. Pull it up and the coach unfolds into it; the coach's own handle folds it away again.
/// Settings > Board and sheet turns it off for the floating dock.
struct GameSheet<Content: View>: View {
    let theme: BoardTheme
    /// The coach is unfolded in the sheet.
    let isOpen: Bool
    /// The home indicator's height: the glass runs on under it, past the screen's foot.
    let bottomInset: CGFloat
    /// Opens the coach (or folds it, from a swipe down).
    let setOpen: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    @AppStorage("haptics") private var hapticsOn = true
    /// How far the finger has the sheet from its rest. It springs back by itself when the pull
    /// ends or is cut short (the coach opening mid-pull, a call coming in).
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.4, dampingFraction: 0.72)))
    private var drag: CGFloat = 0
    private var dragging: Bool { drag != 0 }
    /// Counts the pulls that opened the coach, for a light tap each.
    @State private var pulls = 0

    /// The sheet's corner: the home sheet's.
    static var radius: CGFloat { 34 }
    /// How far the glass runs past the screen's foot, so only its top corners ever show: past
    /// the furthest stretch (56) and the bottom corners' curve with room to spare.
    private static var overhang: CGFloat { 110 }
    /// How far up a flick must be heading to open the coach.
    private static var flick: CGFloat { 50 }

    private var accent: Color { theme.accent ?? .accentColor }

    var body: some View {
        VStack(spacing: 0) {
            if !isOpen {
                grabber
                    .transition(.opacity)
            }
            content()
                .padding(.horizontal, isOpen ? 0 : 10)
        }
        .padding(.top, isOpen ? 4 : 0)
        // Above the home indicator; on a phone without one, a little off the edge.
        .padding(.bottom, bottomInset > 0 ? 0 : 8)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { glass }
        .offset(y: stretch)
        // Closed, the whole sheet can be pulled up. Open, the coach's buttons and scrolling
        // keep their own gestures, and its handle folds it away.
        .gesture(pull, including: isOpen ? .subviews : .all)
        .sensoryFeedback(.impact(weight: .light), trigger: pulls) { (_: Int, _: Int) -> Bool in hapticsOn }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isOpen)
    }

    /// The handle at the top: it stretches while the sheet is pulled, and a tap opens the coach.
    private var grabber: some View {
        Capsule()
            .fill(Color.primary.opacity(dragging ? 0.5 : 0.28))
            .frame(width: dragging ? 52 : 38, height: 5)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: dragging)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .contentShape(Rectangle().inset(by: -6))
            .onTapGesture(perform: openCoach)
            .accessibilityElement()
            .accessibilityLabel("Open the coach")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, openCoach)
    }

    /// The home sheet's glass, running from the sheet's top past the screen's foot. Neon's
    /// accent glows behind it.
    private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let below: CGFloat = bottomInset + Self.overhang
        return ZStack {
            if theme.glows {
                shape.fill(accent.opacity(0.16))
                    .blur(radius: 18)
            }
            GlassSurface(shape: shape)
                .shadow(color: .black.opacity(0.3), radius: 22, y: -4)
        }
        .padding(.bottom, -below)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The sheet follows the finger a little way, giving less the further it goes, like a
    /// rubber band.
    private var stretch: CGFloat {
        let limit: CGFloat = 56
        let distance: CGFloat = abs(drag)
        let give: CGFloat = limit * (1 - 1 / (distance / limit + 1))
        return drag < 0 ? -give : give
    }

    /// Pulled up and let go heading up: the coach opens. Anything else springs back.
    private var pull: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($drag) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let heading: CGFloat = value.predictedEndTranslation.height
                if heading < -Self.flick { openCoach() }
            }
    }

    private func openCoach() {
        guard !isOpen else { return }
        pulls += 1
        setOpen(true)
    }
}

extension View {
    /// In the board style every sheet shows its grabber, like the home's and the game's.
    func boardSheetGrabber(_ on: Bool) -> some View {
        presentationDragIndicator(on ? .visible : .automatic)
    }
}
