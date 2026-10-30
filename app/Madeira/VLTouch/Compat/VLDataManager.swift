// VLTouch: Compat stub; S5 makes real what the runtime needs.
import Foundation

/// Snapshot the touch widgets read from the app's persisted settings. Both
/// members default to VoidLink's factory value, so callers take the
/// "feature off" path.
final class SettingsSnapshot: NSObject {
    @objc var redirectMic: Bool = false
    @objc var unlockDisplayOrientation: Bool = false
}
// VLTouch: lives in VoidLink's DataManager.swift; the widget subset only reads .keepWidgetSize.
@objc enum WidgetSizeTransition: Int {
    case keepWidgetSize
    case transitionWithOrientation
}
// VLTouch: verbatim from VoidLink's DataManager.swift; raw values are load-bearing for archived profiles.
@objc enum ControllerGyroSwitchMode: Int {
    case disabled
    case pressToToggle
    case holdDown
}

@objc enum TouchMode: Int {
    case relative = 0
    case native = 1
    case absolute = 2
    case disabled = 3
    case nativeOnly = 4
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
