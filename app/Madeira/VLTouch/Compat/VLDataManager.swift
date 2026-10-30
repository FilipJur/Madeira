// VLTouch: Compat stub; S5 makes real what the runtime needs.
import Foundation

/// Snapshot the touch widgets read from the app's persisted settings. Both
/// members default to VoidLink's factory value, so callers take the
/// "feature off" path.
final class SettingsSnapshot: NSObject {
    @objc var redirectMic: Bool = false
    @objc var unlockDisplayOrientation: Bool = false
}

final class DataManager: NSObject {

    override init() {
        super.init()
    }

    func getSettings() -> SettingsSnapshot? {
        SettingsSnapshot()
    }

    func retrieveSettings() -> SettingsSnapshot? {
        SettingsSnapshot()
    }
}
