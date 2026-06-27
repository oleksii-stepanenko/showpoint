import SwiftUI

extension Color {
    /// Creates a color from a "#RRGGBB" string. Falls back to yellow on a bad
    /// value so the highlight is never invisible.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .yellow
            return
        }
        self = Color(
            red:   Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue:  Double(value & 0xFF) / 255.0
        )
    }

    /// Black or white — whichever reads better on top of `hex`. Used for text
    /// drawn inside a colored callout bubble so light fills don't get white text.
    static func contrastingText(onHex hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else { return .white }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        // Perceived luminance (Rec. 601). Bright fills → black text, dark → white.
        let luma = 0.299 * r + 0.587 * g + 0.114 * b
        return luma > 0.6 ? .black : .white
    }

    /// "#RRGGBB" representation, for persisting a `ColorPicker` selection.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .yellow
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
