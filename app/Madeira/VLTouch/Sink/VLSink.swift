import Foundation

/// VLTouch sink contract (docs/fork/TOUCH-PORT.md "Sink contract"). S1 owns the bodies.
/// ControllerSupport's `updateFinished:` calls `publish`; the host (S2) passes `control`
/// to `GamepadInput.configureTouch` while VLTouch is active and calls `releaseAll`
/// on resign-active, menu suspension and session end.
@MainActor @objc final class VLSink: NSObject {
    /// Control UUID the host includes in `GamepadInput.configureTouch(controls:)`.
    static let control = UUID()

    /// Fixed owner UUID for the whole virtual pad. One owner + one control UUID
    /// carries VoidLink's entire pad (buttons, analog triggers, sticks), merged
    /// by TouchGamepadState with any other owners. Fixed so every publish from
    /// ControllerSupport updates the same hold rather than leaking one per call.
    static let owner = UUID(uuidString: "6B1E3C9A-0F2A-4E6B-9D1C-7A8F2B4C6D0E")!

    /// Bits above the low 16 have no XInput lane (paddles/MISC/touchpad). Drop
    /// them and log once per session so widget profiles using them fail visibly.
    private static var droppedHighBitsLogged = false

    /// Merged virtual pad from ControllerSupport: Moonlight button flags (low 16 bits are
    /// XInput bits), triggers 0-255, sticks Int16 with y up.
    ///
    /// Builds one `GamepadSample` from the accumulated pad and publishes it via
    /// `GamepadInput.shared.touch(owner:control:value:)`. An all-zero state
    /// sends `nil`, releasing the owner's hold. Callers must already be on the
    /// main thread (ControllerSupport hops there).
    @objc static func publish(buttons: Int32, leftTrigger: UInt8, rightTrigger: UInt8,
                              leftX: Int16, leftY: Int16, rightX: Int16, rightY: Int16) {
        let high = UInt32(bitPattern: buttons) & 0xFFFF_0000
        if high != 0, !droppedHighBitsLogged {
            droppedHighBitsLogged = true
            LogStore.shared.log("[vltouch] dropping non-XInput button bits \(String(high, radix: 16)) (paddles/MISC/touchpad have no lane)")
        }
        let isZero = (UInt32(bitPattern: buttons) & 0xFFFF == 0)
            && leftTrigger == 0 && rightTrigger == 0
            && leftX == 0 && leftY == 0 && rightX == 0 && rightY == 0
        let value: GamepadSample? = isZero ? nil : GamepadSample(
            buttons: UInt16(truncatingIfNeeded: UInt32(bitPattern: buttons) & 0xFFFF),
            lt: leftTrigger, rt: rightTrigger,
            lx: leftX, ly: leftY, rx: rightX, ry: rightY)
        GamepadInput.shared.touch(owner: owner, control: control, value: value)
    }

    /// Releases the pad hold and every key and mouse button the widgets hold.
    /// VLLiShim tracks the down-sets; this clears the pad publish first, then
    /// asks the shim to release its held inputs.
    @objc static func releaseAll() {
        GamepadInput.shared.touch(owner: owner, control: control, value: nil)
        VLLiReleaseAllHeldInputs()
    }
}
