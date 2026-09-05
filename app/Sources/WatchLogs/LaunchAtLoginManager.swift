import ServiceManagement

/// Manages launch-at-login using SMAppService.mainApp (macOS 13+).
@MainActor
final class LaunchAtLoginManager {
    /// Current registration status.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
    
    /// Register or unregister the app to launch at login.
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status == .enabled {
                return  // Already enabled
            }
            try SMAppService.mainApp.register()
        } else {
            if SMAppService.mainApp.status == .notRegistered {
                return  // Already disabled
            }
            try SMAppService.mainApp.unregister()
        }
    }
}
