import AppKit
import CoreGraphics

/// A minimal snapshot of a tapped event, decoded once on the tap callback so the
/// stateful interpreter can run on the main actor without touching `CGEvent`.
struct RawKeyEvent {
    let type: CGEventType
    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags
    let chars: String?

    /// Memberwise init used by the self-test harness.
    init(type: CGEventType, keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, chars: String?) {
        self.type = type
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.chars = chars
    }

    init?(type: CGEventType, cgEvent: CGEvent) {
        self.type = type
        switch type {
        case .leftMouseDown, .rightMouseDown:
            keyCode = 0
            modifierFlags = []
            chars = nil
        case .keyDown, .flagsChanged:
            // Read keycode + flags straight from the CGEvent. We deliberately do
            // NOT route through `NSEvent(cgEvent:)`, which returns nil for
            // `flagsChanged` events on macOS — that would drop every bare
            // modifier press. `CGEventFlags` and `NSEvent.ModifierFlags` share
            // the same bit layout for the device-independent modifiers.
            keyCode = UInt16(cgEvent.getIntegerValueField(.keyboardEventKeycode))
            modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
            // Characters are only needed for `keyDown`; NSEvent converts those
            // fine. `flagsChanged` has no character.
            chars = type == .keyDown ? NSEvent(cgEvent: cgEvent)?.charactersIgnoringModifiers : nil
        default:
            return nil
        }
    }
}
