// VLTouch: Compat subset of VoidLink's ThemeManager.swift — the members the
// ported picker code calls. userInterfaceStyle() and appPrimaryColor are
// verbatim from VoidLink; the trait plumbing (foldable pinning, overrides,
// system-change propagation) is dropped, each named in the report.

import UIKit

@objcMembers
final class ThemeManager: NSObject {

    static let ThemeDidChangeNotification = "ThemeDidChangeNotification"

    // VLTouch: follows the system trait via PublicUtils.currentScreen (VoidLink's
    // ThemeManager.swift:74-77 does the same on non-foldables; the override state,
    // _userInterfaceStyle cache, and system-change propagation are dropped).
    class func userInterfaceStyle() -> UIUserInterfaceStyle {
        if #available(iOS 13.0, *) {
            return PublicUtils.currentScreen.traitCollection.userInterfaceStyle
        }
        return .light
    }

    // VLTouch: verbatim from VoidLink's ThemeManager.swift:365-372 (#0A84FF, no dark variant).
    static var appPrimaryColor: UIColor {
        return UIColor(
            red: 0.0,
            green: 0.48,
            blue: 1.0,
            alpha: 1.0
        ) // #0A84FF
    }
}
