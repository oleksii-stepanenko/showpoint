import AppKit
import SwiftUI
import Combine

/// One full-screen, click-through overlay per display. The halo is a CALayer
/// repositioned every display-link frame by polling the cursor location — this
/// is what makes it track tightly and never "disappear" (event monitors drop and
/// coalesce moves; per-frame polling does not). One window per screen keeps each
/// at its native scale and refresh rate, so nothing renders blurry.
@MainActor
final class CursorScreenOverlay {
    let screen: NSScreen
    private let window: OverlayWindow
    private let hostView: CursorHostView
    private let settings: SettingsStore
    private var displayLink: CADisplayLink?

    init(screen: NSScreen, settings: SettingsStore) {
        self.screen = screen
        self.settings = settings

        window = OverlayWindow(contentRect: screen.frame)
        hostView = CursorHostView(frame: NSRect(origin: .zero, size: screen.frame.size))
        hostView.scale = screen.backingScaleFactor
        window.contentView = hostView
    }

    func start() {
        reconfigure()
        window.orderFrontRegardless()

        // A display link bound to this view runs at this screen's refresh rate.
        let link = hostView.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        window.orderOut(nil)
    }

    func reconfigure() {
        hostView.configure(
            color: NSColor(Color(hex: settings.cursorColorHex)),
            size: settings.cursorSize,
            opacity: settings.cursorOpacity,
            shape: settings.cursorShape,
            showHalo: !settings.cursorOnlyOnClick
        )
    }

    @objc private func tick() {
        let location = NSEvent.mouseLocation
        if NSPointInRect(location, screen.frame) {
            hostView.showHalo(at: CGPoint(x: location.x - screen.frame.minX,
                                          y: location.y - screen.frame.minY))
        } else {
            hostView.hideHalo()
        }
    }

    func emitRippleIfCursorHere() {
        let location = NSEvent.mouseLocation
        guard NSPointInRect(location, screen.frame) else { return }
        hostView.emitRipple(
            at: CGPoint(x: location.x - screen.frame.minX, y: location.y - screen.frame.minY),
            color: NSColor(Color(hex: settings.cursorColorHex)),
            size: settings.cursorSize
        )
    }
}

/// Owns the per-screen overlays and the global click monitor.
@MainActor
final class CursorHighlightController: ObservableObject {
    @Published private(set) var isActive = false

    private let settings: SettingsStore
    private var overlays: [CursorScreenOverlay] = []
    private var clickMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard overlays.isEmpty else { return }
        rebuild()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.handleClick() }
        }

        // Re-render the halo when any cursor setting changes.
        settings.objectWillChange
            .sink { [weak self] in
                Task { @MainActor in self?.overlays.forEach { $0.reconfigure() } }
            }
            .store(in: &cancellables)

        // Rebuild overlays when displays are added/removed or rearranged.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuild() }
        }

        isActive = true
    }

    func stop() {
        overlays.forEach { $0.stop() }
        overlays.removeAll()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        cancellables.removeAll()
        isActive = false
    }

    private func rebuild() {
        overlays.forEach { $0.stop() }
        overlays = NSScreen.screens.map { CursorScreenOverlay(screen: $0, settings: settings) }
        overlays.forEach { $0.start() }
    }

    private func handleClick() {
        guard settings.cursorClickRipple else { return }
        overlays.forEach { $0.emitRippleIfCursorHere() }
    }
}
