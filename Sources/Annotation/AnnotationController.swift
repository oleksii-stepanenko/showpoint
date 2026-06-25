import AppKit
import SwiftUI

/// A borderless, non-activating panel that *captures* the mouse so the user can
/// draw — without stealing focus from the app being presented. Keyboard (Esc /
/// Delete) is handled by `AnnotationKeyInterceptor` via an event tap, so we don't
/// need to activate. Exit via the toolbar's Done button, Esc, or a triple-tap of
/// Control.
final class AnnotationPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        isFloatingPanel = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the annotation panel, the shared drawing model, and the keyboard
/// handling (ESC / Delete) while annotation is active.
@MainActor
final class AnnotationController: ObservableObject {
    @Published private(set) var isActive = false

    let model: AnnotationModel
    private let settings: SettingsStore
    private var panel: AnnotationPanel?
    private let keyInterceptor = AnnotationKeyInterceptor()

    init(settings: SettingsStore) {
        self.settings = settings
        self.model = AnnotationModel(settings: settings)
        keyInterceptor.onEscape = { [weak self] in self?.handleEscape() }
        keyInterceptor.onDelete = { [weak self] in self?.model.deleteSelected() }
        keyInterceptor.onClearAll = { [weak self] in self?.model.clear() }
        keyInterceptor.onUndo = { [weak self] in self?.model.undo() }
        keyInterceptor.onToggleFill = { [weak self] in self?.model.toggleFill() }
        keyInterceptor.onToolKey = { [weak self] tool in self?.settings.annotationTool = tool }
        keyInterceptor.onCycleColor = { [weak self] in self?.model.cycleColor() }
    }

    func start() {
        guard panel == nil else { return }

        let screen = Self.screenUnderMouse()
        let panel = AnnotationPanel(screen: screen)
        panel.contentView = NSHostingView(
            rootView: AnnotationRootView(
                model: model,
                settings: settings,
                onDone: { [weak self] in self?.exitAnnotation() }
            )
        )
        panel.makeKeyAndOrderFront(nil)   // key (mouse + popovers) without activating the app
        self.panel = panel

        keyInterceptor.install()          // Esc / Delete via event tap
        isActive = true

        if ProcessInfo.processInfo.environment["PRESENTER_DEBUG_ANNOTATION"] != nil {
            model.debugSeed()
        }
    }

    func stop() {
        keyInterceptor.uninstall()
        panel?.orderOut(nil)
        panel = nil
        model.endPenSession()
        isActive = false
        // Drawings are intentionally kept in `model` across hide/show.
    }

    // MARK: Keyboard

    private func handleEscape() {
        switch AnnotationEscape.outcome(tool: settings.annotationTool) {
        case .exitTool:
            model.endPenSession()
            settings.annotationTool = .select
        case .exitAnnotation:
            exitAnnotation()
        }
    }

    /// Flips the setting so the menu/settings toggle stay in sync (which calls stop()).
    private func exitAnnotation() {
        settings.annotationEnabled = false
    }

    private static func screenUnderMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
