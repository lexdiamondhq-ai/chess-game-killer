import AppKit

/// Keeps running apps in most-recently-used order, like Windows Alt+Tab.
final class RecentApps {
    private var order: [pid_t] = []

    init() {
        let workspace = NSWorkspace.shared
        if let front = workspace.frontmostApplication {
            order.append(front.processIdentifier)
        }
        let center = workspace.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.moveToFront(app.processIdentifier)
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.order.removeAll { $0 == app.processIdentifier }
        }
    }

    /// Apps that show in the Dock, most recent first. Apps never activated keep launch order at the end.
    func ordered() -> [NSRunningApplication] {
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return NSWorkspace.shared.runningApplications
            .enumerated()
            .filter { $0.element.activationPolicy == .regular && !$0.element.isTerminated }
            .sorted { a, b in
                let ra = rank[a.element.processIdentifier] ?? Int.max
                let rb = rank[b.element.processIdentifier] ?? Int.max
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }

    private func moveToFront(_ pid: pid_t) {
        order.removeAll { $0 == pid }
        order.insert(pid, at: 0)
    }
}
