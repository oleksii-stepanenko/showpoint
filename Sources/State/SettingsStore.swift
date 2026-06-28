import SwiftUI
import Combine

/// Where the keystroke overlay sits on screen.
enum OverlayPosition: String, CaseIterable, Identifiable {
    case bottomLeading, bottomCenter, bottomTrailing
    case topLeading, topCenter, topTrailing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bottomLeading:  return "Bottom Left"
        case .bottomCenter:   return "Bottom Center"
        case .bottomTrailing: return "Bottom Right"
        case .topLeading:     return "Top Left"
        case .topCenter:      return "Top Center"
        case .topTrailing:    return "Top Right"
        }
    }

    /// SwiftUI alignment used to pin the keystroke stack inside the full-screen
    /// overlay window.
    var alignment: Alignment {
        switch self {
        case .bottomLeading:  return .bottomLeading
        case .bottomCenter:   return .bottom
        case .bottomTrailing: return .bottomTrailing
        case .topLeading:     return .topLeading
        case .topCenter:      return .top
        case .topTrailing:    return .topTrailing
        }
    }
}

/// User-facing settings, persisted to `UserDefaults`. Single shared instance so
/// the menu, the settings window, and the overlay all read the same values.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    // MARK: Keystroke display
    @Published var keystrokesEnabled: Bool { didSet { defaults.set(keystrokesEnabled, forKey: Key.keystrokesEnabled) } }
    @Published var showModifiers: Bool      { didSet { defaults.set(showModifiers, forKey: Key.showModifiers) } }
    @Published var showMouseClicks: Bool    { didSet { defaults.set(showMouseClicks, forKey: Key.showMouseClicks) } }
    @Published var fontSize: Double         { didSet { defaults.set(fontSize, forKey: Key.fontSize) } }
    @Published var overlayOpacity: Double   { didSet { defaults.set(overlayOpacity, forKey: Key.overlayOpacity) } }
    @Published var displayDuration: Double  { didSet { defaults.set(displayDuration, forKey: Key.displayDuration) } }
    @Published var maxKeys: Int             { didSet { defaults.set(maxKeys, forKey: Key.maxKeys) } }
    @Published var position: OverlayPosition {
        didSet { defaults.set(position.rawValue, forKey: Key.position) }
    }

    // MARK: Cursor highlight
    @Published var cursorHighlightEnabled: Bool { didSet { defaults.set(cursorHighlightEnabled, forKey: Key.cursorEnabled) } }
    @Published var cursorColorHex: String       { didSet { defaults.set(cursorColorHex, forKey: Key.cursorColorHex) } }
    @Published var cursorSize: Double            { didSet { defaults.set(cursorSize, forKey: Key.cursorSize) } }
    @Published var cursorOpacity: Double         { didSet { defaults.set(cursorOpacity, forKey: Key.cursorOpacity) } }
    @Published var cursorShape: CursorShape      { didSet { defaults.set(cursorShape.rawValue, forKey: Key.cursorShape) } }
    @Published var cursorClickRipple: Bool       { didSet { defaults.set(cursorClickRipple, forKey: Key.cursorClickRipple) } }
    @Published var cursorOnlyOnClick: Bool       { didSet { defaults.set(cursorOnlyOnClick, forKey: Key.cursorOnlyOnClick) } }

    // MARK: Spotlight dim (Ctrl+scroll)
    @Published var dimSpotlightEnabled: Bool     { didSet { defaults.set(dimSpotlightEnabled, forKey: Key.dimEnabled) } }
    @Published var dimSpotlightOpacity: Double   { didSet { defaults.set(dimSpotlightOpacity, forKey: Key.dimOpacity) } }

    // MARK: Annotation
    @Published var annotationEnabled: Bool       { didSet { defaults.set(annotationEnabled, forKey: Key.annEnabled) } }
    @Published var annotationColorHex: String    { didSet { defaults.set(annotationColorHex, forKey: Key.annColorHex) } }
    @Published var annotationLineWidth: Double    { didSet { defaults.set(annotationLineWidth, forKey: Key.annLineWidth) } }
    @Published var annotationTool: AnnotationTool { didSet { defaults.set(annotationTool.rawValue, forKey: Key.annTool) } }
    @Published var annotationFilled: Bool         { didSet { defaults.set(annotationFilled, forKey: Key.annFilled) } }

    // MARK: Shortcuts
    @Published var tapModifier: TapModifier { didSet { defaults.set(tapModifier.rawValue, forKey: Key.tapModifier) } }

    private init() {
        defaults.register(defaults: [
            Key.showModifiers: true,
            Key.showMouseClicks: true,
            Key.fontSize: 28.0,
            Key.overlayOpacity: 0.85,
            Key.displayDuration: 2.0,
            Key.maxKeys: 4,
            Key.position: OverlayPosition.bottomCenter.rawValue,
            Key.cursorColorHex: "#FFCC00",
            Key.cursorSize: 62.0,
            Key.cursorOpacity: 0.45,
            Key.cursorShape: CursorShape.disc.rawValue,
            Key.cursorClickRipple: true,
            Key.cursorOnlyOnClick: false,
            Key.dimEnabled: true,
            Key.dimOpacity: 0.6,
            Key.annColorHex: "#FF3B30",
            Key.annLineWidth: 4.0,
            Key.annTool: AnnotationTool.pen.rawValue,
            Key.annFilled: false,
            Key.tapModifier: TapModifier.control.rawValue,
        ])

        keystrokesEnabled = defaults.bool(forKey: Key.keystrokesEnabled)
        showModifiers     = defaults.bool(forKey: Key.showModifiers)
        showMouseClicks   = defaults.bool(forKey: Key.showMouseClicks)
        fontSize          = defaults.double(forKey: Key.fontSize)
        overlayOpacity    = defaults.double(forKey: Key.overlayOpacity)
        displayDuration   = defaults.double(forKey: Key.displayDuration)
        maxKeys           = defaults.integer(forKey: Key.maxKeys)
        position          = OverlayPosition(rawValue: defaults.string(forKey: Key.position) ?? "")
            ?? .bottomCenter

        cursorHighlightEnabled = defaults.bool(forKey: Key.cursorEnabled)
        cursorColorHex    = defaults.string(forKey: Key.cursorColorHex) ?? "#FFCC00"
        cursorSize        = defaults.double(forKey: Key.cursorSize)
        cursorOpacity     = defaults.double(forKey: Key.cursorOpacity)
        cursorShape       = CursorShape(rawValue: defaults.string(forKey: Key.cursorShape) ?? "") ?? .disc
        cursorClickRipple = defaults.bool(forKey: Key.cursorClickRipple)
        cursorOnlyOnClick = defaults.bool(forKey: Key.cursorOnlyOnClick)
        dimSpotlightEnabled = defaults.bool(forKey: Key.dimEnabled)
        dimSpotlightOpacity = defaults.double(forKey: Key.dimOpacity)

        annotationEnabled   = defaults.bool(forKey: Key.annEnabled)
        annotationColorHex  = defaults.string(forKey: Key.annColorHex) ?? "#FF3B30"
        annotationLineWidth = defaults.double(forKey: Key.annLineWidth)
        annotationTool      = AnnotationTool(rawValue: defaults.string(forKey: Key.annTool) ?? "") ?? .pen
        annotationFilled    = defaults.bool(forKey: Key.annFilled)
        tapModifier         = TapModifier(rawValue: defaults.string(forKey: Key.tapModifier) ?? "") ?? .control
    }

    private enum Key {
        static let keystrokesEnabled = "ks.enabled"
        static let showModifiers     = "ks.showModifiers"
        static let showMouseClicks   = "ks.showMouseClicks"
        static let fontSize          = "ks.fontSize"
        static let overlayOpacity    = "ks.overlayOpacity"
        static let displayDuration   = "ks.displayDuration"
        static let maxKeys           = "ks.maxKeys"
        static let position          = "ks.position"
        static let cursorEnabled     = "cursor.enabled"
        static let cursorColorHex    = "cursor.colorHex"
        static let cursorSize        = "cursor.size"
        static let cursorOpacity     = "cursor.opacity"
        static let cursorShape       = "cursor.shape"
        static let cursorClickRipple = "cursor.clickRipple"
        static let cursorOnlyOnClick = "cursor.onlyOnClick"
        static let dimEnabled        = "cursor.dimSpotlight.enabled"
        static let dimOpacity        = "cursor.dimSpotlight.opacity"
        static let annEnabled        = "ann.enabled"
        static let annColorHex       = "ann.colorHex"
        static let annLineWidth      = "ann.lineWidth"
        static let annTool           = "ann.tool"
        static let annFilled         = "ann.filled"
        static let tapModifier       = "shortcut.tapModifier"
    }
}

