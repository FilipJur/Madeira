// VLTouch: Compat stub (D4: controller navigation is dropped, API preserved); S5 makes real what the runtime needs.
import UIKit
import Combine // VLTouch: GamepadOverlayStateCenter is an ObservableObject (verbatim from ControllerUtil.swift).

// ControllerUtil's element vocabulary travels with the navigator API here,
// because the compat ControllerUtil carries only its five functions.
@objc enum ControllerElementPosition: Int {
    case left
    case right
    case middle
    case undefined
}

@objc enum ControllerElement: Int32 {
    case a = 0x1000
    case b = 0x2000
    case x = 0x4000
    case y = 0x8000

    case dpadUp    = 0x0001
    case dpadDown  = 0x0002
    case dpadLeft  = 0x0004
    case dpadRight = 0x0008

    case leftShoulder  = 0x0100
    case rightShoulder = 0x0200

    case leftStickButton  = 0x0040
    case rightStickButton = 0x0080

    case start   = 0x0010
    case select  = 0x0020
    case special = 0x0400

    case paddle1 = 0x010000
    case paddle2 = 0x020000
    case paddle3 = 0x040000
    case paddle4 = 0x080000
    case touchpadButton = 0x100000
    case misc = 0x200000

    case leftTrigger  = 0x400000
    case rightTrigger = 0x800000

    case leftStick  = 0x800010
    case leftStickX = 0x80011
    case leftStickY = 0x800012
    case rightStick  = 0x800020
    case rightStickX = 0x800021
    case rightStickY = 0x800022

    case dpad = 0x800013
    case abxy = 0x800023

    case null = 0xFFFFFF
}
// VLTouch: field shape from VoidLink's ControllerUtil.swift; the ported picker code renders the
// six defaulted fields. Dropped with the controller-navigation feature: nothing publishes live
// snapshots (VLTouch never assigns valueChangedHandler — Madeira's GamepadInput owns it).
struct GamepadOverlaySnapshot: Equatable {
    var pressedButtons: Set<ControllerElement> = []
    var dpadHighlight: Int = 0
    var leftStick: CGPoint = .zero
    var rightStick: CGPoint = .zero
    var leftTrigger: CGFloat = 0
    var rightTrigger: CGFloat = 0

    static let idle = GamepadOverlaySnapshot()
}
// VLTouch: shape from VoidLink's ControllerUtil.swift; nothing publishes live snapshots (see above).
final class GamepadOverlayStateCenter: NSObject, ObservableObject {
    static let shared = GamepadOverlayStateCenter()

    @Published private(set) var snapshot: GamepadOverlaySnapshot = .idle

    func publish(snapshot: GamepadOverlaySnapshot) {
        DispatchQueue.main.async {
            self.snapshot = snapshot
        }
    }

    static func clearSharedState() {
        shared.publish(snapshot: .idle)
    }
}

@objcMembers
final class ControllerNavigationElement: NSObject {
    var control: ControllerElement
    var action: String
    var isInAction: Bool = false

    init(control: ControllerElement, action: String) {
        self.control = control
        self.action = action
        super.init()
    }
}

protocol ControllerUINavigationDelegate: AnyObject {
    func getNavigationElements() -> [ControllerNavigationElement]
    func navigateByController(forward: Bool)
    func navigateByController(downward: Bool)
    func uiWidgetActionForControllerNavigator(forward: Bool, from navigation: ControllerNavigationElement)
    func uiButtonActionForControllerNavigator(pressed: Bool, from navigation: ControllerNavigationElement)
    func persistControllerNavigationHighlight()
    func restoreControllerNavigationHighlight()
    func restoreControllerNavigationHighlightAfterSettingsModeSwitch()
}

extension ControllerUINavigationDelegate {
    func getNavigationElements() -> [ControllerNavigationElement] { [] }
    func navigateByController(forward: Bool) {}
    func navigateByController(downward: Bool) {}
    func uiWidgetActionForControllerNavigator(forward: Bool, from navigation: ControllerNavigationElement) {}
    func uiButtonActionForControllerNavigator(pressed: Bool, from navigation: ControllerNavigationElement) {}
    func persistControllerNavigationHighlight() {}
    func restoreControllerNavigationHighlight() {}
    func restoreControllerNavigationHighlightAfterSettingsModeSwitch() {}
}

protocol ControllerNavigationHighlightTargetProviding: AnyObject {
    var controllerNavigationHighlightTargetView: UIView { get }
    func controllerNavigationHighlightDidApply()
    func controllerNavigationHighlightDidClear()
}

extension ControllerNavigationHighlightTargetProviding {
    func controllerNavigationHighlightDidApply() {}
    func controllerNavigationHighlightDidClear() {}
}

protocol ControllerCollectionNavigationDelegate: ControllerUINavigationDelegate where Self: UIViewController {
    var controllerNavigationCollectionView: UICollectionView { get }
    var controllerNavigationSelectedIndexPath: IndexPath? { get set }
    func controllerNavigationCurrentIndexPathForControllerNavigator() -> IndexPath?
    func controllerNavigationHighlightItemForControllerNavigator(at indexPath: IndexPath)
    func invalidateCollectionControllerNavigationHighlightForControllerNavigator()
    func clearCollectionControllerNavigationHighlightForControllerNavigator()
}

extension ControllerCollectionNavigationDelegate {
    var controllerNavigationSelectedIndexPath: IndexPath? {
        get { nil }
        set {}
    }

    func controllerNavigationCurrentIndexPathForControllerNavigator() -> IndexPath? {
        nil
    }

    func controllerNavigationHighlightItemForControllerNavigator(at indexPath: IndexPath) {
    }

    func invalidateCollectionControllerNavigationHighlightForControllerNavigator() {
    }

    func clearCollectionControllerNavigationHighlightForControllerNavigator() {
    }
}

// AlertControllerUtil still hands alerts to the navigator.
extension UIAlertController: ControllerUINavigationDelegate {
}

// VLTouch: no-op — controller navigation is dropped (D4); the API stays so the
// profile/widget pickers compile. Delegates are tracked but never driven.
final class ControllerNavigator: NSObject {

    static var radialMenuButtonPosition: ControllerElementPosition {
        .undefined
    }

    static func setUINavigationDelegate(_ delegate: ControllerUINavigationDelegate?) {
        uiNavigationDelegate = delegate
    }

    static func restorePreviousUINavigationDelegate(ifCurrentDelegateIs delegate: ControllerUINavigationDelegate) {
        guard uiNavigationDelegate === delegate else { return }
        uiNavigationDelegate = nil
    }

    private static weak var uiNavigationDelegate: ControllerUINavigationDelegate?
}
