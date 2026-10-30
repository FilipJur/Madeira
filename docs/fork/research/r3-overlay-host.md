<!-- Scout report R3OverlayHost captured 2026-10-30 by the lead. Sources: Madeira fork/main 67bd667, VoidLink fa42805, BCD 05e9f6f. [INFERENCE] marks unverified claims. -->

# VLTouch hosting in Madeira's game session — findings

## Summary

- Madeira's on-screen controls are **not** a child of the SwiftUI game view. They live in a **process-lifetime `UIWindow` at `.normal + 101`** (`ControlsWindow`), created once by `TouchControlsHost.attach()`; the game surface (`MetalHostView.shared`) is a subview of the app window *above* SwiftUI but *below* that window (`ContentView.swift:26-77, 299-302, 4146-4174`).
- The window is **never hidden, re-keyed, or torn down**. "Visible or not" is decided per-touch by `ControlsWindow.hitTest` (`4111-4143`) and per-pixel by the SwiftUI body's `if` (`4193-4194`). A VLTouch host inherits exactly that policy for free.
- The window's root is **one** `UIHostingController` hosting `TouchControlsOverlay`, which also carries Madeira's in-session HUD (`LibraryHUD`), the top bar, gesture zones, the edit panel and the pinch gesture. Therefore the smallest hook is **not** a root swap (that would delete the HUD/menu) but a **branch inside `TouchControlsOverlay.controls(_:session:)` (`4232-4246`)** that renders the VoidLink widget container instead of `TouchControlButton`s.
- Because VoidLink widgets are real `UIButton` subviews (`OnScreenWidgetView: UIButton`), hosting them via a `UIViewRepresentable` keeps UIKit hit-testing meaningful — unlike SwiftUI buttons, which forced Madeira's geometric `hitsInteractive` workaround (`ContentView.swift:4068-4083`). That means the VL container can answer `point(inside:)` itself and `ControlsWindow.hitTest` needs only a 2-line early branch.
- Per-game binding already exists and is the right precedent: `LibraryEntry.controlLayout: String?` (`Library.swift:203`) + `controls: [TouchControl]?` (199) + `zones` (205), loaded in `begin()` (`1343-1362`) and written back in `saveCurrentProfile()` (`1505-1517`). `vlTouchProfile: String?` goes beside them.

## Architecture

```
ContentView.body (1306-1325)
 ├ library.enabled && current != nil → sessionBody (1435-1449)  ─ onAppear → TouchControlsHost.attach()
 ├ library.enabled                   → LibraryView
 └ else                              → developerBody (1406-1429) ─ onAppear/onChange → attach()

UIWindowScene
  window .normal          → SwiftUI (MetalBackedView placeholder + HUD-less)
     └ MetalHostView.shared (CAMetalLayer, isUserInteractionEnabled=false)   [26-77, 299-302]
  window .normal + 100    → PassthroughWindow (joystick pad, hitTest nil)     [881-905]
  window .normal + 101    → ControlsWindow → UIHostingController(TouchControlsOverlay)  [4111-4174]
  window .normal + 102    → LibraryKeyboard window                            [5425-5431]
  window .normal + 150    → LaunchCurtain                                     [5668-5671]
```

VoidLink for comparison: widgets are plain subviews of the stream view's top layer (`StreamView.m:1058`, `_onScreenControls` created at `StreamView.m:214`), positions denormalised against **that view's bounds** (`StreamView.m:882-886`, `OSCProfilesManager.swift:438-442`), size from `superview.bounds` (`OnScreenWidgetView.swift:950-959`). `LayoutOnScreenControls` is the container *and* the editor's canvas; the editor instantiates its own copy (`LayoutOnScreenControlsViewController.m:264`). Madeira's analogue of `_streamFrameTopLayerView` is the `UIHostingController`'s root view — full scene bounds, safe-area ignoring.

## 1. Session lifecycle

