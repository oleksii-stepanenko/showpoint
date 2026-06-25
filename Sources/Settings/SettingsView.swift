import SwiftUI

/// The standard macOS Settings window, one tab per feature — matching the shape
/// of Presentify/KeyScreen preferences.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            KeystrokeSettingsView()
                .tabItem { Label("Keystrokes", systemImage: "keyboard") }

            CursorSettingsView()
                .tabItem { Label("Cursor", systemImage: "cursorarrow.rays") }

            AnnotateSettingsView()
                .tabItem { Label("Annotate", systemImage: "pencil.tip.crop.circle") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 400)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var settings = SettingsStore.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.setEnabled(on) }
            } header: {
                Text("Startup")
            }

            Section {
                LabeledContent("Accessibility") {
                    if env.permissions.accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant…") { env.permissions.requestAccessibility() }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Accessibility is required to read keystrokes and track the cursor.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Shortcut key", selection: $settings.tapModifier) {
                    ForEach(TapModifier.allCases) { Text("\($0.glyph) \($0.label)").tag($0) }
                }
                let m = settings.tapModifier
                LabeledContent("Double-tap \(m.glyph) \(m.label)", value: "Toggle cursor highlight")
                LabeledContent("Triple-tap \(m.glyph) \(m.label)", value: "Toggle annotation")
            } header: {
                Text("Hands-free shortcuts")
            } footer: {
                Text("Tap the key cleanly (nothing else held). Fires ~0.3 s after your last tap.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            env.permissions.refresh()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

private struct KeystrokeSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show keystrokes", isOn: $settings.keystrokesEnabled)
                LabeledContent("Status") {
                    if !settings.keystrokesEnabled {
                        Text("Off").foregroundStyle(.secondary)
                    } else if env.keystrokes.captureActive {
                        Label("Capturing", systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(.green)
                    } else if !env.permissions.accessibilityGranted {
                        Label("Waiting for Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Starting…", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Show modifier keys", isOn: $settings.showModifiers)
                Toggle("Show mouse clicks", isOn: $settings.showMouseClicks)
                Picker("Position", selection: $settings.position) {
                    ForEach(OverlayPosition.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Display")
            }

            Section("Appearance") {
                LabeledContent("Font size") {
                    Slider(value: $settings.fontSize, in: 14...64, step: 1)
                    Text("\(Int(settings.fontSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                }
                LabeledContent("Opacity") {
                    Slider(value: $settings.overlayOpacity, in: 0.2...1.0)
                }
                LabeledContent("Hide after") {
                    Slider(value: $settings.displayDuration, in: 0.5...6.0, step: 0.5)
                    Text("\(settings.displayDuration, specifier: "%.1f")s").monospacedDigit().foregroundStyle(.secondary)
                }
                Stepper("Max keys shown: \(settings.maxKeys)", value: $settings.maxKeys, in: 1...10)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CursorSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    // Bridge the persisted hex string to a SwiftUI ColorPicker.
    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: settings.cursorColorHex) },
            set: { settings.cursorColorHex = $0.hexString }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Highlight cursor", isOn: $settings.cursorHighlightEnabled)
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                Picker("Shape", selection: $settings.cursorShape) {
                    ForEach(CursorShape.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Highlight")
            } footer: {
                Text("Tip: double-tap the \(settings.tapModifier.glyph) \(settings.tapModifier.label) key to toggle the highlight (requires Accessibility).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Appearance") {
                LabeledContent("Size") {
                    Slider(value: $settings.cursorSize, in: 24...120, step: 1)
                    Text("\(Int(settings.cursorSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                }
                LabeledContent("Opacity") {
                    Slider(value: $settings.cursorOpacity, in: 0.1...1.0)
                }
            }

            Section("Clicks") {
                Toggle("Show ripple on click", isOn: $settings.cursorClickRipple)
                Toggle("Show only while clicking", isOn: $settings.cursorOnlyOnClick)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AnnotateSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Annotate screen", isOn: $settings.annotationEnabled)
                LabeledContent("Line weight") {
                    Slider(value: $settings.annotationLineWidth, in: 1...24, step: 1)
                    Text("\(Int(settings.annotationLineWidth)) pt").monospacedDigit().foregroundStyle(.secondary)
                }
            } header: {
                Text("Drawing")
            } footer: {
                Text("Triple-tap \(settings.tapModifier.glyph) \(settings.tapModifier.label) to start/stop. Each tool has a letter shortcut (shown on its button). Tab cycles the color through the palette. Esc exits the current tool, then exits annotation. Delete/Backspace removes the selected object. Pen keeps drawing until you press Esc.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettingsView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 14) {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable().frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 64)).foregroundStyle(.tint)
            }

            Text("Showpoint").font(.title2).bold()
            Text("Keystrokes, cursor highlight & screen annotation for presentations.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider().frame(width: 220)

            Form {
                LabeledContent("Author", value: "Oleksii Stepanenko")
                LabeledContent("License", value: "Free")
                LabeledContent("Version", value: version)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 130)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ComingSoonView: View {
    let feature: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(feature).font(.headline)
            Text("Coming in the next build.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
