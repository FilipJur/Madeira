// VLTouch: Compat stub; S5 makes real what the runtime needs.
//
//  GenericUtils.swift
//  VoidLink (compat subset)
//
//  Type name and member names must match VoidLink's GenericUtils, because the
//  ported widget/editor/picker code calls them verbatim. Tips never fire here.
//

import Foundation
import UIKit

@objc public class GenericUtils: NSObject {

    // MARK: - Tips (never fire in this port)

    @objc public static func handleStickWheelTip(in vc: UIViewController?) {}

    @objc public static func handleVelocityBasedTouchpadTip(in vc: UIViewController?) {}

    @objc public static func handleMagnifierTip(in vc: UIViewController?) {}

    @objc public static func handleGyroButtonTip(in vc: UIViewController?) {}

    @objc public static func handleSlideAndHoldFolderButtonTip(in vc: UIViewController?) {}

    @objc public static func handleLayoutToolTip(in vc: UIViewController?) {}

    @objc public static func handleGamingLayoutFolderTip(in vc: UIViewController?) {}

    @objc public static func handleWidgetPanelTip(in vc: UIViewController?) {}

    @objc public static func handleButtonModeTip(in vc: UIViewController?) {}

    @objc public static func isFirstTappingFolderInLayoutTool() -> Bool {
        return false
    }

    // MARK: - Push to talk

    @objc public static func canActivatePushToTalk(in vc: UIViewController?, redirectMic: Bool) -> Bool {
        return false
    }

    // MARK: - Keyboard

    @objc public static var autoPopSoftKeyboard: Bool = false

    @objc public static func getAtrributedPlaceHolder(text: String) -> NSAttributedString {
        return NSAttributedString(string: text)
    }

    // MARK: - Gamepad overlay feature

    @objc public static func isFirstLaunchGamepadOverlayFeature() -> Bool {
        return false
    }

    @objc public static func gamepadOverlayFeatureTipTitle() -> String {
        LocalizationHelper.localizedString(forKey: "Gamepad Overlay")
    }

    @objc public static func gamepadOverlayFeatureTipMessage() -> String {
        LocalizationHelper.localizedString(forKey: "gamepadOverlayFeatureTip")
    }

    // MARK: - Add-on purchase

    @objc public static var pencilProPurchaseProcessedWithImportingWidgetTemplates: Bool = false
}
