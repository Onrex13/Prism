import ServiceManagement

/// Thin wrapper over `SMAppService` to launch HubOS at login. Works with an
/// ad-hoc-signed app (no developer account needed).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("HubOS: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
