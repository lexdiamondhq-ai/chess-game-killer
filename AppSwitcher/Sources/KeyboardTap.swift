import CoreGraphics
import Foundation

/// A system-wide keyboard hook. The handler returns true to swallow an event.
final class KeyboardTap {
    typealias Handler = (CGEventType, CGEvent) -> Bool

    private let handler: Handler
    private var machPort: CFMachPort?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Needs Accessibility permission. Returns false if macOS refused the hook.
    func start() -> Bool {
        if machPort != nil { return true }

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<KeyboardTap>.fromOpaque(refcon).takeUnretainedValue()

            // macOS switches the hook off if it ever runs slow. Turn it right back on.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let port = tap.machPort { CGEvent.tapEnable(tap: port, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return tap.handler(type, event) ? nil : Unmanaged.passUnretained(event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        machPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
}
