import UIKit

/// Entry point the host (S2) uses for VoidLink's PROFILES / PICKPROFILE buttons.
/// S4 owns the body.
@MainActor enum VLProfilePresenter {
    /// Presents the profile list over `presenter`; `pickOnly` is VoidLink's PICKPROFILE mode.
    /// `onClose` runs after dismissal; read `VLProfiles.selectedName` then.
    static func present(from presenter: UIViewController, pickOnly: Bool, onClose: @escaping () -> Void) {}
}
