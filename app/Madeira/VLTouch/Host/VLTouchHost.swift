import SwiftUI
import UIKit

/// VoidLink's functional widgets (SETTINGS, QUITAPP, PROFILES ...) call this object where the
/// original called StreamFrameViewController (docs/fork/TOUCH-PORT.md "Host contract").
/// The widgets run it on the main thread; anything else hops there first.
final class VLTouchHost: NSObject, OnScreenWidgetView.OnScreenFunctionalWidgetDelegate {
    /// `OnScreenWidgetView.functionalWidgetDelegate` is weak, so the container's widgets share this one.
    static let shared = VLTouchHost()

    private func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated(body) } else { Task { @MainActor in body() } }
    }

    // MARK: Mapped to Madeira

    /// SETTINGS: the session menu, the same entry point as the HUD's menu button.
    func expandSettingsView() {
        onMain { if LibraryModel.shared.current != nil { LibraryModel.shared.showMenu() } }
    }

    /// DISCONNECT: a session is the process; the nearest thing is asking the game to close.
    func disconnectRemoteSession() { requestQuit() }

    /// QUITAPP.
    func disconnectAndQuitApp() { requestQuit() }

    private func requestQuit() {
        onMain { if LibraryModel.shared.current != nil { LibraryModel.shared.requestQuit() } }
    }

    /// SOFTKEYBOARD.
    func bringUpSoftKeyboard() { onMain { LibraryKeyboard.show() } }

    /// WIDGETTOOL: VoidLink's layout editor.
    func openWidgetLayoutTool() {
        onMain { Self.open { root, done in VLEditorPresenter.present(from: root, onClose: done) } }
    }

    /// PROFILES / PICKPROFILE: the profile list (`pickProfile`: pick-only mode).
    func openWidgetProfileTable(pickProfile: Bool) {
        onMain { Self.open { root, done in VLProfilePresenter.present(from: root, pickOnly: pickProfile, onClose: done) } }
    }

    // MARK: No Madeira counterpart (docs/fork/research/r3-overlay-host.md §5)

    func enterPip() {}
    func bringUpToolboxMenu() {}
    func alterAbsTouchDragWith(mouseButton: Int32) {}
    func enablePencilHover() {}
    func disablePencilHover() {}
    func handleDisableSingleTouchButtonUp() {}
    func replaceBrush(shortcut: String) {}
    func replaceEraser(shortcut: String) {}
    func presentPressureCurveVC() {}
    func handleTouchDisableButtonUp() {}
    func toggleGamepadOverlay(overlayEnabled: Bool) {}
    @objc(magnifierMoveStreamViewWithTranslation:)
    func magnifierMoveStreamView(translation: CGVector) {}
    @objc(magnifierMoveStreamViewWithTranslation:pinchDelta:)
    func magnifierMoveStreamView(translation: CGVector, pinchDelta: CGFloat) {}
    func setMagnifierViewportInteractionEnabled(_ enabled: Bool) {}
    func resetMagnifierStreamView(animated: Bool) {}
    @objc(restoreMagnifierStreamViewWithOffset:scale:)
    func restoreMagnifierStreamView(offset: CGPoint, scale: CGFloat) {}
    func startStreamViewInteractionTimer() {}

    // MARK: Presenting the editor and the pickers

    /// An editor or picker is on screen: the widgets are gone and the pad takes no input.
    @MainActor static var modalOpen: Bool { VLTouchModal.shared.open }

    /// The controls window's root view controller: the overlay's own window, above the game and
    /// below the keyboard and the launch curtain.
    @MainActor static func controlsRoot() -> UIViewController? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .lazy.flatMap(\.windows).first { $0 is ControlsWindow }?.rootViewController
    }

    /// Opens an editor or a picker over the controls window. VoidLink's order
    /// (StreamFrameViewController.openWidgetLayoutTool): save the widgets' changes, drop the
    /// widgets (the editor owns the shared widget state), present, rebuild from the possibly
    /// changed profile when it closes.
    @MainActor static func open(_ present: (_ root: UIViewController, _ onClose: @escaping () -> Void) -> Void) {
        guard !modalOpen, VLTouchSwitch.active, let root = controlsRoot(), root.presentedViewController == nil else { return }
        VLTouchModal.shared.open = true   // TouchControlsOverlay re-runs configureGamepad: no pad input meanwhile
        VLTouchLayer.suspend()
        VLSink.releaseAll()
        present(root) { closed() }
        // A presenter that put nothing on screen would leave the widgets gone for good.
        if root.presentedViewController == nil { closed() }
    }

    @MainActor private static func closed() {
        guard modalOpen else { return }
        VLTouchModal.shared.open = false
        // The picker may have changed the selected profile: it belongs to the game from now on.
        LibraryModel.shared.saveCurrentProfile()
        VLTouchLayer.resume()
    }

    /// The session menu's rows: same flows as the widgets' own buttons.
    @MainActor static func openEditor() { shared.openWidgetLayoutTool() }
    @MainActor static func openProfiles() { shared.openWidgetProfileTable(pickProfile: false) }

    /// Settings › Touch controls: the editor outside a session, from the app's key window.
    @MainActor static func openEditorFromSettings() {
        guard !modalOpen else { return }
        var top = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .lazy.flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        if let top { VLEditorPresenter.present(from: top, onClose: {}) }
    }
}

