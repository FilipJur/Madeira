// VLTouch: Compat subset of VoidLink's GenericUtils.swift.
//
// Type name and member names must match VoidLink's GenericUtils, because the
// ported widget/editor/picker code calls them verbatim. Tips never fire here.

import Foundation
import UIKit

@objc public class GenericUtils: NSObject {

    // MARK: - Tips (never fire in this port)

    // VLTouch: no-op — first-run stick-wheel tip dropped with VoidLink's tip UI.
    @objc public static func handleStickWheelTip(in vc: UIViewController?) {}

    // VLTouch: no-op — velocity touchpad tip dropped with VoidLink's tip UI.
    @objc public static func handleVelocityBasedTouchpadTip(in vc: UIViewController?) {}

    // VLTouch: no-op — magnifier tip dropped with VoidLink's tip UI.
    @objc public static func handleMagnifierTip(in vc: UIViewController?) {}

    // VLTouch: no-op — gyro button tip dropped with VoidLink's tip UI.
    @objc public static func handleGyroButtonTip(in vc: UIViewController?) {}

    // VLTouch: no-op — slide-and-hold tip dropped with VoidLink's tip UI.
    @objc public static func handleSlideAndHoldFolderButtonTip(in vc: UIViewController?) {}

    // VLTouch: no-op — layout tool tip dropped with VoidLink's tip UI.
    @objc public static func handleLayoutToolTip(in vc: UIViewController?) {}

    // VLTouch: no-op — gaming folder tip dropped with VoidLink's tip UI.
    @objc public static func handleGamingLayoutFolderTip(in vc: UIViewController?) {}

    // VLTouch: no-op — widget panel tip dropped with VoidLink's tip UI.
    @objc public static func handleWidgetPanelTip(in vc: UIViewController?) {}

    // VLTouch: no-op — button mode tip dropped with VoidLink's tip UI.
    @objc public static func handleButtonModeTip(in vc: UIViewController?) {}

    // VLTouch: no-op — always reports already-tapped so no tip fires.
    @objc public static func isFirstTappingFolderInLayoutTool() -> Bool {
        return false
    }

    // MARK: - Push to talk

    // VLTouch: no-op — push-to-talk needs the dropped mic route check; never activates.
    @objc public static func canActivatePushToTalk(in vc: UIViewController?, redirectMic: Bool) -> Bool {
        return false
    }

    // MARK: - Keyboard

    // VLTouch: verbatim VoidLink default (true); the editor reads and writes it.
    @objc public static var autoPopSoftKeyboard: Bool = true

    // VLTouch: verbatim from VoidLink's GenericUtils.swift; editor placeholder styling.
    @objc public static func getAtrributedPlaceHolder(text: String) -> NSAttributedString {
        if #available(iOS 13.0, *) {
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15),
                    .foregroundColor: UIColor.placeholderText
                ])
        } else {
#if os(tvOS)
            let foregroundColor = UIColor(white: 1, alpha: 0.6)
#else
            let foregroundColor = UIColor.lightText
#endif
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15),
                    .foregroundColor: foregroundColor
                ])
        }
    }

    // MARK: - Gamepad overlay feature

    // VLTouch: no-op — overlay first-launch tip dropped with VoidLink's tip UI.
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

    // VLTouch: no-op — storefront dropped; the widget subset only reads this flag.
    @objc public static var pencilProPurchaseProcessedWithImportingWidgetTemplates: Bool = false
}
