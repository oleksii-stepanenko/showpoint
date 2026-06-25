import AppKit
import CoreGraphics
import ApplicationServices

/// Listens for global key and mouse-down events via a `CGEventTap`. The tap is
/// listen-only (it never modifies or swallows events) and runs on the main run
/// loop. Requires the Accessibility permission.
///
/// Note on privacy: when a secure text field (password) is focused, macOS turns
/// on secure event input and the system simply does not deliver those keystrokes
/// to taps — so passwords are never seen, the same guarantee KeyScreen makes.
final class KeystrokeMonitor {
    typealias Handler = (RawKeyEvent) -> Void

    private let handler: Handler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isRunning: Bool { eventTap != nil }

    /// Returns false if the tap could not be created (usually missing
    /// permission), so the caller can prompt.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            NSLog("Showpoint: CGEvent.tapCreate FAILED — trusted=\(AXIsProcessTrusted())")
            return false
        }
        NSLog("Showpoint: CGEvent.tapCreate OK — trusted=\(AXIsProcessTrusted())")

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        // The system disables a tap that is slow or after certain input; just
        // re-enable and move on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard let raw = RawKeyEvent(type: type, cgEvent: event) else { return }
        handler(raw)
    }
}

/// Free C-compatible callback. Runs on the main run loop since that's where the
/// source is attached.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let monitor = Unmanaged<KeystrokeMonitor>.fromOpaque(refcon).takeUnretainedValue()
        monitor.handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
