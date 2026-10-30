// VLTouch: Compat subset of VoidLink's Database layer — the settings the ported
// widget/editor code reads. Values come from Madeira's persisted settings store
// with VoidLink's factory defaults (false), so callers take the "feature off"
// path. Enum raw values are verbatim from VoidLink's DataManager.swift — they
// are load-bearing for archived profiles.

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
        // VLTouch: safe defaults — Madeira has no redirectMic setting; VoidLink factory value is false.
        SettingsSnapshot()
    }

    func retrieveSettings() -> SettingsSnapshot? {
        // VLTouch: safe defaults — Madeira has no unlockDisplayOrientation setting; VoidLink factory value is false.
        SettingsSnapshot()
    }
}
