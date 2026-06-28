import SwiftUI
import Combine

/// Owns the long-lived objects that the whole app shares: settings, the
/// permission gate, and the feature controllers. Scenes reach these through
/// `@EnvironmentObject`.
@MainActor
final class AppEnvironment: ObservableObject {
    let settings = SettingsStore.shared
    let permissions = PermissionsManager()
    let keystrokes: KeystrokeController
    let cursorHighlight: CursorHighlightController
    let annotation: AnnotationController

    private var cancellables = Set<AnyCancellable>()
    private var permissionTimer: Timer?

    /// Control taps drive hands-free toggles: double-tap → presentation overlays
    /// (cursor highlight + keystrokes, together), triple-tap → annotation.
    /// Lazy so `self` is initialized before capture.
    private lazy var controlTaps = MultiTapControlDetector { [weak self] count in
        guard let self else { return }
        switch count {
        case 2: self.togglePresentationOverlays()
        case 3: self.settings.annotationEnabled.toggle()
        default: break
        }
    }

    /// Turns the cursor highlight and keystroke overlay on or off as a pair —
    /// if either is on, both go off; otherwise both come on.
    private func togglePresentationOverlays() {
        let enable = !(settings.cursorHighlightEnabled || settings.keystrokesEnabled)
        settings.cursorHighlightEnabled = enable
        settings.keystrokesEnabled = enable
    }

    init() {
        keystrokes = KeystrokeController(settings: settings)
        cursorHighlight = CursorHighlightController(settings: settings)
        annotation = AnnotationController(settings: settings)

        permissions.refresh()

        // Restore the last-enabled state on launch.
        applyKeystrokeState(settings.keystrokesEnabled)
        applyCursorHighlightState(settings.cursorHighlightEnabled)
        applyAnnotationState(settings.annotationEnabled)

        // React to the toggles. IMPORTANT: use the value the publisher delivers,
        // not a re-read of the property — `@Published` emits during `willSet`, so
        // reading the property back here would return the *old* value.
        settings.$keystrokesEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in self?.applyKeystrokeState(enabled) }
            .store(in: &cancellables)

        settings.$cursorHighlightEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in self?.applyCursorHighlightState(enabled) }
            .store(in: &cancellables)

        settings.$annotationEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in self?.applyAnnotationState(enabled) }
            .store(in: &cancellables)

        controlTaps.modifier = settings.tapModifier
        settings.$tapModifier
            .dropFirst()
            .sink { [weak self] modifier in self?.controlTaps.modifier = modifier }
            .store(in: &cancellables)

        startPermissionWatcher()
    }

    /// Annotation's mouse drawing needs no permission, but its keyboard shortcuts
    /// (Esc, the tool keys, the Text tool) ride a CGEventTap that requires
    /// Accessibility. Prompt for it if it's missing — drawing works meanwhile, and
    /// the watcher re-arms the keyboard the moment permission is granted.
    func applyAnnotationState(_ enabled: Bool) {
        if enabled {
            permissions.refresh()
            if !permissions.accessibilityGranted {
                permissions.requestAccessibility()   // shows the system prompt
            }
            annotation.start()
        } else {
            annotation.stop()
        }
    }

    /// Cursor highlight needs no special permission, so it starts/stops directly
    /// with its toggle.
    func applyCursorHighlightState(_ enabled: Bool) {
        if enabled {
            cursorHighlight.start()
        } else {
            cursorHighlight.stop()
        }
    }

    /// Turn the keystroke overlay on or off. When the user wants it on but the
    /// Accessibility permission isn't granted yet, we prompt once and leave the
    /// toggle ON — the watcher below starts capture automatically the moment the
    /// permission is granted, so the user never has to toggle twice.
    func applyKeystrokeState(_ enabled: Bool) {
        guard enabled else {
            keystrokes.stop()
            return
        }
        permissions.refresh()
        if permissions.accessibilityGranted {
            keystrokes.start()
        } else {
            permissions.requestAccessibility()   // shows the system prompt
        }
    }

    /// Polls the Accessibility permission once a second. Brings the keystroke
    /// overlay and the global double-tap shortcut to life as soon as permission
    /// is granted.
    private func startPermissionWatcher() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let wasGranted = permissions.accessibilityGranted
        permissions.refresh()

        if permissions.accessibilityGranted {
            // The Control-tap shortcuts need keyboard monitoring.
            if !controlTaps.isInstalled { controlTaps.install() }
            if settings.keystrokesEnabled && !keystrokes.isRunning {
                keystrokes.start()
            }
            // If the cursor highlight is on, arm the consuming Ctrl+scroll tap so
            // the content underneath stops scrolling while resizing the spotlight.
            if settings.cursorHighlightEnabled {
                cursorHighlight.installScrollTapIfPossible()
            }
            // If annotation is already showing, bring its keyboard to life now.
            annotation.reinstallKeyboardIfNeeded()
        }

        if permissions.accessibilityGranted != wasGranted {
            NSLog("Showpoint: accessibility granted -> \(permissions.accessibilityGranted)")
        }
    }
}
