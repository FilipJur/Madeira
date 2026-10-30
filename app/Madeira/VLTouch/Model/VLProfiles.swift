import UIKit

/// Profile access for the host (S2) and pickers (S4). S5 owns the bodies, over
/// `OSCProfilesManager` (docs/fork/TOUCH-PORT.md).
@MainActor enum VLProfiles {
    /// Loads the profiles for a widget container of `bounds`; imports the bundled
    /// templates on first run.
    static func prepare(bounds: CGRect) {}

    /// Profile names in display order.
    static func names() -> [String] { [] }

    /// Name of the selected profile.
    static var selectedName: String? { nil }

    /// Selects the profile called `name`; false when there is none.
    @discardableResult static func select(name: String) -> Bool { false }
}
