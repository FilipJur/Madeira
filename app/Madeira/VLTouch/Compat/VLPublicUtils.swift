// VLTouch: Compat subset of VoidLink's PublicUtils.swift — every member the
// ported widget/editor/picker code calls, plus the screen/foldable surface that
// feeds it (OSCProfilesManager template choice, MotionHandler matrix source).
// Bodies are verbatim from VoidLink's Utility/PublicUtils.swift (foldable
// detection, scene-based screen resolution, symbol names); members nothing in
// the subset calls are dropped, each named in the report.
//
// Type name and member names must match VoidLink's PublicUtils, because the
// ported code calls them verbatim.

import Foundation
import ObjectiveC
import UIKit
import AVFoundation
import GameController

@objc public class PublicUtils: NSObject {

    /// True when running in an Apple platform simulator.
    @objc public static let isSimulator: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()

    /// This port has no tvOS target.
    @objc public static let isTVOS: Bool = {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }()

    @objc public static var isIPhone: Bool = {
        return UIDevice.current.userInterfaceIdiom == .phone
    }()

    @objc public static var isIPad: Bool = {
        return UIDevice.current.userInterfaceIdiom == .pad
    }()

    @objc public static let isFoldableIPhoneUserDefaultsKey = "isFoldableIPhone"

    /// Do not register a default for this key: nil means detection is still needed.
    @MainActor private static var cachedFoldableIPhone: Bool? {
        UserDefaults.standard.object(forKey: isFoldableIPhoneUserDefaultsKey) as? Bool
    }

    /// Loaded from persistent storage, or detected before the main interface is built.
    /// Read on the main thread. Hardware capability remains cached as poses change.
    @MainActor @objc public private(set) static var isFoldableIPhone: Bool = {
        return cachedFoldableIPhone ?? false
    }()

    private static let foldableRAMCacheLock = NSLock()
    private static var foldableRAMCacheValue: Bool?