/// Tools for screen annotation. `select` is the pointer used to click/move/delete
/// existing objects. (Blur is intentionally deferred.)
enum AnnotationTool: String, CaseIterable, Identifiable {
    case select, pen, highlighter, line, arrow, rectangle, ellipse, counter, text, spotlight
    var id: String { rawValue }

    var label: String {
        switch self {
        case .select:      return "Select"
        case .pen:         return "Pen"
        case .highlighter: return "Highlighter"
        case .line:        return "Line"
        case .arrow:       return "Arrow"
        case .rectangle:   return "Rectangle"
        case .ellipse:     return "Ellipse"
        case .counter:     return "Counter"
        case .text:        return "Text"
        case .spotlight:   return "Spotlight"
        }
    }

    var systemImage: String {
        switch self {
        case .select:      return "cursorarrow"
        case .pen:         return "pencil.tip"
        case .highlighter: return "highlighter"
        case .line:        return "line.diagonal"
        case .arrow:       return "line.diagonal.arrow"
        case .rectangle:   return "rectangle"
        case .ellipse:     return "circle"
        case .counter:     return "1.circle"
        case .text:        return "text.bubble"
        case .spotlight:   return "rays"
        }
    }

    /// Freehand tools collect every point; shape tools keep just start + current.
    var isFreehand: Bool { self == .pen || self == .highlighter }
    /// Closed shapes that can be outline or filled.
    var isClosedShape: Bool { self == .rectangle || self == .ellipse }
    var drawsObjects: Bool { self != .select }

