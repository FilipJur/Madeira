import UIKit

/// Entry point the host (S2) uses for VoidLink's WIDGETTOOL and the settings row.
/// S3 owns the body.
@MainActor enum VLEditorPresenter {
    /// Presents the layout editor full screen over `presenter`. `onClose` runs after it is
    /// dismissed; the selected profile or its widgets may have changed.
    static func present(from presenter: UIViewController, onClose: @escaping () -> Void) {}
}