    /// Resolve once on the main actor; subsequent callers only read memory.
    @objc public static var isFoldableRAMCached: Bool {
        foldableRAMCacheLock.lock()
        let cached = foldableRAMCacheValue
        foldableRAMCacheLock.unlock()
        if let cached { return cached }

        if Thread.isMainThread {
            return MainActor.assumeIsolated { initializeFoldableRAMCache() }
        }
        // Do not hold the cache lock while waiting for the main queue. This is
        // a computed getter so Swift's static-let initialization lock cannot
        // deadlock a simultaneous first read on the main thread.
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { initializeFoldableRAMCache() }
        }
    }

    @MainActor private static func initializeFoldableRAMCache() -> Bool {
        foldableRAMCacheLock.lock()
        defer { foldableRAMCacheLock.unlock() }
        if let cached = foldableRAMCacheValue { return cached }
        let result: Bool
        if #available(iOS 27.0, *) {
            result = isFoldableIPhone
        } else {
            result = false
        }
        foldableRAMCacheValue = result
        return result
    }

    /// Mirrors UIKit's hinge states without requiring availability checks at readers.
    @objc(VLHingeStatus) public enum HingeStatus: Int {
        case unknown = 0
        case closed = 1
        case partiallyOpen = 2
        case fullyOpen = 3
    }

    /// Updated on the main thread before hingeStatusDidChangeNotification is posted.
    @MainActor @objc public private(set) static var hingeStatus: HingeStatus = .unknown
    @objc public static let hingeStatusDidChangeNotification = Notification.Name("VoidLinkHingeStatusDidChange")
    @objc public static let windowGeometryDidChangeNotification = Notification.Name("VoidLinkWindowGeometryDidChange")

    @MainActor private static var foldableIPhoneDetectionStarted = false
    @MainActor private static var foldableIPhoneDetectionFinished = cachedFoldableIPhone != nil
    @MainActor private static var foldableIPhoneDetectionCallbacks: [() -> Void] = []
    @MainActor private static var hingeInteractionAssociationKey: UInt8 = 0
    @MainActor private static var foldableIPhoneDetectionTimeout: DispatchWorkItem?

    /// Call once from window setup, before constructing any business UI.
    /// UIKit needs a visible window to report its initial hinge state. While
    /// waiting, show the same background as the launch screen without blocking
    /// the main thread. A stored true or false bypasses this startup wait entirely.
    @MainActor @objc(prepareFoldableIPhoneDetectionInWindow:completion:)
    public static func prepareFoldableIPhoneDetection(in window: UIWindow, completion: @escaping () -> Void) {
        if foldableIPhoneDetectionFinished {
            _ = initializeFoldableRAMCache()
            completion()
            // Foldable devices still observe live poses without gating startup.
            if isFoldableIPhone { installHingeStatusObservation(in: window) }
            return
        }
        foldableIPhoneDetectionCallbacks.append(completion)
        guard !foldableIPhoneDetectionStarted else { return }
        foldableIPhoneDetectionStarted = true
        #if os(iOS) && compiler(>=6.4)
        if #available(iOS 27.1, *), UIDevice.current.userInterfaceIdiom == .phone {
            let launchController = UIViewController()
            launchController.view.backgroundColor = .systemBackground
            window.rootViewController = launchController
            let timeout = DispatchWorkItem {
                // Cache the timeout fallback so ordinary iPhones only wait once.
                NSLog("Foldable iPhone detection timed out; caching false")
                finishFoldableIPhoneDetection(false)
            }
            foldableIPhoneDetectionTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: timeout)
            window.makeKeyAndVisible()
            installHingeStatusObservation(in: window)
            return
        }
        #endif
        #if compiler(>=6.4)
        finishFoldableIPhoneDetection(false)
        #else
        // Xcode 26.6 lacks the hinge API; do not persist a hardware conclusion.
        finishFoldableIPhoneDetection(nil)
        #endif
    }

    /// Each application window owns its listener for its entire lifetime.
    @MainActor private static func installHingeStatusObservation(in window: UIWindow) {
        #if os(iOS) && compiler(>=6.4)
        if #available(iOS 27.1, *), UIDevice.current.userInterfaceIdiom == .phone {
            guard window.windowScene?.session.role == .windowApplication,
                  objc_getAssociatedObject(window, &hingeInteractionAssociationKey) == nil else { return }
            let interaction = UIHingeInteraction { interaction, update in
                guard let window = interaction.view as? UIWindow,
                      window.windowScene != nil, !window.isHidden else { return }
                guard let hinge = update.hinge else {
                    // Losing a hinge hierarchy is not a change in the physical pose.
                    // Keep the last known status after startup has completed.
                    if !foldableIPhoneDetectionFinished {
                        finishFoldableIPhoneDetection(false)
                    }
                    return
                }
                let nextStatus = HingeStatus(rawValue: hinge.status.rawValue) ?? .unknown
                let didChange = hingeStatus != nextStatus
                hingeStatus = nextStatus
                finishFoldableIPhoneDetection(true)
                // Angle updates within the same state do not require UI rebuilds.
                if didChange {
                    NotificationCenter.default.post(name: hingeStatusDidChangeNotification, object: window)
                }
            }
            objc_setAssociatedObject(window, &hingeInteractionAssociationKey, interaction, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            window.addInteraction(interaction)
        }
        #endif
    }

    @MainActor private static func finishFoldableIPhoneDetection(_ result: Bool?) {
        // A late positive sample after a timeout is still a confirmed capability.
        if let result {
            isFoldableIPhone = result
            if cachedFoldableIPhone != result {
                UserDefaults.standard.set(result, forKey: isFoldableIPhoneUserDefaultsKey)
            }
        }
        guard !foldableIPhoneDetectionFinished else { return }
        foldableIPhoneDetectionFinished = true
        foldableIPhoneDetectionTimeout?.cancel()
        foldableIPhoneDetectionTimeout = nil
        _ = initializeFoldableRAMCache()
        let callbacks = foldableIPhoneDetectionCallbacks
        foldableIPhoneDetectionCallbacks.removeAll()
        callbacks.forEach { $0() }
    }

    @objc public static var isRunningOnMacAsiPadApp: Bool = {
        if #available(iOS 14.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac
        }
        return false
    }()

    @objc public static let iOS26Available: Bool = {
        if #available(iOS 26.0, tvOS 26.0, *) {
            return true
        } else {
            return false
        }
    }()

    @objc public static let isGUIWidgetPickerAvailable: Bool = {
        if #available(iOS 13.0, tvOS 13.0, *) {
            return true
        } else {
            return false
        }
    }()

    @objc public static func isLandscape() -> Bool {
#if os(tvOS)
        return true
#else
        if #available(iOS 13.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.session.role == .windowApplication && $0.activationState == .foregroundActive })
            else { return false }
            return windowScene.interfaceOrientation.isLandscape
        } else { return PublicUtils.screenWidth > PublicUtils.screenHeight }
