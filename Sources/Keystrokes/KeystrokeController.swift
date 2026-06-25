import SwiftUI
import Combine

/// Bridges the low-level monitor to the SwiftUI overlay: receives key items,
/// keeps the visible list trimmed and auto-expiring, and shows/hides the
/// click-through overlay window.
@MainActor
final class KeystrokeController: ObservableObject {
    @Published private(set) var items: [KeyPressItem] = []
    /// True while the event tap is live and feeding the overlay.
    @Published private(set) var captureActive = false

    private let settings: SettingsStore
    private let interpreter = KeyInterpreter()
    private var monitor: KeystrokeMonitor?
    private var overlay: OverlayWindowController?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var isRunning: Bool { monitor?.isRunning ?? false }

    func start() {
        // Show the (transparent) overlay window first so it's ready, then wire
        // up the tap. The poller retries this each second until the tap exists.
        showOverlayIfNeeded()

        guard monitor == nil else { return }

        interpreter.reset()
        let monitor = KeystrokeMonitor { [weak self] raw in
            // Tap callback is already on the main run loop, but hop explicitly
            // so we satisfy the main-actor isolation of our published state.
            Task { @MainActor in self?.handle(raw) }
        }
        if monitor.start() {
            self.monitor = monitor
            captureActive = true
            NSLog("Showpoint: KeystrokeController.start — capture active")
        } else {
            captureActive = false
            NSLog("Showpoint: KeystrokeController.start — tap not ready, will retry")
        }

        startDebugInjectorIfRequested()
    }

    private func showOverlayIfNeeded() {
        guard overlay == nil else { return }
        let overlay = OverlayWindowController(
            rootView: KeystrokeOverlayView(controller: self, settings: settings)
        )
        overlay.show()
        self.overlay = overlay
    }

    // MARK: Debug — inject synthetic keys to validate rendering without a tap.
    // Enable with the PRESENTER_DEBUG_KEYS environment variable.
    private var debugInjectorStarted = false
    private func startDebugInjectorIfRequested() {
        guard !debugInjectorStarted,
              ProcessInfo.processInfo.environment["PRESENTER_DEBUG_KEYS"] != nil else { return }
        debugInjectorStarted = true
        let samples = ["A", "B", "Space", "⏎", "→"]
        var index = 0
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            let glyph = samples[index % samples.count]
            index += 1
            Task { @MainActor in
                self?.items.append(KeyPressItem(debugDisplay: glyph))
                self?.trim()
                if let id = self?.items.last?.id { self?.scheduleExpiry(of: id) }
            }
        }
    }

    func stop() {
        monitor?.stop()
        monitor = nil
        overlay?.hide()
        overlay = nil
        items.removeAll()
        captureActive = false
    }

    // MARK: Item lifecycle

    private func handle(_ raw: RawKeyEvent) {
        guard let item = interpreter.interpret(
            raw,
            showModifiers: settings.showModifiers,
            showMouseClicks: settings.showMouseClicks
        ) else { return }

        items.append(item)
        trim()
        scheduleExpiry(of: item.id)
    }

    private func trim() {
        let maxKeys = max(1, settings.maxKeys)
        if items.count > maxKeys {
            items.removeFirst(items.count - maxKeys)
        }
    }

    private func scheduleExpiry(of id: UUID) {
        let duration = max(0.3, settings.displayDuration)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            self?.items.removeAll { $0.id == id }
        }
    }
}
