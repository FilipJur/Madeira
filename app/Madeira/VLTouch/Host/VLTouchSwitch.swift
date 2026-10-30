// VLTouch: feature switch for the VoidLink widget system. `touch-system = voidlink`
// turns it on for a library session; anything else (or nothing) keeps upstream's
// touch controls.
import Foundation
import UIKit

@MainActor enum VLTouchSwitch {
    /// The switch as the running library session resolved it. Re-evaluated at each
    /// session start (`beginSession`) and when the session menu flips it; false outside a
    /// session, so the upstream paths in ContentView.swift never see it set.
    private(set) static var active = false

    /// Profile that was selected before the session engaged VLTouch (nil: not engaged).
    private static var savedProfile: String??
    private static var resignObserver: NSObjectProtocol?

    /// `touch-system` for `entry`: the game's own file (GameConfigs/<hash>.cfg) first, then
    /// the entry's legacy `config` lines, then madeira.cfg, then MADEIRA_TOUCH_SYSTEM.
    /// Read live, never cached: a session start must see the Game details choice.
    static func value(for entry: LibraryEntry) -> String? {
        let own = GameProfile(windowsPath: entry.windowsPath).values["touch-system"]
        let legacy = entry.config.flatMap { GameProfile.parse($0)["touch-system"] }
        return [own, legacy].lazy.compactMap { $0 }.first { !$0.isEmpty }
            ?? MadeiraConfig.get("touch-system")
            ?? ProcessInfo.processInfo.environment["MADEIRA_TOUCH_SYSTEM"]
    }

    /// Library session start (LibraryModel.begin): resolve the switch for this game and, when
    /// on, select the game's widget profile.
    static func beginSession(_ entry: LibraryEntry) {
        installResignObserver()
        if value(for: entry) == "voidlink" { engage(entry) } else { disengage() }
    }

    /// Library session end (LibraryModel.finish): persist the widgets' own changes into the
    /// session's profile, release everything held, give back the profile that was selected.
    static func endSession() { disengage() }

    /// The session menu changed the game's choice: take it live. A choice that did not
    /// change leaves the session's selected profile alone.
    static func refresh(_ entry: LibraryEntry) {
        let on = value(for: entry) == "voidlink"
        guard on != active else { return }
        if on { engage(LibraryModel.shared.entries.first { $0.id == entry.id } ?? entry) } else { disengage() }
    }

    private static func engage(_ entry: LibraryEntry) {
        if savedProfile == nil { savedProfile = .some(VLProfiles.selectedName) }
        if let name = entry.vlTouchProfile { VLProfiles.select(name: name) }
        active = true
    }

    private static func disengage() {
        guard active else { return }
        VLTouchLayer.flush()
        active = false
        VLSink.releaseAll()
        if case let .some(name) = savedProfile, let name { VLProfiles.select(name: name) }
        savedProfile = nil
    }

    /// Menus and the app leaving the foreground end every touch the widgets hold.
    private static func installResignObserver() {
        guard resignObserver == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { if active { VLSink.releaseAll() } }
        }
    }

    /// `text` (madeira.cfg syntax) with its `touch-system` line replaced by `value`, or
    /// removed for nil. Other lines are kept as they are.
    nonisolated static func updatedText(_ text: String, value: String?) -> String {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" })
            .map(String.init)
        if lines.last == "" { lines.removeLast() }
        lines.removeAll { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { return false }
            return t[..<eq].trimmingCharacters(in: .whitespaces) == "touch-system"
        }
        if let value { lines.append("touch-system = \(value)") }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    /// Game details / session menu: store the game's own choice in its cfg file; nil removes it.
    static func setGameValue(_ value: String?, windowsPath: String) {
        let file = GameProfile(windowsPath: windowsPath)
        file.text = updatedText(file.text, value: value)
    }
}
