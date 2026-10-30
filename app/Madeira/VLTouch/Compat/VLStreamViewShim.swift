// VLTouch: Compat stub; S5 makes real what the runtime needs.
import UIKit

// Widget code reads the stream controller's touch flags off
// StreamFrameViewController.sharedInstance(); StreamView is the same handle
// under the name VoidLink's view type used.
@objcMembers
final class StreamFrameViewController: NSObject {

    private static let shared = StreamFrameViewController()

    class func sharedInstance() -> StreamFrameViewController? {
        shared
    }

    var touchDisabled: Bool = false
    var singleTouchDisabled: Bool = false
}

typealias StreamView = StreamFrameViewController
