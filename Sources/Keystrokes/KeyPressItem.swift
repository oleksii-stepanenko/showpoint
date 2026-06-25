import AppKit

/// One thing shown in the overlay: a key combo, a bare modifier tap, or a mouse
/// click. Pure display model — the glyph/modifier decisions are made by
/// `KeyInterpreter`.
struct KeyPressItem: Identifiable, Equatable {
    let id = UUID()
    /// Modifier glyphs in canonical order, e.g. ["⌃","⌥","⇧","⌘"].
    let modifiers: [String]
    /// The main glyph, e.g. "A", "⏎", "Space", or "Left Click".
    let display: String
    let isMouse: Bool

    static func == (lhs: KeyPressItem, rhs: KeyPressItem) -> Bool { lhs.id == rhs.id }

    /// Full text rendered in the capsule.
    var text: String {
        modifiers.isEmpty ? display : "\(modifiers.joined()) \(display)"
    }

    init(modifiers: [String] = [], display: String, isMouse: Bool = false) {
        self.modifiers = modifiers
        self.display = display
        self.isMouse = isMouse
    }

    /// For previews / the debug injector only.
    init(debugDisplay: String) {
        self.init(display: debugDisplay)
    }

    // MARK: Glyph mapping (used by the interpreter)

    static let relevantModifiers: NSEvent.ModifierFlags =
        [.command, .shift, .option, .control, .function, .capsLock]

    static func modifierGlyphs(_ flags: NSEvent.ModifierFlags) -> [String] {
        var glyphs: [String] = []
        if flags.contains(.function) { glyphs.append("fn") }
        if flags.contains(.control)  { glyphs.append("⌃") }
        if flags.contains(.option)   { glyphs.append("⌥") }
        if flags.contains(.shift)    { glyphs.append("⇧") }
        if flags.contains(.command)  { glyphs.append("⌘") }
        if flags.contains(.capsLock) { glyphs.append("⇪") }
        return glyphs
    }

    static func mainGlyph(keyCode: UInt16, chars: String?) -> String? {
        if let special = specialKeys[keyCode] { return special }
        guard let chars, !chars.isEmpty else { return nil }
        let upper = chars.uppercased()
        // Reject control characters (e.g. from ⌃-combos); printable only.
        return upper.unicodeScalars.allSatisfy { $0.value >= 0x20 } ? upper : nil
    }

    /// Hardware keycodes with no printable character or that read better as a
    /// symbol. Standard macOS virtual key codes.
    private static let specialKeys: [UInt16: String] = [
        36: "⏎",   76: "⏎",   48: "⇥",   49: "Space",
        51: "⌫",   117: "⌦",  53: "⎋",   114: "Ins",
        123: "←",  124: "→",  125: "↓",  126: "↑",
        115: "↖",  119: "↘",  116: "⇞",  121: "⇟",
        122: "F1", 120: "F2", 99: "F3",  118: "F4",
        96: "F5",  97: "F6",  98: "F7",  100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
