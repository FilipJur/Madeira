// VLTouch: minimal stand-in for VoidLink's stream controller; the host (S2)
// owns the real flags. Touch stays enabled (false/false = feature off).
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