/// Observable so the overlay re-registers the pad (`configureGamepad`) when an editor or picker opens or closes.
@MainActor final class VLTouchModal: ObservableObject {
    static let shared = VLTouchModal()
    @Published fileprivate(set) var open = false
}

/// The `touch-system` choice. Without an entry it is the global key in madeira.cfg (Settings);
/// with one, the game's own line in its GameConfigs file (Game details, Session menu). `live`:
/// the entry is the running session, so a change takes effect at once.
struct VLTouchSystemPicker: View {
    var entry: LibraryEntry?
    var live = false
    var changed: () -> Void = {}
    @State private var choice: String

    init(entry: LibraryEntry? = nil, live: Bool = false, changed: @escaping () -> Void = {}) {
        self.entry = entry; self.live = live; self.changed = changed
        _choice = State(initialValue: Self.stored(entry))
    }

    /// "voidlink" or "madeira" for the global key; "", "voidlink" or "madeira" for a game ("" = follow Settings).
    private static func stored(_ entry: LibraryEntry?) -> String {
        guard let entry else { return MadeiraConfig.get("touch-system") == "voidlink" ? "voidlink" : "madeira" }
        guard let v = GameProfile(windowsPath: entry.windowsPath).values["touch-system"],
              v == "voidlink" || v == "madeira" else { return "" }
        return v
    }

    var body: some View {
        Picker("Touch controls", selection: $choice) {
            if entry != nil { Text("Default (Settings)").tag("") }
            Text("Madeira").tag("madeira")
            Text("VoidLink widgets").tag("voidlink")
        }
        .onChange(of: choice) { _, new in
            guard new != Self.stored(entry) else { return }
            if let entry {
                VLTouchSwitch.setGameValue(new.isEmpty ? nil : new, windowsPath: entry.windowsPath)
                if live { VLTouchSwitch.refresh(entry) }
            } else {
                MadeiraConfig.set("touch-system", new == "voidlink" ? new : nil)
            }
            changed()
        }
    }
}

/// Settings › Touch controls.
struct VLTouchSettings: View {
    @State private var voidlink = MadeiraConfig.get("touch-system") == "voidlink"
    var body: some View {
        VLTouchSystemPicker { voidlink = MadeiraConfig.get("touch-system") == "voidlink" }
        Text("VoidLink widgets: the on-screen widget system with profiles, macros and a layout editor, in game sessions. Each game can choose its own in Game details.")
            .font(.caption).foregroundStyle(.secondary)
        if voidlink {
            Button("Edit widget layout", systemImage: "slider.horizontal.3") { VLTouchHost.openEditorFromSettings() }
        }
    }
}
