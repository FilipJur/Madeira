// VLTouch: no-op — push-to-talk mic control dropped; the widget subset calls
// requestPermission (always denied) and setMicMuted (ignored). S5 owns the final wording.
import Foundation

@objcMembers
final class MicHandler: NSObject {

    static var sharedInstance: MicHandler? = MicHandler()

    // VLTouch: no-op — mic permission is never granted in this port.
    static func requestPermission(_ completion: ((Bool) -> Void)? = nil) {
        completion?(false)
    }

    // VLTouch: no-op — mic mute has no audio route in this port.
    func setMicMuted(_ muteMic: Bool) {
    }
}
