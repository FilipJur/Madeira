// VLTouch: Compat stub; S5 makes real what the runtime needs.
import Foundation

@objcMembers
final class MicHandler: NSObject {

    static var sharedInstance: MicHandler? = MicHandler()

    static func requestPermission(_ completion: ((Bool) -> Void)? = nil) {
        completion?(false)
    }

    func setMicMuted(_ muteMic: Bool) {
    }
}
