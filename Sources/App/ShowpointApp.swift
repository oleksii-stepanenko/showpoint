import SwiftUI

/// Entry point. A menu-bar-only app (LSUIElement) that exposes presentation
/// helpers — keystroke display, cursor highlight, and screen annotation.
@main
struct ShowpointApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Shared app-wide state. Created once and injected into every scene.
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        MenuBarExtra("Showpoint", systemImage: "cursorarrow.rays") {
            MenuBarContent()
                .environmentObject(env)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(env)
        }
    }
}

/// We only need the delegate to keep the app alive as an accessory and to
/// kick off the initial permission + start-up state once the app is ready.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["PRESENTER_SELFTEST"] != nil {
            KeyInterpreterSelfTest.run()   // prints results and exits
        }
        NSApp.setActivationPolicy(.accessory)
    }
}