| Event | Where | Behaviour |
|---|---|---|
| Session start (library) | `ContentView.swift:2558` `launchLibraryEntry` → `Library.swift:1325` `begin()` | sets `current`, `activeEntry`; restores per-game controls at `1343-1362`; shows surface `1367` |
| View switch to session | `ContentView.swift:1316-1318` | `sessionBody` replaces library/developer UI |
| Overlay window created | `ContentView.swift:4149-4174` (`attach()`) | first call creates `ControlsWindow(windowScene:)`, level `.normal + 101` (4161), `isHidden = false` (4163), **never `makeKey`**, root `UIHostingController(rootView: TouchControlsOverlay())` (4164-4166), `PointerLock.register(host)` (4167) |
| Re-attach / re-frame | `ContentView.swift:1427, 1439, 1476, 1537`; `Library.swift:1298` (`prepare()`); frame set at `4170` from `scene.coordinateSpace.bounds` | idempotent: window exists → only `frame` updated |
| Overlay shown/hidden | **no code**; `ControlsWindow.hitTest` `4111-4143` (returns `nil` for empty space; `4141` gates portrait) and body condition `4193-4194` | window stays on screen forever; portrait returns `nil` for every touch |
| Torn down | **never** — `TouchControlsHost.window` is never set to `nil` and `isHidden` is never set true (`4146-4174`). `TouchControlsOverlay.onDisappear` (`4217`) only resets the pad | process lifetime, matching `MetalHostView`'s singleton rule |
| Session end | `Library.swift:1524-1548` `finish()` (called from `poll()` `1406` and `launchFailed()` `1436`) | saves profile `1505`, restores pre-session working copy `1532-1537`, `current = nil` `1538`, hides surface `1544` |
| Menu suspension (`acceptingInput`) | set in `ContentView.swift:4248-4256` `configureGamepad` from `!m.editing && !library.blocksGameplayTouch`; consumed by `GamepadInput.configureTouch` (`GamepadInput.swift:25-34`) → `TouchGamepadState.configure` (`TouchGamepad.swift:73-82`) | menus suppress *input*, keep the pad *connected* (`suspendedConnection`, `TouchGamepad.swift:65-78`) |
| `reserved` (player 1 pre-armed) | `ContentView.swift:2698` at launch → `GamepadInput.reserveSessionSlot` (`GamepadInput.swift:50-57`) → `TouchGamepad.swift:70` | opt-in `MADEIRA_PAD_EARLY_SLOT`; survives the whole process |
| Menu open/close UI state | `Library.swift:1486-1489` `showMenu()`, `LibraryHUD` `4880-4889` | `blocksGameplayTouch` = `preparing != nil \|\| (current != nil && (menu \|\| launching))` (`796`) |
| Orientation | `UIDevice.beginGeneratingDeviceOrientationNotifications()` `4157`; `attach()` re-frames `4170`; triggers `1427` (`landscape`), `1442`, `1479`, `Library.swift:1298` | SwiftUI additionally re-lays out on `.onChange(of: geo.size)` `4212` |
| Safe area | window gets **full** scene bounds (`4170`); overlay `.ignoresSafeArea()` `4221`; safe-area insets reach layout only via `ControlPresetScreen` in `applyDefaultLayout` `4261-4268` | VL profile positions are normalised to the container bounds; host must feed its bounds into `OSCProfilesManager.sharedManager(_:)` (`OSCProfilesManager.swift:28-31`) and set `sizeReference` from bounds width/height ratio (`StreamView.m:893-896`) |
| Keyboard toggle | `MetalBackedView.toggleKeyboard()` `ContentView.swift:145-149`; in-session menu uses `LibraryKeyboard.show()` `Library.swift:5420-5422` (falls back to `toggleKeyboard` when `MADEIRA_FRONTEND_KEYBOARD=0`) | `MetalBackedView.keyboardTarget` is assigned in `didMoveToWindow` `286` |
| App background/foreground | **no overlay-specific handling.** `GamepadInput.swift:251-259` (`setActive(false)`, re-poll on active); `GestureZones.swift:111-112` and `TouchGamepad.swift:135-136` cancel held touches on `willResignActive`; `ContentView.swift:1371-1373` on `didBecomeActive` | VLTouch must add the same release-on-resign hook for widgets that hold buttons/keys |

## 2. `ControlsWindow` details

