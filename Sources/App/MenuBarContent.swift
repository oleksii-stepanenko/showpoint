import SwiftUI

/// The menu shown when the user clicks the status-bar icon. Mirrors the shape
/// of Presentify/KeyScreen menus: quick toggles up top, settings + quit below.
struct MenuBarContent: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var settings: SettingsStore

    init() {
        // `@EnvironmentObject` isn't available in init; we re-bind in body.
        _settings = ObservedObject(wrappedValue: SettingsStore.shared)
    }

    var body: some View {
        Toggle("Show Keystrokes", isOn: $settings.keystrokesEnabled)

        if !env.permissions.accessibilityGranted {
            Divider()
            Text("Accessibility permission needed for keystrokes")
            Button("Open Accessibility Settings…") {
                env.permissions.openAccessibilitySettings()
            }
        }

        Divider()

        Toggle("Highlight Cursor", isOn: $settings.cursorHighlightEnabled)
        Toggle("Annotate Screen", isOn: $settings.annotationEnabled)

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Showpoint") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
