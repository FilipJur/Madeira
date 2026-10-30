// VLTouch: Compat stub; S5 makes real what the runtime needs.
//
//  ControllerUtil.swift
//  VoidLink (compat subset)
//
//  Type name and member names must match VoidLink's ControllerUtil, because the
//  ported widget/runtime/picker code calls them verbatim. No controller state is
//  tracked in this port, so the stick compensation functions are identities.
//

import Foundation
import UIKit
import GameController

@objc class ControllerUtil: NSObject {

    @objc static var activeStreamingGCControllers: NSMutableSet = NSMutableSet()

    @objc static var gamepadArrivalReported: Bool = false

    @objc static weak var primaryGCController: GCController?

    /// Identity compensation: the stub never rescales stick vectors.
    @objc static func compensated(offsetVector: CGVector, minOffset: CGFloat, circulate: Bool = false) -> CGVector {
        return offsetVector
    }

    /// Identity clamp: the stub never rescales stick vectors.
    @objc static func circulated(offsetVector: CGVector) -> CGVector {
        return offsetVector
    }
}
