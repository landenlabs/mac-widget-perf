// Copyright (c) 2026 LanDen Labs - Dennis Lang
import Foundation
import ServiceManagement

/// Registers/unregisters the app as a login item via SMAppService.
///
/// SMAppService relaunches the app's own .app bundle at login — it only
/// works when the running binary is packaged inside a real bundle (see
/// `build_app.sh`). A bare SwiftPM executable has no bundle for the system
/// to relaunch, which previously caused the login item to fall back to
/// opening the binary in a foreground Terminal shell.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("MacWidgetPerf: failed to \(enabled ? "register" : "unregister") login item: \(error)")
        }
    }
}