| Aspect | Fact |
|---|---|
| Class / level | `final class ControlsWindow: UIWindow` `4111`; `windowLevel = .normal + 101` `4161` (above the joystick pad's `+100` `886`) |
| Key window | never (`isHidden = false`, no `makeKeyAndVisible`, `4163`) — so it cannot steal first responder from the game keyboard |
| Pass-through | `hitTest` `4112-4142`: (a) `m.editing` → `super` (editor owns screen) `4116`; (b) `ControlPresetsModel.enabled` + a hit outside the hosting root (alerts/presented VCs) → return it `4119-4121`; (c) `library.preparing` → `super` `4126`; (d) library between sessions → `nil` `4130`; (e) library session → `super` only for menu/launch/menu-button/performance rects, else `m.hitsInteractive(topBar:false)` `4131-4137`; (f) non-session portrait → `nil` `4140` |
| Empty space | `nil` → touches reach SwiftUI → `MetalBackedView` → Wine mouse (`ContentView.swift:100-118` `TouchMouseGate`, `MetroMouse` path) — mouse-look keeps working between buttons |
| SwiftUI + UIKit | single `UIHostingController` root (`4164`); UIKit presentations (alerts, `.sheet`) are handled by branch (b) `4119-4121`; the level `+102` `LibraryKeyboardWindow` and `+150` `LaunchCurtain` sit above it |
| Current game | no reference passed. Content read from singletons in the view: `TouchControlsModel.shared` `4177`, `LibraryModel.shared` `4178`, `GestureZonesModel.shared` `4179`; per-game entry via `LibraryModel.activeEntry` (`Library.swift:746`) |
| Hit test helper | `TouchControlsModel.hitsInteractive` `4084-4108` — geometric, because "SwiftUI does not back each Button with its own UIView" (`4068-4083`) — the constraint a UIKit-based VLTouch layer avoids |

## 3. Per-game state

| Item | Location / type |
|---|---|
| Entry model | `struct LibraryEntry: Codable, Identifiable` `Library.swift:169-…` |
| `controlLayout` | `Library.swift:202-203` — `var controlLayout: String?` (id of a `ControlPreset` in `madeira-control-presets.json`, `TouchControlPresets.swift:368-…`) |
| `controls` / `zones` | `199` `[TouchControl]?`, `204-205` `[GestureZone]?` |
| `controllerBinds` / `padMouseVertical` | `244` `[String: ControlAction]?`, `247` `Double?` |
| `touchControls`, `controlOpacity`, `controlSize` | `198`, `216`, `217` |
| Where **new** `vlTouchProfile: String?` goes | `Library.swift` immediately after `controlLayout` (~line 204); optional → older files decode (same convention as `244-247`) |
| Load path | `Library.swift:1343-1362` in `begin()` — copy of working state `1344-1345`, then per-entry apply `1349-1362`. Add `vltouch.load(entry.vlTouchProfile)` here |
| Save path | `Library.swift:1505-1517` `saveCurrentProfile()` (called from `finish()` `1529` and every HUD close `4883`) |
| Global switch `touch-system = voidlink` | plain key (not `env.*`): read with `MadeiraConfig.get("touch-system")` or `MadeiraConfig.bool("touch-system", default: false)` (`MadeiraConfig.swift:100-103, 183-187`). Note `GamepadInput.flag/optIn` (`GamepadInput.swift:143-151`) only look at **`env.NAME`** — do not use them for a non-`env` key |
| Per-game override | `Application Support/GameConfigs/<%016llx of lowercased windowsPath>.cfg` — `GameProfile` (`GameProfiles.swift:20-31`), same `key = value` syntax, `values` dictionary (`58`). Read live with `GameProfile(windowsPath:).values["touch-system"]`; or `MadeiraConfig.gameValue("touch-system")` (`MadeiraConfig.swift:106-113`) which reads whatever `MADEIRA_CFG_GAME` names (exported at launch by `LibraryBCD.applyExtras` `LibraryBCD.swift:19-66`) |
| Precedent for a Swift-only per-game switch read at session start | `TouchMouseGate` (`ContentView.swift:60-67`) uses `gameValue ?? get ?? ProcessInfo` — copy that 3-source order |
| Catalog cost | a new key is expected in `ConfigCatalog.generated.swift` (category `Controllers`, see line 88) or `check-config-catalog.py` fails (`ConfigCatalog.swift:1-8`); Settings › All settings lists it automatically (`55-84`) |

## 4. Settings UI

| Where | Line | Fit |
|---|---|---|
| Settings tab `private var settings: some View` (Form, sections gated by `settingsShow(...)`) | `Library.swift:3017-3090` | **best place**: a new `if settingsShow("controller", "touch", "gamepad", "voidlink") { Section("Controllers") { … } }` right after the Pointer section (`3033-3035`) |
| `LibraryPointerSettings` (existing touch/pointer toggles, used both in Settings and the Session menu) | `Library.swift:4520-…` | alternative; but it is shared with the in-game menu, so a *global* switch there would look per-session |
| Per-game toggle | `Library.swift:3628-3641` (`displayPage`: `ControllerModeChoice`, `Controller binds`) and `3884-3888` (`Toggle("Touch controls", …)`) | per-game "Touch system: Madeira / VoidLink" picker belongs next to `Toggle("Touch controls")` |
| In-session menu | `Library.swift:5137-5150` (`Touch controls` toggle `5142`, `ControlLayoutMenu` `5145-5149`) | mirror the per-game choice here so a session can be flipped without leaving the game |
| All-settings editor | `ConfigCatalog.swift:36-84` | the raw `touch-system` key appears there for free once catalogued |

## 5. Functional-button targets in Madeira

VoidLink's dispatch is `OnScreenWidgetView.swift:3320-3353` → `OnScreenFunctionalWidgetDelegate` (`OnScreenWidgetView.swift:51-63`), implemented by `StreamFrameViewController` (`StreamFrameViewController.m:1236-1238, 1858`).

| VL cmd | VL call (file:line) | Madeira target | Notes |
|---|---|---|---|
| `SETTINGS` | `expandSettingsView()` `OnScreenWidgetView.swift:3322-3324` | `LibraryModel.shared.showMenu()` — `Library.swift:1486-1490` | requires `library.enabled && current != nil`; same entry point the HUD menu button uses (`4750-4754`); `LibraryController` gets `ownsInput` |
| `QUITAPP` | `disconnectAndQuitApp()` `3329-3332` | `LibraryModel.shared.requestQuit()` — `Library.swift:1491-1504` | posts Alt+F4 (`winios_post_key(0x12/0x73)`), sets `quitRequested`, waits for native exit; `finish()` follows from `poll()` `1406`. Madeira's own Quit button: `Library.swift:5225-5227` |
| `DISCONNECT` | `disconnectRemoteSession()` `3325-3328` | no exact equivalent (a session is the process). Nearest: `requestQuit()`; or `library.finish()` is `private` `1524` | [INFERENCE] map to `requestQuit()` or hide |
| `SOFTKEYBOARD` | `bringUpSoftKeyboard()` `3352-3353` (`StreamFrameViewController.m:1236-1238`) | `MetalBackedView.toggleKeyboard()` — `ContentView.swift:145-149`; or `LibraryKeyboard.show()` — `Library.swift:5420-5422` (respects `MADEIRA_FRONTEND_KEYBOARD`) | in a library session the menu's Keyboard button uses `LibraryKeyboard.show()` (`5164`) |
| `PROFILES` / `WIDGETPROFILES` | `openWidgetProfileTable(pickProfile:false)` `3342-3346` → `ProfileSelectorViewController` | Madeira's analog is the **layout** picker `ControlLayoutMenu` (`TouchControlPresets.swift:~550-666`) with model `ControlPresetsModel` (`370-410`); VoidLink profiles instead need a new VC over `OSCProfilesManager.sharedManager(bounds)` (`OSCProfilesManager.swift:28-31`) | the VL picker must also write `LibraryEntry.vlTouchProfile` |
| `PICKPROFILE` / `PICKPRFL` | `3347-3351` | same picker, "pick" mode | |
| `WIDGETTOOL` | `openWidgetLayoutTool()` `3337-3341` | Madeira's "Edit controls" (`Library.swift:5150`, `TouchControlsOverlay` pencil `4300-4303`) → for VL: present `LayoutOnScreenControlsViewController` (`LayoutOnScreenControlsViewController.m:264-267`) |
| `TOOLBOX`, `PIP`, `ABSGAMEPAD`, `PUSHTOTALK`, `DISABLETOUCH` | `3333-3368` | no Madeira counterpart; `ABSGAMEPAD` → `AbstractGamepadOverlayView` (`AbstractGamepadOverlayWidgetView.swift`); stubs | |

## 6. Proposed hook

**Principle:** keep `TouchControlsHost`/`ControlsWindow`/`TouchControlsOverlay` and swap only the *button layer*. A root-VC swap at `4164` would remove `LibraryHUD`, the top bar, the layout menu, the pinch/gesture-zone layer and `configureGamepad`'s pad bookkeeping — about 300 lines to reimplement; the inner branch needs none of that.

New file (inside the compiled port, e.g. `app/Madeira/VLTouch/Host/VLTouchLayer.swift`):
`struct VLTouchLayer: UIViewRepresentable` → returns a `VLTouchContainer: UIView` (real UIKit subviews = correct hit testing) that
- calls `OSCProfilesManager.sharedManager(bounds)` once bounds are known,
- builds `OnScreenWidgetView`s exactly as `StreamView.m:1000-1070` does (`addSubview` → `setLocation(position:)` → `sizeReference` → `resizeWidgetView()`),
- overrides `point(inside:with:)` → `widgets.contains(where: { $0.frame.contains(p) }) || editing`,
- overrides `hitTest` → deepest widget or `nil`,
- exposes `static var active: Bool` (switch read once per session) and `static func hit(_ p: CGPoint, in window: UIWindow) -> Bool`.

Edits in `ContentView.swift` (~6 lines):

| # | Location | Change | Lines |
|---|---|---|---|
| H1 | `4112` (`ControlsWindow.hitTest`, after `let m = …`) | `if VLTouchLayer.active { return VLTouchLayer.hit(point, in: self) }` — VL layer's own hit test replaces `hitsInteractive`; the `library.menu/launching/menuButtonRect/performanceRect` branch (`4131-4137`) and the presented-VC branch (`4119-4121`) must stay **before** it: put the VL line after `4121`, guarded by `library.current != nil` | +2 |
| H2 | `4232-4246` (`controls(_:session:)`) | `if VLTouchLayer.active { VLTouchLayer(screen: screen, editing: m.editing, opacity: session ? library.opacity : 1) }` as the first branch of the `@ViewBuilder`, existing `button`/`GlassEffectContainer` unchanged in the `else` | +3 (branch + closing brace) |
| H3 | `4254` (`configureGamepad`) | `let accepting = !m.editing && !VLTouchLayer.editing && !library.blocksGameplayTouch` | +1 (or 0 if `VLTouchLayer.editing` is folded into `TouchControlsModel.editing`) |
| H4 (optional) | `4113`/`4194` | reuse `m.visible` as the show/hide switch (VL profile `isSelected` maps onto `TouchControlsModel.shared.visible`), so no new gate | 0 |
| — | `4149-4174` `attach()` | **unchanged**: the hosted view already exists; bounds come from `geo.size` in `controls()` | 0 |
| — | `2698` `reserveSessionSlot(touchControls:)` | **unchanged** if `TouchControlsModel.offersControllerInput` (`4064-4068`) is extended to `|| VLTouchLayer.active` (that is +2 lines in `ContentView.swift` inside `TouchControlsModel`, not a call-site edit) | 0–2 |

Awareness needed outside `ContentView.swift` (in the integration slice, ~12 lines):

| File / line | Change |
|---|---|
| `Library.swift:1349-1362` (`begin`) | load `entry.vlTouchProfile` into `OSCProfilesManager.sharedManager(...)` and set `VLTouchLayer.active` from `pregame` switch |
| `Library.swift:1505-1517` (`saveCurrentProfile`) | `entry.vlTouchProfile = VLProfiles.currentSelectedID` |
| `Library.swift:1529-1537` (`finish`) | restore the pre-session VL profile + `VLTouchLayer.editing = false` |
| `Library.swift:3033-3036` (Settings) / `3884-3888` (Game details) / `5142-5149` (Session menu) | the `touch-system` toggle (global / per game / live) |
| `Library.swift:4119-4121` reuse | the VL **editor** presented modally is a UIKit presentation outside the hosting root — the existing branch already returns it, so no change |
| `GestureZones`/`TouchGamepad` background hooks (`GestureZones.swift:111`, `TouchGamepad.swift:135`) | VL needs the same release-on-resign (inside `VLTouchLayer`, not ContentView) |

**Total: ~6–8 lines in `ContentView.swift` at three sites (`4112`, `4232`, `4254`) plus ~12 in `Library.swift`; everything else is new files under `app/Madeira/VLTouch/`.** `TouchControlButton` (`4430-4676`) and the `TouchControl` path remain compiled and selectable by the switch, so upstream continues to work.

## Files

| Path | Holds |
|---|---|
| `app/Madeira/ContentView.swift:3855-3968` | `ControlAction` (key/mouse/stick/keyboardToggle/pad actions) |
| `app/Madeira/ContentView.swift:3969-3985` | `TouchControl` (normalised layout item) |
| `app/Madeira/ContentView.swift:3992-4108` | `TouchControlsModel` (JSON persist `madeira-controls.json`, `layoutID`, `offersControllerInput`, `hitsInteractive`) |
| `app/Madeira/ContentView.swift:4111-4143` | `ControlsWindow` (level, pass-through policy) |
| `app/Madeira/ContentView.swift:4146-4174` | `TouchControlsHost.attach()` (window creation, frame, PointerLock) |
| `app/Madeira/ContentView.swift:4176-4246` | `TouchControlsOverlay` (body conditions, top bar, `controls()`), `configureGamepad` `4248-4257`, `applyDefaultLayout` `4261-4269` |
| `app/Madeira/ContentView.swift:4430-4676` | `TouchControlButton` + `press(_:)` `4658-4677` (the current sink: `winios_post_key` / `winios_pointer` / `MetalBackedView.toggleKeyboard`) |
| `app/Madeira/ContentView.swift:26-77`, `122-323` | `MetalHostView`, `MetalBackedView` (+ `toggleKeyboard` `145`) |
| `app/Madeira/Library.swift:169-217` | `LibraryEntry` persisted fields |
| `app/Madeira/Library.swift:713-796` | `LibraryModel` state (`enabled`, `current`, `menu`, `blocksGameplayTouch`) |
| `app/Madeira/Library.swift:1293-1370` / `1486-1548` | `prepare`/`begin`; `showMenu`/`requestQuit`/`saveCurrentProfile`/`finish` |
| `app/Madeira/Library.swift:3017-3090` / `3628-3641` / `4520-…` | Settings form, per-game page, pointer settings |
| `app/Madeira/Library.swift:4786-5248` | `LibraryHUD` (menu button, starting screen, Session menu, Quit) |
| `app/Madeira/Library.swift:5419-5431` | `LibraryKeyboard.show()`/window (+102) |
| `app/Madeira/TouchGamepad.swift:60-90` | `TouchGamepadState` (`reserved`, `acceptingInput`, `configure`) |
| `app/Madeira/GamepadInput.swift:15-57, 143-151` | switches, `configureTouch`, `reserveSessionSlot`, `flag`/`optIn` |
| `app/Madeira/MadeiraConfig.swift:60-190` | cfg read API (`get`, `bool`, `flag`, `gameValue`, `all`) |
| `app/Madeira/GameProfiles.swift:20-70` | `GameConfigs/<hash>.cfg` path + parser |
| `app/Madeira/TouchControlPresets.swift:368-410, 550-666` | `ControlPresetsModel`, `ControlLayoutMenu` |
| `docs/CONTROLLERS.md:23-129` | authoritative touch/pad semantics (merge, reservation, menu suspension) |
| `/tmp/voidlink/VoidLink/Input/StreamView.m:214, 882-896, 1058-1069` | how VoidLink hosts widgets (bounds-based denormalisation, size reference) |
| `/tmp/voidlink/VoidLink/Input/OnScreenWidgetView.swift:51-63, 3320-3368` | `OnScreenFunctionalWidgetDelegate` + cmd dispatch |
| `/tmp/voidlink/VoidLink/Input/CustomOSC/OSCProfilesManager.swift:28-31, 438-442` | `sharedManager(bounds)` singleton that needs the container bounds |