// VLTouch: Compat stub; S5 makes real what the runtime needs.
import UIKit

@objcMembers
final class PencilHandler: NSObject {

    static var shared: PencilHandler? = PencilHandler()

    var disableTilt: Bool = false
    var pencilProEnabled: Bool = false
}
