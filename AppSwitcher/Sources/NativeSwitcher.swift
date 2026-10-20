import CoreGraphics

/// Turns the built-in macOS ⌘Tab switcher off while ours runs, and back on when we quit.
/// Uses the same private CoreGraphics call that AltTab and similar apps use.
enum NativeSwitcher {
    private static let commandTab: Int32 = 1
    private static let commandShiftTab: Int32 = 2

    static func setEnabled(_ enabled: Bool) {
        _ = CGSSetSymbolicHotKeyEnabled(commandTab, enabled)
        _ = CGSSetSymbolicHotKeyEnabled(commandShiftTab, enabled)
    }
}

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> Int32
