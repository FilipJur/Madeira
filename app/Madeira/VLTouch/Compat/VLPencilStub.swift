// VLTouch: no-op — pencil pack gated behind the dropped storefront; tilt and
// pro flags stay off so widget code takes the non-pencil path. S5 owns the final wording.
import UIKit

@objcMembers
final class PencilHandler: NSObject {

    static var shared: PencilHandler? = PencilHandler()

    var disableTilt: Bool = false
    var pencilProEnabled: Bool = false
}

// VLTouch: no-op — the storefront is dropped; purchase does nothing.
@objc enum AddOnProduct: UInt8 {
    case PencilProPack
}

@objcMembers
final class IAPManager: NSObject {
    @objc static let shared = IAPManager()
    // VLTouch: no-op — the storefront is dropped; purchase does nothing.
    @objc func purchase(_ product: AddOnProduct) {}
}
