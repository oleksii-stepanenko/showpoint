import AppKit
import CoreGraphics

/// While annotation is active, intercepts Esc and Delete/Backspace via a
/// `CGEventTap` and consumes them (so they don't reach the app underneath).
/// A tap works regardless of window focus, which is why annotation can keep its
/// non-activating panel (no focus steal) and still handle the keyboard.
/// Requires Accessibility.
final class AnnotationKeyInterceptor {
    var onEscape: (() -> Void)?
    var onDelete: (() -> Void)?
    var onClearAll: (() -> Void)?
    var onUndo: (() -> Void)?
    var onToggleFill: (() -> Void)?
    var onToolKey: ((AnnotationTool) -> Void)?
    var onCycleColor: (() -> Void)?

    // Text-editing mode: while a callout is open, keystrokes feed the text box
    // instead of firing tool shortcuts.
    var isEditingText: (() -> Bool)?
    var onTextInput: ((String) -> Void)?
    var onTextBackspace: (() -> Void)?
    var onTextNewline: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isInstalled: Bool { eventTap != nil }

    func install() {
        guard eventTap == nil else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,           // can consume events
            eventsOfInterest: mask,
            callback: annotationKeyCallback,
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

    /// Returns true if the event should be consumed.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // While a text callout is open, route keys into the text box.
        if isEditingText?() == true {
            return handleTextEditing(keyCode: keyCode, event: event)
        }

        switch keyCode {
        case 53:                              // Esc
            // Dispatch async — the handler may tear down this tap.
            DispatchQueue.main.async { [weak self] in self?.onEscape?() }
            return true
        case 51:                              // Delete / Backspace (⇧ = clear all)
            if event.flags.contains(.maskShift) {
                DispatchQueue.main.async { [weak self] in self?.onClearAll?() }
            } else {
                DispatchQueue.main.async { [weak self] in self?.onDelete?() }
            }
            return true
        case 117:                             // Forward-Delete
            DispatchQueue.main.async { [weak self] in self?.onDelete?() }
            return true
        case 48:                              // Tab — cycle color
            DispatchQueue.main.async { [weak self] in self?.onCycleColor?() }
            return true
        default:
            return handleCharacterShortcut(event)
        }
    }

    /// Keystroke routing while typing into a text callout. The rule is
    /// bare-vs-modified, NOT "consume everything":
    ///   • Bare keys are consumed — printable ones go into the box, Return/
    ///     Backspace/Esc do their thing, arrows/fn are swallowed. This is what
    ///     stops a typed "t"/"a"/… from firing a tool shortcut, and stops arrows
    ///     from leaking to the app underneath (e.g. flipping slides).
    ///   • Modifier combos pass through (return false) so ⌘Q / ⌘Tab / ⌘Space /
    ///     Spotlight keep working — except ⌘V, which pastes into the box.
    private func handleTextEditing(keyCode: Int64, event: CGEvent) -> Bool {
        let modifiers = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate])
        if !modifiers.isEmpty {
            if modifiers == .maskCommand,
               typedCharacter(event)?.lowercased().first == "v" {
                DispatchQueue.main.async { [weak self] in
                    if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                        self?.onTextInput?(pasted)
                    }
                }
                return true
            }
            return false   // let the system keep its ⌘-combos
        }

        switch keyCode {
        case 53:                              // Esc — commit (handled by onEscape)
            DispatchQueue.main.async { [weak self] in self?.onEscape?() }
        case 51, 117:                         // Backspace / Forward-Delete
            DispatchQueue.main.async { [weak self] in self?.onTextBackspace?() }
        case 36, 76:                          // Return / keypad Enter — newline
            DispatchQueue.main.async { [weak self] in self?.onTextNewline?() }
        default:
            if let string = typedCharacter(event), Self.isPrintable(string) {
                DispatchQueue.main.async { [weak self] in self?.onTextInput?(string) }
            }
        }
        return true   // every bare key is consumed while typing
    }

    /// True for real text input — filters control characters and the private-use
    /// scalars AppKit returns for arrows / function keys.
    private static func isPrintable(_ string: String) -> Bool {
        guard let scalar = string.unicodeScalars.first else { return false }
        if scalar.value < 0x20 { return false }
        if (0xF700...0xF8FF).contains(scalar.value) { return false }
        return true
    }

    /// Character-based shortcuts: ⌘Z = undo; bare F = toggle fill; bare tool
    /// letters select the tool. Uses the typed character so it respects layout.
    private func handleCharacterShortcut(_ event: CGEvent) -> Bool {
        let character = typedCharacter(event)?.lowercased().first

        // ⌘Z — undo (only command allowed).
        if event.flags.contains(.maskCommand),
           event.flags.intersection([.maskControl, .maskAlternate]).isEmpty,
           character == "z" {
            DispatchQueue.main.async { [weak self] in self?.onUndo?() }
            return true
        }

        // Bare letter (no ⌘/⌃/⌥).
        guard event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
              let character else { return false }

        if character == "f" {
            DispatchQueue.main.async { [weak self] in self?.onToggleFill?() }
            return true
        }
        if let tool = AnnotationTool.forShortcut(character) {
            DispatchQueue.main.async { [weak self] in self?.onToolKey?(tool) }
            return true
        }
        return false
    }

    private func typedCharacter(_ event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

private func annotationKeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<AnnotationKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
    return interceptor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
