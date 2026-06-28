import AppKit
import CoreGraphics

/// A consuming `CGEventTap` that swallows **Control + scroll-wheel** events so the
/// view underneath doesn't scroll while you resize the spotlight. Every other
/// event — plain scrolls, clicks, drags — passes straight through untouched, so
/// the overlay stays click-through. Requires Accessibility (like any tap that
/// alters the event stream); when it isn't granted the controller falls back to a
/// non-consuming global monitor, which still resizes but lets the content scroll.
final class ScrollSpotlightTap {
    /// Reports the scroll delta (matched to `NSEvent.scrollingDeltaY`) for each
    /// consumed Control+scroll. Called on the main thread.
    private let onResize: (CGFloat) -> Void

    /// When false the tap passes Control+scroll through unchanged (feature off).
    var isEnabled = true

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onResize: @escaping (CGFloat) -> Void) {
        self.onResize = onResize
    }

    var isInstalled: Bool { eventTap != nil }

    func install() {
        guard eventTap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,           // .defaultTap lets us delete the event
            eventsOfInterest: mask,
            callback: scrollTapCallback,
            userInfo: refcon
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    func uninstall() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    /// Returns true when the event should be consumed (deleted from the stream).
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }

        guard type == .scrollWheel, isEnabled, event.flags.contains(.maskControl) else {
            return false
        }

        // Mirror `NSEvent.scrollingDeltaY`: precise (trackpad) → point delta,
        // otherwise (wheel mouse) → line delta. Keeps resize feel identical to the
        // non-consuming fallback path.
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let delta = continuous
            ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            : event.getDoubleValueField(.scrollWheelEventDeltaAxis1)

        onResize(CGFloat(delta))
        return true   // swallow so the app underneath doesn't scroll
    }
}

private func scrollTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<ScrollSpotlightTap>.fromOpaque(refcon).takeUnretainedValue()
    return tap.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
