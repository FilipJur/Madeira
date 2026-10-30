// VLTouch: Compat stub; S5 makes real what the runtime needs.
import UIKit

// VLTouch: matches VoidLink's @objc public class + reloadTableView (CommandManager.swift:488,658).
@objcMembers
public final class ToolboxViewController: UIViewController {
    @objc public func reloadTableView() {}
}
