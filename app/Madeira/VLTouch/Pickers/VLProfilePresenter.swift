import UIKit

/// Entry point the host (S2) uses for VoidLink's PROFILES / PICKPROFILE buttons.
///
/// VoidLink opens `ProfileSelectorViewController` as a modal over the stream
/// (`StreamFrameViewController.openWidgetProfileTable(pickProfile:)` ->
/// `.selectProfileFromStreamView` / `.pickProfile`); the host there reloads its
/// widgets when the selector reports a refresh. Madeira's host reads
/// `VLProfiles.selectedName` from `onClose` instead.
@MainActor enum VLProfilePresenter {
    private static weak var active: ProfileSelectorViewController?

    /// Presents the profile list over `presenter`; `pickOnly` is VoidLink's PICKPROFILE mode.
    /// `onClose` runs once after dismissal; read `VLProfiles.selectedName` then.
    /// If a profile list is already on screen, or `presenter` is not in a window, nothing is
    /// presented and `onClose` runs immediately.
    static func present(from presenter: UIViewController, pickOnly: Bool, onClose: @escaping () -> Void) {
        guard active == nil, presenter.viewIfLoaded?.window != nil else {
            onClose()
            return
        }

        var host = presenter
        while let next = host.presentedViewController, !next.isBeingDismissed {
            host = next
        }

        // The selector fills the list from OSCProfilesManager; make sure the bundled
        // templates were imported (no-op once the host has prepared the profiles).
        if VLProfiles.names().isEmpty {
            VLProfiles.prepare(bounds: presenter.view.bounds)
        }

        let controller = ProfileSelectorViewController()
        // .zero keeps the layout bounds the host already registered with OSCProfilesManager.
        controller.layoutViewBounds = .zero
        controller.loadingMode = pickOnly ? .pickProfile : .selectProfileFromStreamView
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        controller.onDismissed = {
            active = nil
            onClose()
        }
        active = controller
        host.present(controller, animated: false)
    }
}
