import AppKit
import CoreGraphics
import QuartzCore

/// Counts quick consecutive "clean" taps of the Control key (each a press-release
/// with no other key in between) and reports the total once tapping stops. Used
/// for hands-free toggles: double-tap → cursor highlight, triple-tap → annotation.
///
/// Because two and three taps share the same key, the detector must wait
/// `interTapTimeout` after the last tap before reporting — you can't know a 2
/// isn't about to become a 3. That adds a small, unavoidable delay before the
/// action fires.
///
/// Uses a `CGEventTap` (the mechanism verified to deliver real `flagsChanged`),
/// listen-only. Requires Accessibility.
final class MultiTapControlDetector {
    /// Called with the number of taps (only for counts >= 2).
    private let handler: (Int) -> Void
    private let interTapTimeout: CFTimeInterval = 0.32

    /// Which modifier is being multi-tapped. Changeable at runtime.
    var modifier: TapModifier = .control { didSet { resetState() } }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var modifierDown = false
    private var usedInCombo = false
    private var tapCount = 0
    private var flushGeneration = 0

    private let debug = ProcessInfo.processInfo.environment["PRESENTER_DEBUG_KEYS"] != nil

    init(handler: @escaping (Int) -> Void) {
        self.handler = handler
    }

    private func resetState() {
        modifierDown = false
        usedInCombo = false
        tapCount = 0
    }

    private static func flag(for modifier: TapModifier) -> CGEventFlags {
        switch modifier {
        case .control: return .maskControl
        case .option:  return .maskAlternate
        case .command: return .maskCommand
        case .shift:   return .maskShift
        }
    }

    var isInstalled: Bool { eventTap != nil }

    func install() {
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: multiTapCallback,
            userInfo: refcon
        ) else {
            if debug { NSLog("Showpoint[multitap]: tapCreate FAILED") }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        if debug { NSLog("Showpoint[multitap]: installed") }
    }

    func uninstall() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        resetState()
    }

    func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }

        if type == .keyDown {
            if modifierDown { usedInCombo = true }
            return
        }

        // flagsChanged
        let flags = event.flags
        let activeFlag = Self.flag(for: modifier)
        let allModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn]
        let modifierNow = flags.contains(activeFlag)
        let otherModifiers = !flags.intersection(allModifiers.subtracting(activeFlag)).isEmpty

        if modifierNow && !modifierDown {
            modifierDown = true
            usedInCombo = otherModifiers
        } else if modifierNow && modifierDown {
            if otherModifiers { usedInCombo = true }
        } else if !modifierNow && modifierDown {
            modifierDown = false
            guard !usedInCombo else { return }
            registerTap()
        }
    }

    private func registerTap() {
        tapCount += 1
        flushGeneration += 1
        let generation = flushGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + interTapTimeout) { [weak self] in
            guard let self, generation == self.flushGeneration else { return }
            let count = self.tapCount
            self.tapCount = 0
            if self.debug { NSLog("Showpoint[multitap]: \(count) taps") }
            if count >= 2 { self.handler(count) }
        }
    }
}

private func multiTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let detector = Unmanaged<MultiTapControlDetector>.fromOpaque(refcon).takeUnretainedValue()
        detector.handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
