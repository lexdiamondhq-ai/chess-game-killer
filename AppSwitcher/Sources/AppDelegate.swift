import AppKit
import ApplicationServices
import ServiceManagement

/// Menu bar app that owns the keyboard hook and the switcher.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let switcher = SwitcherController()
    private lazy var tap = KeyboardTap { [unowned self] type, event in
        self.switcher.handle(type: type, event: event)
    }
    private var permissionTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(AppDelegate.toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMenuBar()
        restoreNativeSwitcherOnSignals()

        if AXIsProcessTrusted() {
            start()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard AXIsProcessTrusted() else { return }
                self?.start()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NativeSwitcher.setEnabled(true)
    }

    private func start() {
        guard tap.start() else { return } // Try again on the next timer tick.
        permissionTimer?.invalidate()
        permissionTimer = nil
        NativeSwitcher.setEnabled(false)
    }

    // MARK: Menu bar

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Switcher")

        let menu = NSMenu()
        let hint = NSMenuItem(title: "Hold ⌘ and press Tab to switch apps", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Switcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = "Move Switcher to your Applications folder and try again.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
        loginItem.state = service.status == .enabled ? .on : .off
    }

    /// Give the built-in ⌘Tab back if the app is killed from Terminal or Activity Monitor.
    private func restoreNativeSwitcherOnSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                NativeSwitcher.setEnabled(true)
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
