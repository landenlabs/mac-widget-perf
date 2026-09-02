// Copyright (c) 2026 LanDen Labs - Dennis Lang
import Foundation

/// Registers/unregisters the running executable as a login item via System Events.
///
/// The app is a plain SwiftPM executable (no .app bundle), so `Bundle.main.bundlePath`
/// resolves to the *containing folder*, not the binary — pointing a login item at a
/// folder does nothing on login. `executablePath` must be used instead.
enum LoginItem {
    static let defaultsKey = "launchAtLogin"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Re-applies the stored preference. Call at app launch so a login item that
    /// previously failed to register (e.g. before this path fix, or due to a
    /// declined automation prompt) self-heals without the user retoggling it.
    static func syncWithStoredPreference() {
        set(enabled: isEnabled)
    }

    static func set(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)

        guard let path = Bundle.main.executablePath else { return }
        let script = enabled
            ? """
              tell application "System Events"
                  try
                      delete (every login item whose path is "\(path)")
                  end try
                  make login item at end with properties {path:"\(path)", hidden:false}
              end tell
              """
            : """
              tell application "System Events"
                  try
                      delete (every login item whose path is "\(path)")
                  end try
              end tell
              """

        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err {
            NSLog("MacWidgetPerf: failed to \(enabled ? "add" : "remove") login item: \(err)")
        }
    }
}
