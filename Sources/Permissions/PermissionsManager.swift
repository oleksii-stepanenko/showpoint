import AppKit
import ApplicationServices

/// Tracks the macOS Accessibility permission that the keystroke event tap (and,
/// later, cursor tracking) require. Screen Recording — needed only for zoom —
/// will be added when that feature lands.
@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var accessibilityGranted = false

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// Triggers the system prompt that deep-links the user to
    /// Settings → Privacy & Security → Accessibility.
    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
