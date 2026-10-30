// VLTouch: Compat subset of VoidLink's ControllerUtil.swift — the members the
// ported widget/editor/picker code calls. Stick math is verbatim from VoidLink;
// the pad mirror only reads GameController state (no handlers, no gestures).
//
// Type name and member names must match VoidLink's ControllerUtil, because the
// ported widget/runtime/picker code calls them verbatim.

import Foundation
import UIKit
import GameController

@objc class ControllerUtil: NSObject {

    // MARK: - input processing

    /// VoidLink's raw stick range (ControllerUtil.swift:1128).
    static private let stickMaxOffset: CGFloat = 0x7FFE

    /// Verbatim from VoidLink's ControllerUtil.swift:1688-1703.
    @objc static func compensated(offsetVector: CGVector, minOffset: CGFloat, circulate: Bool = false) -> CGVector {
        let vectorHypot = hypot(offsetVector.dx, offsetVector.dy)
        guard vectorHypot > 0 else { return CGVector(dx: 0, dy: 0) }
        let targetHypot = minOffset + (stickMaxOffset - minOffset) * (vectorHypot / stickMaxOffset)
        var compensatedX = targetHypot * (offsetVector.dx / vectorHypot)
        var compensatedY = targetHypot * (offsetVector.dy / vectorHypot)

        if circulate {
            return circulated(offsetVector: CGVector(dx: compensatedX, dy: compensatedY))
        } else {
            compensatedX = max(min(compensatedX, stickMaxOffset), -stickMaxOffset)
            compensatedY = max(min(compensatedY, stickMaxOffset), -stickMaxOffset)
            return CGVector(dx: compensatedX, dy: compensatedY)
        }
    }

    /// Verbatim from VoidLink's ControllerUtil.swift:1705-1712.
    @objc static func circulated(offsetVector: CGVector) -> CGVector {
        let vectorHypot = hypot(offsetVector.dx, offsetVector.dy)
        guard vectorHypot > 0 else { return CGVector(dx: 0, dy: 0) }
        let targetHypot = min(vectorHypot, stickMaxOffset)
        let circulatedX = targetHypot * (offsetVector.dx / vectorHypot)
        let circulatedY = targetHypot * (offsetVector.dy / vectorHypot)
        return CGVector(dx: circulatedX, dy: circulatedY)
    }

    // MARK: - virtual-pad use flag

    /// Set the first time the virtual pad sends stick/button/gyro input; read by
    /// teardown/cleanup paths. Despite the name it is NOT set by physical-pad
    /// arrival — with Madeira the virtual pad is always connected while VLTouch
    /// is active, so the widget code setting it on input is the real signal.
    @objc static var gamepadArrivalReported: Bool = false

    // MARK: - physical pads (GameController framework, read-only mirror)

    /// Every connected extended-gamepad controller. Read-only: VLTouch never
    /// assigns valueChangedHandler (Madeira's GamepadInput owns it) and never
    /// changes system gestures, so physical pads keep feeding Madeira.
    /// VoidLink's membership rule (players 1-4) does not apply: Madeira never
    /// assigns playerIndex, so every extended pad counts.
    @objc static var activeStreamingGCControllers: NSMutableSet = NSMutableSet()

    /// First connected extended-gamepad controller, or nil.
    @objc static weak var primaryGCController: GCController?

    private static var connectObserver: NSObjectProtocol?
    private static var disconnectObserver: NSObjectProtocol?

    /// Starts (idempotently) the connect/disconnect observation and refreshes the
    /// read-only mirror. Replaces VoidLink's installControllerObserversIfNeeded
    /// minus its stream-controller/settings/navigation side effects (not ported).
    static func installControllerObserversIfNeeded() {
        guard connectObserver == nil, disconnectObserver == nil else { return }

        refreshActiveStreamingControllers()

        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { _ in
            refreshActiveStreamingControllers()
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { _ in
            refreshActiveStreamingControllers()
        }
    }

    /// Rebuilds the mirror from all connected extended-gamepad controllers.
    private static func refreshActiveStreamingControllers() {
        let active = NSMutableSet()
        for controller in GCController.controllers() {
            guard controller.extendedGamepad != nil else { continue }
            active.add(controller)
        }
        activeStreamingGCControllers = active
        primaryGCController = GCController.controllers().first { $0.extendedGamepad != nil }
    }
}

