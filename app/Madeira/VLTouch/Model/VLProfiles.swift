import UIKit

/// Profile access for the host (S2) and pickers (S4), over
/// `OSCProfilesManager` (docs/fork/TOUCH-PORT.md).
@MainActor enum VLProfiles {
    /// Loads the profiles for a widget container of `bounds`; imports the bundled
    /// templates on first run, exactly as VoidLink's `getSelectedProfile` does
    /// (phone vs iPad template file, `widgetProfileUpdated-20261016` sentinel;
    /// UserDefaults keys unchanged so VoidLink exports stay compatible).
    /// Also mirrors VoidLink clearing `gamepadArrivalReported` when a new stream
    /// view loads, and starts the physical-pad mirroring the widget code reads.
    static func prepare(bounds: CGRect) {
        let manager = OSCProfilesManager.sharedManager(bounds)
        _ = manager.getSelectedProfile()
        ControllerUtil.gamepadArrivalReported = false
        ControllerUtil.installControllerObserversIfNeeded()
    }

    /// Profile names in display order.
    static func names() -> [String] {
        let profiles = OSCProfilesManager.sharedManager(.zero).getAllProfiles()
        var result: [String] = []
        for case let profile as OSCProfile in profiles {
            result.append(profile.name)
        }
        return result
    }

    /// Name of the selected profile, or nil when the store is empty. Read-only:
    /// the first-run import lives in `prepare` only — unlike VoidLink's
    /// `getSelectedProfile`, this never imports and never force-indexes.
    static var selectedName: String? {
        let profiles = OSCProfilesManager.sharedManager(.zero).getAllProfiles()
        for case let profile as OSCProfile in profiles where profile.isSelected {
            return profile.name
        }
        return (profiles.firstObject as? OSCProfile)?.name
    }

    /// Selects the profile called `name` and persists the selection; false when
    /// there is none.
    @discardableResult static func select(name: String) -> Bool {
        let manager = OSCProfilesManager.sharedManager(.zero)
        guard let index = manager.getIndex(byName: name) else { return false }
        manager.setProfileToSelected(index)
        return true
    }
}
