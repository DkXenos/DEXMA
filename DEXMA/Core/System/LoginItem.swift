import os
import ServiceManagement

/// Launch at login via `SMAppService.mainApp` (macOS 13+; no helper app needed).
enum LoginItem {
    private static let logger = Logger(category: "LoginItem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription, privacy: .public)")
        }
        // The user switched DEXMA off in System Settings before: only they can re-allow it.
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
