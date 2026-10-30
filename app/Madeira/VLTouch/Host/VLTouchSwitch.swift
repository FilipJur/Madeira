// VLTouch: feature switch for the VoidLink widget system. Nothing reads it
// yet (S2 hooks the overlay); default keeps upstream touch controls.
@MainActor enum VLTouchSwitch {
    /// `touch-system` in madeira.cfg (`voidlink` = on, anything else = off),
    /// same 3-source order as TouchMouseGate (ContentView.swift).
    static let active: Bool = {
        let v = MadeiraConfig.gameValue("touch-system")
            ?? MadeiraConfig.get("touch-system")
            ?? ProcessInfo.processInfo.environment["MADEIRA_TOUCH_SYSTEM"]
        return v == "voidlink"
    }()
}
