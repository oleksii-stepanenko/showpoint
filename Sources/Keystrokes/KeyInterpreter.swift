import AppKit

/// Turns the raw stream of key/modifier/mouse events into the capsules we want
/// to show — collapsing the "press ⌘ → press C → release ⌘" sequence into a
/// single `⌘ C` instead of three separate capsules.
///
/// Rule: a held modifier is only shown on its own if it is tapped and released
/// **without** any other key being pressed in between (a "bare" modifier tap).
/// Otherwise it folds into the key combo produced on `keyDown`.
@MainActor
final class KeyInterpreter {
    /// The union of every modifier held since the last time all modifiers were
    /// released — so "⌘ then ⇧ then release" reports ⇧⌘, not just the last one.
    private var peakModifiers: NSEvent.ModifierFlags = []
    /// Set once a real key is pressed while modifiers are held, which suppresses
    /// the bare-modifier capsule on release.
    private var modifierConsumed = false

    func reset() {
        peakModifiers = []
        modifierConsumed = false
    }

    func interpret(_ event: RawKeyEvent, showModifiers: Bool, showMouseClicks: Bool) -> KeyPressItem? {
        switch event.type {
        case .leftMouseDown:
            return showMouseClicks ? KeyPressItem(display: "Left Click", isMouse: true) : nil
        case .rightMouseDown:
            return showMouseClicks ? KeyPressItem(display: "Right Click", isMouse: true) : nil

        case .keyDown:
            let heldNow = event.modifierFlags.intersection(KeyPressItem.relevantModifiers)
            // A key only "consumes" the held modifiers if it was actually pressed
            // together with one — a plain letter must not suppress a later bare
            // modifier tap.
            if !heldNow.isEmpty { modifierConsumed = true }
            guard let glyph = KeyPressItem.mainGlyph(keyCode: event.keyCode, chars: event.chars) else {
                return nil
            }
            let mods = showModifiers ? KeyPressItem.modifierGlyphs(heldNow) : []
            return KeyPressItem(modifiers: mods, display: glyph, isMouse: false)

        case .flagsChanged:
            let current = event.modifierFlags.intersection(KeyPressItem.relevantModifiers)

            if current.isEmpty {
                // All modifiers released. Emit a bare-modifier capsule only if no
                // key consumed them while held.
                let held = peakModifiers
                let consumed = modifierConsumed
                reset()
                if !consumed, !held.isEmpty, showModifiers {
                    return KeyPressItem(display: KeyPressItem.modifierGlyphs(held).joined(), isMouse: false)
                }
                return nil
            } else {
                // A modifier went down (or a partial release). Track the peak and
                // wait — we don't know yet whether it'll be used in a combo.
                peakModifiers.formUnion(current)
                return nil
            }

        default:
            return nil
        }
    }
}
