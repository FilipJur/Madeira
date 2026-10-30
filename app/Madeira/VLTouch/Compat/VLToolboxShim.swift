// VLTouch: no-op — the toolbox UI is not ported; the handle exists only so
// CommandManager compiles (it stores an optional reference and reloads it).
import UIKit

// VLTouch: matches VoidLink's @objc public class + reloadTableView (CommandManager.swift:488,658).
@objcMembers
public final class ToolboxViewController: UIViewController {
    // VLTouch: no-op — the toolbox UI is not ported; reload does nothing.
    @objc public func reloadTableView() {}
}
