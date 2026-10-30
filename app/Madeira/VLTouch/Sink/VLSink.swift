import Foundation

/// VLTouch sink contract (docs/fork/TOUCH-PORT.md "Sink contract"). S1 owns the bodies.
/// ControllerSupport's `updateFinished:` calls `publish`; the host (S2) passes `control`
/// to `GamepadInput.configureTouch` while VLTouch is active and calls `releaseAll`
/// on resign-active, menu suspension and session end.
@MainActor @objc final class VLSink: NSObject {
    /// Control UUID the host includes in `GamepadInput.configureTouch(controls:)`.
    static let control = UUID()

    /// Merged virtual pad from ControllerSupport: Moonlight button flags (low 16 bits are
    /// XInput bits), triggers 0-255, sticks Int16 with y up.
    @objc static func publish(buttons: Int32, leftTrigger: UInt8, rightTrigger: UInt8,
                              leftX: Int16, leftY: Int16, rightX: Int16, rightY: Int16) {}

    /// Releases the pad hold and every key and mouse button the widgets hold.
    @objc static func releaseAll() {}
}