#endif
    }

    @objc public static func quitSymbol() -> String {
        if #available(iOS 14.0, tvOS 14.0, *) {
            return "pip.exit"
        } else {
            return "arrow.left.square"
        }
    }

    @objc public static func disconnectSymbol() -> String {
        if #available(iOS 18.0, tvOS 18.0, *) {
            return "personalhotspot.slash"
        } else if #available(iOS 14.0, tvOS 14.0, *) {
            return "rectangle.slash"
        } else {
            return "nosign"
        }
    }

    @objc public static func viewIsLandscape(_ view: UIView?) -> Bool {
        guard let view else { return false }
        return view.bounds.width > view.bounds.height
    }

    private static let currentScreenLock = NSLock()
    private static var publishedCurrentScreen: UIScreen?

    private static func publishCurrentScreen(_ screen: UIScreen) {
        currentScreenLock.lock()
        publishedCurrentScreen = screen
        currentScreenLock.unlock()
    }

    /// The local application screen, independent of external display scenes.
    /// UI readers resolve it live. Worker threads read the last published screen
    /// without traversing UIKit scenes or synchronously waiting for the main queue.
    @objc public static var currentScreen: UIScreen {
        if Thread.isMainThread, #available(iOS 13.0, tvOS 13.0, *) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .filter { $0.session.role == .windowApplication && $0.activationState != .unattached }
            let active = scenes.filter { $0.activationState == .foregroundActive }
            let scene = active.first { $0.windows.contains { $0.isKeyWindow } }
                ?? active.first
                ?? scenes.first { $0.activationState == .foregroundInactive }
            if let screen = scene?.screen {
                publishCurrentScreen(screen)
                return screen
            }
        }
        currentScreenLock.lock()
        let screen = publishedCurrentScreen
        currentScreenLock.unlock()
        // Only startup and pre-scene systems need this legacy fallback.
        return screen ?? UIScreen.main
    }

    @objc(refreshCurrentScreenForWindow:)
    public static func refreshCurrentScreen(for window: UIWindow?) {
        guard Thread.isMainThread, let window else { return }
        if #available(iOS 13.0, tvOS 13.0, *) {
            guard let scene = window.windowScene, scene.session.role == .windowApplication else { return }
            publishCurrentScreen(scene.screen)
        } else {
            publishCurrentScreen(window.screen)
        }
        // In a multi-window app, a geometry callback from an inactive window
        // must not displace the foreground key scene's default screen.
        _ = currentScreen
    }

    /// Prefer the caller's window, including an explicitly external render view.
    @objc(screenForView:)
    public static func screen(for view: UIView?) -> UIScreen {
        if Thread.isMainThread, let window = view?.window {
            if #available(iOS 13.0, tvOS 13.0, *), let scene = window.windowScene {
                return scene.screen
            }
            return window.screen
        }
        return currentScreen
    }

    @objc public static var screenWidth: CGFloat {
        return currentScreen.bounds.width
    }

    @objc public static var screenHeight: CGFloat {
        return currentScreen.bounds.height
    }

    @objc public static var refreshRate: CGFloat {
        return CGFloat(currentScreen.maximumFramesPerSecond)
    }

    @objc public static func rootViewController() -> UIViewController? {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .windows
                .first { $0.isKeyWindow }?
                .rootViewController
        } else {
            return UIApplication.shared.keyWindow?.rootViewController
        }
    }

    @objc public static func topViewController() -> UIViewController? {
        return topViewController(from: rootViewController())
    }

    private static func topViewController(from rootViewController: UIViewController?) -> UIViewController? {
        if let navigationController = rootViewController as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = rootViewController as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }

        if let splitViewController = rootViewController as? UISplitViewController,
           let lastViewController = splitViewController.viewControllers.last {
            return topViewController(from: lastViewController)
        }

        if let presentedViewController = rootViewController?.presentedViewController {
            return topViewController(from: presentedViewController)
        }

        return rootViewController
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
}
