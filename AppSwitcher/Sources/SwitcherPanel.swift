import AppKit

/// The floating dark bar of app icons in the middle of the screen.
final class SwitcherPanel: NSPanel {
    let switcherView = SwitcherView()
    private let background = NSVisualEffectView()

    static func make() -> SwitcherPanel {
        let panel = SwitcherPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.configure()
        return panel
    }

    private func configure() {
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        appearance = NSAppearance(named: .darkAqua)

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 20
        background.layer?.masksToBounds = true
        background.addSubview(switcherView)
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(apps: [NSRunningApplication], selected: Int) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let area = screen.visibleFrame

        switcherView.apps = apps
        switcherView.selected = selected
        switcherView.fitIcons(maxWidth: area.width * 0.9)
        let size = switcherView.preferredSize

        let frame = NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        setFrame(frame, display: false)
        switcherView.frame = NSRect(origin: .zero, size: size)
        switcherView.needsDisplay = true
        orderFrontRegardless()
    }
}

/// Draws the icons, the highlight and the selected app's name.
final class SwitcherView: NSView {
    var apps: [NSRunningApplication] = []
    var selected = 0 { didSet { needsDisplay = true } }
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private var iconSize: CGFloat = 96
    private let maxIconSize: CGFloat = 96
    private let minIconSize: CGFloat = 32
    private let inset: CGFloat = 10    // space between highlight edge and icon
    private let gap: CGFloat = 8       // space between cells
    private let padding: CGFloat = 18  // space between cells and panel edge
    private let labelHeight: CGFloat = 20

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var cellSize: CGFloat { iconSize + inset * 2 }

    var preferredSize: NSSize {
        let count = CGFloat(max(apps.count, 1))
        let width = padding * 2 + count * cellSize + (count - 1) * gap
        let height = padding + cellSize + 6 + labelHeight + padding - 4
        return NSSize(width: width, height: height)
    }

    /// Shrinks icons when many apps are open so the bar always fits on screen.
    func fitIcons(maxWidth: CGFloat) {
        let count = CGFloat(max(apps.count, 1))
        let fitted = (maxWidth - padding * 2 - (count - 1) * gap) / count - inset * 2
        iconSize = min(maxIconSize, max(minIconSize, fitted.rounded(.down)))
    }

    private func cellRect(_ index: Int) -> NSRect {
        NSRect(x: padding + CGFloat(index) * (cellSize + gap), y: padding, width: cellSize, height: cellSize)
    }

    private func index(at point: NSPoint) -> Int? {
        apps.indices.first { cellRect($0).contains(point) }
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, app) in apps.enumerated() {
            let cell = cellRect(i)
            if i == selected {
                NSColor.white.withAlphaComponent(0.2).setFill()
                NSBezierPath(roundedRect: cell, xRadius: 14, yRadius: 14).fill()
            }
            let icon = app.icon ?? NSImage(named: NSImage.applicationIconName)
            icon?.draw(
                in: cell.insetBy(dx: inset, dy: inset),
                from: .zero,
                operation: .sourceOver,
                fraction: app.isHidden ? 0.45 : 1, // Hidden apps look faded, like the Mac's own switcher.
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high.rawValue]
            )
        }
        drawSelectedName()
    }

    private func drawSelectedName() {
        guard apps.indices.contains(selected) else { return }
        let name = apps[selected].localizedName ?? ""

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ]

        let cell = cellRect(selected)
        let width = min(240, bounds.width - 16)
        var x = cell.midX - width / 2
        x = max(8, min(x, bounds.width - 8 - width)) // Keep the name inside the panel.
        let rect = NSRect(x: x, y: cell.maxY + 6, width: width, height: labelHeight)
        (name as NSString).draw(in: rect, withAttributes: attributes)
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        if let i = index(at: convert(event.locationInWindow, from: nil)), i != selected { onHover?(i) }
    }

    override func mouseDown(with event: NSEvent) {
        if let i = index(at: convert(event.locationInWindow, from: nil)) { onClick?(i) }
    }
}
