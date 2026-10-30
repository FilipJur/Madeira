// VLTouch: Compat stub; S5 makes real what the runtime needs.
//
//  PublicUtils.swift
//  VoidLink (compat subset)
//
//  Type name and member names must match VoidLink's PublicUtils, because the
//  ported widget/editor/picker code calls them verbatim.
//

import Foundation
import UIKit

@objc public class PublicUtils: NSObject {

    /// Mirrors UIKit's hinge states without requiring availability checks at readers.
    @objc(VLHingeStatus) public enum HingeStatus: Int {
        case unknown = 0
        case closed = 1
        case partiallyOpen = 2
        case fullyOpen = 3
    }

    /// True when running in an Apple platform simulator.
    @objc public static let isSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    /// This port has no tvOS target.
    @objc public static let isTVOS: Bool = false

    @objc public static var isIPhone: Bool = {
        return UIDevice.current.userInterfaceIdiom == .phone
    }()

    @objc public static var isIPad: Bool = {
        return UIDevice.current.userInterfaceIdiom == .pad
    }()

    @objc public static let isGUIWidgetPickerAvailable: Bool = true

    /// No foldable support in this port.
    @objc public static var isFoldableIPhone: Bool = false

    @objc public static var isFoldableRAMCached: Bool {
        return false
    }

    /// Updated on the main thread before hingeStatusDidChangeNotification is posted.
    @objc public static var hingeStatus: HingeStatus = .unknown

    @objc public static var isRunningOnMacAsiPadApp: Bool = false

    @objc public static let iOS26Available: Bool = {
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
    }()

    @objc public static func isLandscape() -> Bool {
        return false
    }

    @objc public static func viewIsLandscape(_ view: UIView?) -> Bool {
        guard let view else { return false }
        return view.bounds.width > view.bounds.height
    }

    /// The local application screen, independent of external display scenes.
    @objc public static var currentScreen: UIScreen {
        if Thread.isMainThread {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState != .unattached }
            let active = scenes.filter { $0.activationState == .foregroundActive }
            let scene = active.first { $0.windows.contains { $0.isKeyWindow } }
                ?? active.first
            if let screen = scene?.screen {
                return screen
            }
        }
        return UIScreen.main
    }

    /// Prefer the caller's window, including an explicitly external render view.
    @objc(screenForView:)
    public static func screen(for view: UIView?) -> UIScreen {
        if Thread.isMainThread, let window = view?.window {
            if let scene = window.windowScene {
                return scene.screen
            }
            return window.screen
        }
        return currentScreen
    }

    @objc public static func topViewController() -> UIViewController? {
        var controller = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }?
            .rootViewController
        while true {
            if let navigationController = controller as? UINavigationController {
                controller = navigationController.visibleViewController
            } else if let tabBarController = controller as? UITabBarController {
                controller = tabBarController.selectedViewController
            } else if let presentedViewController = controller?.presentedViewController {
                controller = presentedViewController
            } else {
                return controller
            }
        }
    }

    public static func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    @objc(openUrl:)
    static func openUrl(_ urlString: String) {
        guard let url = URL(string: urlString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    @objc public static func quitSymbol() -> String {
        if #available(iOS 14.0, *) {
            return "pip.exit"
        } else {
            return "arrow.left.square"
        }
    }

    @objc public static func disconnectSymbol() -> String {
        if #available(iOS 18.0, *) {
            return "personalhotspot.slash"
        } else if #available(iOS 14.0, *) {
            return "rectangle.slash"
        } else {
            return "nosign"
        }
    }
}
