// VLTouch: Compat stub; S5 makes real what the runtime needs.
import UIKit

@objcMembers
final class ThemeManager: NSObject {

    static let ThemeDidChangeNotification = "ThemeDidChangeNotification"

    /// Follows the trait collection in effect, falling back to the key window
    /// when queried outside a trait environment.
    class func userInterfaceStyle() -> UIUserInterfaceStyle {
        if #available(iOS 13.0, *) {
            let style = UITraitCollection.current.userInterfaceStyle
            if style != .unspecified {
                return style
            }
            let keyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            return keyWindow?.traitCollection.userInterfaceStyle ?? style
        }
        return .light
    }

    /// VoidLink's accent (#0A84FF), resolved against the current system trait.
    static var appPrimaryColor: UIColor {
        if #available(iOS 13.0, *) {
            return UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.20, green: 0.50, blue: 1.0, alpha: 1.0)
                    : UIColor(red: 0.00, green: 0.48, blue: 1.0, alpha: 1.0)
            }
        }
        return UIColor(red: 0.00, green: 0.48, blue: 1.0, alpha: 1.0)
    }
}
