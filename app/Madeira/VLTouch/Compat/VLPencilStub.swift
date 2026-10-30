// VLTouch: Compat stub; S5 makes real what the runtime needs.
import UIKit

@objcMembers
final class PencilHandler: NSObject {

    static var shared: PencilHandler? = PencilHandler()

    var disableTilt: Bool = false
    var pencilProEnabled: Bool = false
}
// VLTouch: purchase-gated pencil pack; storefront dropped, purchase is a no-op (tips/purchase -> no-op).
@objc enum AddOnProduct: UInt8 {
    case PencilProPack
}

@objcMembers
final class IAPManager: NSObject {
    @objc static let shared = IAPManager()
    @objc func purchase(_ product: AddOnProduct) {}
}
