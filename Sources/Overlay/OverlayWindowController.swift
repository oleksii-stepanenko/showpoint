import AppKit
import SwiftUI

/// A borderless, transparent, click-through window that floats above everything
/// (including full-screen apps) and spans a single screen. Hosts an arbitrary
/// SwiftUI view. Reused for keystrokes now and cursor highlight/annotation next.
///
/// The window follows the screen the mouse is on, so in multi-display setups the
/// overlay always appears where the user is actually working — not on whichever
/// screen happens to be `NSScreen.main`.
final class OverlayWindowController {
    private let window: OverlayWindow
    private var followTimer: Timer?
    private var currentScreen: NSScreen?

    init<Root: View>(rootView: Root) {
        let screen = Self.screenUnderMouse()
        window = OverlayWindow(contentRect: screen.frame)
        currentScreen = screen

        let hosting = NSHostingView(rootView: rootView)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
    }

    func show() {
        moveToScreen(Self.screenUnderMouse())
        window.orderFrontRegardless()
        startFollowingMouseScreen()
    }

    func hide() {
        followTimer?.invalidate()
        followTimer = nil
        window.orderOut(nil)
    }

    // MARK: Following the active screen

    private func startFollowingMouseScreen() {
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            let screen = Self.screenUnderMouse()
            if screen.frame != self.currentScreen?.frame {
                self.moveToScreen(screen)
            }
        }
    }

    private func moveToScreen(_ screen: NSScreen) {
        currentScreen = screen
        window.setFrame(screen.frame, display: true)
    }

    private static func screenUnderMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

/// The actual window. Transparent, never takes focus, ignores the mouse so
/// clicks pass through to the app underneath, and rides along across Spaces.
final class OverlayWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