    /// Single-key shortcut (active while annotating).
    var shortcut: Character {
        switch self {
        case .select:      return "v"
        case .pen:         return "p"
        case .highlighter: return "h"
        case .line:        return "l"
        case .arrow:       return "a"
        case .rectangle:   return "r"
        case .ellipse:     return "o"
        case .counter:     return "c"
        case .text:        return "t"
        case .spotlight:   return "s"
        }
    }

    var shortcutLabel: String { String(shortcut).uppercased() }

    static func forShortcut(_ character: Character) -> AnnotationTool? {
        allCases.first { $0.shortcut == character }
    }
}

/// Curated pastel palette shown in the color popover (Shottr-style). Eight
/// distinct hues.
enum AnnotationPalette {
    static let presets: [String] = [
        "#FF6B6B", "#FFA94D", "#FFD43B", "#69DB7C",
        "#4DABF7", "#9775FA", "#F783AC", "#343A40",
    ]
}

/// Modifier key used for the hands-free multi-tap toggles.
enum TapModifier: String, CaseIterable, Identifiable {
    case control, option, command, shift
    var id: String { rawValue }

    var label: String {
        switch self {
        case .control: return "Control"
        case .option:  return "Option"
        case .command: return "Command"
        case .shift:   return "Shift"
        }
    }

    var glyph: String {
        switch self {
        case .control: return "⌃"
        case .option:  return "⌥"
        case .command: return "⌘"
        case .shift:   return "⇧"
        }
    }
}

/// What an ESC press does while annotating, depending on the active tool.
enum AnnotationEscape {
    enum Outcome { case exitTool, exitAnnotation }

    /// A drawing tool active → drop back to Select; already on Select → leave
    /// annotation entirely.
    static func outcome(tool: AnnotationTool) -> Outcome {
        tool == .select ? .exitAnnotation : .exitTool
    }
}

/// Shape of the cursor highlight.
enum CursorShape: String, CaseIterable, Identifiable {
    case disc, ring, squircle, rhombus
    var id: String { rawValue }
    var label: String {
        switch self {
        case .disc:     return "Disc"
        case .ring:     return "Ring"
        case .squircle: return "Squircle"
        case .rhombus:  return "Rhombus"
        }
    }
}
