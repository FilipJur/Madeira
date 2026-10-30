import UIKit

/// Entry point the host (S2) uses for VoidLink's WIDGETTOOL and the settings row.
@MainActor enum VLEditorPresenter {
    /// Presents the layout editor full screen over `presenter`. `onClose` runs once after it is
    /// dismissed (close button, save-and-close, or any host-driven dismissal); the selected
    /// profile or its widgets may have changed. If the editor is already open, `onClose` is chained
    /// onto the open one. If it cannot be presented, `onClose` runs synchronously before this returns.
    ///
    /// Mirrors VoidLink's `StreamFrameViewController prepareGameProfileSelector` (.m:322-336) and
    /// `openWidgetLayoutTool` (.m:1162-1175): the scene comes from the phone or pad storyboard by the
    /// same identifier, gets a clear background, the toolbar is shown and quick-switch is off.
    /// `StreamView` bookkeeping (`saveStreamingGameProfileChanges`, `disableOnScreenControls`,
    /// `clearOnScreenWidgets`) is the host's to do around this call.
    static func present(from presenter: UIViewController, onClose: @escaping () -> Void) {
        // Present from the top of the chain: UIKit ignores present() on a VC that already presents.
        var top = presenter
        while let next = top.presentedViewController, !next.isBeingDismissed {
            if let existing = next as? LayoutOnScreenControlsViewController {
                let previous = existing.onDismissed
                existing.onDismissed = { previous?(); onClose() }
                return
            }
            top = next
        }

        guard let window = top.viewIfLoaded?.window else {
            NSLog("VLTouch: editor presenter is not in a window")
            onClose()
            return
        }

        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        var bounds = window.bounds
        if isPhone && bounds.width < bounds.height {
            bounds.size = CGSize(width: bounds.height, height: bounds.width) // the phone editor is landscape only
        }

        // Profiles (and the first-run template import) must exist before the scene's viewDidLoad
        // asks OSCProfilesManager for them.
        VLProfiles.prepare(bounds: bounds)

        let storyboard = UIStoryboard(name: isPhone ? "VLEditor" : "VLEditorPad", bundle: nil)
        guard let editor = storyboard.instantiateViewController(withIdentifier: "LayoutOnScreenControlsViewController") as? LayoutOnScreenControlsViewController else {
            NSLog("VLTouch: editor scene missing from storyboard")
            onClose()
            return
        }

        editor.modalPresentationStyle = .overFullScreen
        editor.quickSwitchEnabled = false
        editor.profileSelectorLoadingMode = .selectProfileFromLayoutTool
        editor.onDismissed = onClose

        editor.loadViewIfNeeded() // viewDidLoad sees the storyboard's design size; overwrite it right after
        OSCProfilesManager.setLayoutViewBounds(bounds)
        editor.view.backgroundColor = .clear
        editor.toolbarStackView.isHidden = false
        editor.toolbarRootView.isHidden = false

        top.present(editor, animated: true)
    }
}
