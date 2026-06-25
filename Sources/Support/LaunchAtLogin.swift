import ServiceManagement
import Foundation

/// Registers Showpoint as a login item via `SMAppService` (macOS 13+). The system
/// is the source of truth — no preference to persist ourselves.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let status) where status != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        } catch {
            NSLog("Showpoint: launch-at-login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }
}
