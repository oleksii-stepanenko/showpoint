import AppKit
import ApplicationServices
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

    /// Spotlight-dim state, driven by the controller's Ctrl+scroll monitor.
    /// `dimRadius` is the clear-circle radius in points; the controller shares one
    /// accumulator across screens so resizing carries between displays.
    private var dimActive = false
    private var dimRadius: CGFloat = 220

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
        let onThisScreen = NSPointInRect(location, screen.frame)
        let point = CGPoint(x: location.x - screen.frame.minX,
                            y: location.y - screen.frame.minY)

        if onThisScreen {
            hostView.showHalo(at: point)
        } else {
            hostView.hideHalo()
        }

        updateDim(point: point, onThisScreen: onThisScreen)
    }

    /// Called by the controller when a Ctrl+scroll arrives.
    func activateDim(radius: CGFloat) {
        dimRadius = radius
        dimActive = true
    }

    /// The spotlight lives only while Control stays held; releasing it fades the
    /// dim out. Opacity is read live so the settings slider previews immediately.
    private func updateDim(point: CGPoint, onThisScreen: Bool) {
        guard dimActive else { return }
        guard NSEvent.modifierFlags.contains(.control) else {
            dimActive = false
            hostView.hideDim()
            return
        }
        let opacity = CGFloat(settings.dimSpotlightOpacity)
        if onThisScreen {
            hostView.showDim(at: point, radius: dimRadius, opacity: opacity)
        } else {
            hostView.showFullDim(opacity: opacity)
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
    private var scrollMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    /// Consuming tap that stops the content underneath from scrolling while you
    /// resize the spotlight. Installed only when Accessibility is granted; until
    /// then the non-consuming `scrollMonitor` below handles resize instead.
    private var scrollTap: ScrollSpotlightTap?

    /// Shared clear-circle radius (points) for the Ctrl+scroll spotlight, carried
    /// across displays and resize gestures. Clamped to a sane on-screen range.
    private var dimRadius: CGFloat = 220
    private static let dimRadiusRange: ClosedRange<CGFloat> = 60...1400
    /// Points of radius change per unit of scroll delta.
    private static let dimRadiusPerScroll: CGFloat = 9

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

        // Ctrl+scroll spotlight. The global monitor needs no Accessibility, so it
        // keeps the feature working permission-free — but it's listen-only, so the
        // content underneath also scrolls. When Accessibility is available we also
        // install a consuming tap (below) that swallows Ctrl+scroll; the monitor
        // then steps aside via `scrollTap` to avoid resizing twice.
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.scrollWheel]
        ) { [weak self] event in
            let delta = event.scrollingDeltaY
            let control = event.modifierFlags.contains(.control)
            Task { @MainActor in
                guard let self, self.scrollTap?.isInstalled != true else { return }
                self.handleScroll(deltaY: delta, control: control)
            }
        }

        installScrollTapIfPossible()

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
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        scrollTap?.uninstall()
        scrollTap = nil
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

    /// Holding Control while scrolling activates the spotlight and resizes its
    /// clear circle (scroll up grows, down shrinks). Gated on the feature toggle —
    /// it's already implicitly gated on the highlight being on, since this monitor
    /// only exists while the controller is running.
    private func handleScroll(deltaY: CGFloat, control: Bool) {
        guard control, settings.dimSpotlightEnabled, deltaY != 0 else { return }
        dimRadius = min(max(dimRadius + deltaY * Self.dimRadiusPerScroll,
                            Self.dimRadiusRange.lowerBound),
                        Self.dimRadiusRange.upperBound)
        overlays.forEach { $0.activateDim(radius: dimRadius) }
    }

    /// Installs the consuming Ctrl+scroll tap if Accessibility is granted (so the
    /// content underneath stops scrolling while you resize). Safe to call repeatedly
    /// — the `AppEnvironment` permission watcher retries this once permission lands.
    func installScrollTapIfPossible() {
        guard scrollTap == nil, AXIsProcessTrusted() else { return }
        let tap = ScrollSpotlightTap { [weak self] delta in
            // The tap fires on the main thread; hop to the main actor to mutate
            // overlay state. Control is implied — the tap only reports Ctrl+scroll.
            Task { @MainActor in self?.handleScroll(deltaY: delta, control: true) }
        }
        tap.isEnabled = settings.dimSpotlightEnabled
        tap.install()
        guard tap.isInstalled else { return }   // tapCreate can still fail
        scrollTap = tap

        // Keep the tap's consume decision in sync with the feature toggle so it
        // passes Ctrl+scroll through untouched when the spotlight is turned off.
        settings.$dimSpotlightEnabled
            .sink { [weak self] enabled in self?.scrollTap?.isEnabled = enabled }
            .store(in: &cancellables)
    }
}
