import AppKit
import CoreGraphics

/// Windows-style Alt+Tab on ⌘Tab: hold ⌘, tap Tab to move, let go of ⌘ to switch.
final class SwitcherController {
    private enum Key {
        static let tab: Int64 = 48
        static let escape: Int64 = 53
        static let returnKey: Int64 = 36
        static let left: Int64 = 123
        static let right: Int64 = 124
        static let grave: Int64 = 50 // ` key: move backwards
        static let q: Int64 = 12     // quit the selected app
        static let h: Int64 = 4      // hide the selected app
    }

    /// A quick ⌘Tab tap switches straight back without flashing the panel.
    private let showDelay: TimeInterval = 0.12

    private let recents = RecentApps()
    private let panel = SwitcherPanel.make()
    private var apps: [NSRunningApplication] = []
    private var selected = 0
    private var isOpen = false
    private var pendingShow: DispatchWorkItem?

    init() {
        panel.switcherView.onHover = { [weak self] index in self?.select(index) }
        panel.switcherView.onClick = { [weak self] index in
            self?.select(index)
            self?.commit()
        }
    }

    /// Called for every key event on the system. Returns true to swallow it.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let flags = event.flags
        let command = flags.contains(.maskCommand)
        let shift = flags.contains(.maskShift)
        let key = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .keyDown:
            if command && key == Key.tab {
                isOpen ? step(shift ? -1 : 1) : open(backwards: shift)
                return true
            }
            guard isOpen else { return false }
            switch key {
            case Key.escape: close()
            case Key.returnKey: commit()
            case Key.left, Key.grave: step(-1)
            case Key.right: step(1)
            case Key.q: quitSelected()
            case Key.h: hideSelected()
            default: break
            }
            return true // Nothing else leaks into the app underneath while the switcher is open.

        case .keyUp:
            return isOpen

        case .flagsChanged:
            if isOpen && !command { commit() }
            return false

        default:
            return false
        }
    }

    // MARK: Actions

    private func open(backwards: Bool) {
        apps = recents.ordered()
        isOpen = true
        guard !apps.isEmpty else { return }

        // Start on the previous app, unless the front app is something outside the list.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontIsFirst = apps.first?.processIdentifier == frontPID
        if backwards {
            selected = apps.count - 1
        } else {
            selected = frontIsFirst && apps.count > 1 ? 1 : 0
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isOpen else { return }
            self.panel.show(apps: self.apps, selected: self.selected)
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
    }

    private func step(_ delta: Int) {
        guard !apps.isEmpty else { return }
        select((selected + delta + apps.count) % apps.count)
    }

    private func select(_ index: Int) {
        guard apps.indices.contains(index) else { return }
        selected = index
        panel.switcherView.selected = index
    }

    private func commit() {
        let target = apps.indices.contains(selected) ? apps[selected] : nil
        close()
        // Activate after the key event returns, so a slow app can't stall the keyboard hook.
        if let target {
            DispatchQueue.main.async { Activator.bringForward(target) }
        }
    }

    private func close() {
        pendingShow?.cancel()
        pendingShow = nil
        isOpen = false
        panel.orderOut(nil)
        apps = []
    }

    private func quitSelected() {
        guard apps.indices.contains(selected) else { return }
        apps[selected].terminate()
        removeSelected()
    }

    private func hideSelected() {
        guard apps.indices.contains(selected) else { return }
        apps[selected].hide()
        panel.switcherView.needsDisplay = true
    }

    private func removeSelected() {
        apps.remove(at: selected)
        if apps.isEmpty { close(); return }
        selected = min(selected, apps.count - 1)
        if panel.isVisible { panel.show(apps: apps, selected: selected) }
    }
}
