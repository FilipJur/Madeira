<!-- Scout report R4BCDHook captured 2026-10-30 by the lead. Sources: Madeira fork/main 67bd667, VoidLink fa42805, BCD 05e9f6f. [INFERENCE] marks unverified claims. -->

# R4 — How BCD (`thebcd69/bcd-games` @ `05e9f6f`, base `279fd0f83170`) hooks `BCDTouch*` into ContentView and the app

All paths below: BCD = `/tmp/bcd-games/app/Madeira/…`; OURS = `~/Developer/Madeira/app/Madeira/…`.

## Summary

BCD did **not** build a VoidLink-style standalone touch system. It kept Madeira's model, presets, window host and overlay wholesale, and **replaced only the two view factories inside `TouchControlsOverlay`** (`controls`, `topBar`) plus added hooks in `ControlsWindow`/`MetalBackedView`. Nine new `BCDTouch*.swift` files contain: engine-free core/views/editor/layouts/look (preview-compilable), **one** engine adapter (`BCDTouchLive.swift`), **one** game-view input hook (`BCDTouchExtrasLive.swift`), and a tiny auto-hide/look model (`BCDTouchFeelModel.swift`). `TouchControlButton`, `MappingPanel`, `GestureZones*`, `ControlLayoutMenu`, `GlassShape`/`glassFace`/`GlassEffectContainer` were **deleted**; nothing coexists behind a feature switch. Pad input still goes through Madeira's `TouchPadSurface` — no new sink, no `LiSend*` analogue.

| BCD file | lines/anchors seen | role | engine-free? |
|---|---|---|---|
| `BCDTouchCore.swift` | 1-444 (`BCDTouchEvent` 150-159, `BCDTouchRules` 162-214, `BCDTouchPress` 216-273, `BCDTouchNames` 276-413, `BCDTouchPanelPlacement` 417-444) | values/rules/labels | yes (only comments name winios) |
| `BCDTouchControls.swift` | 1-542 (`BCDTouchInput` 25-29, `BCDTouchLayer` 66-98, `BCDTouchControl` 101-180, `BCDTouchKeySurface/View` 402-497) | play-mode views | yes |
| `BCDTouchEditor.swift` | `BCDTouchEditorActions` 43-62, `BCDTouchEditor` 66-220, inspector 243-436, picker 438-470 | editor | yes |
| `BCDTouchLayouts.swift` | `BCDTouchLayouts` 23, list 59, menu section 235, row 295 | layout UI | yes |
| `BCDTouchLook.swift` / `BCDTouchLookViews.swift` | 1-~90 / 1-152 | colour scheme (per-game line `touchlook`) | yes |
| `BCDTouchFeelModel.swift` | 1-110 | auto-hide timer + redraw revision | yes |
| `BCDTouchLive.swift` | 1-375 | **the only engine adapter** | no (`ENGINE_BOUND`) |
| `BCDTouchExtrasLive.swift` | 1-258 | MetalBackedView touch filter: aim/gestures/Pencil | no (`ENGINE_BOUND`) |

BCD's own architecture doc referenced by every header (`docs/BCD-UI-ARCHITECTURE.md`) **is not in the repo** — `docs/` contains only `local-build/` (dir listing).

---

## 1. Every `BCDTouch*` reference outside `BCDTouch*.swift`

### ContentView.swift (2956 lines total)

| `ContentView.swift:line` | code | purpose |
|---|---|---|
| `:344` | `func mapPoint(_ p: CGPoint) -> (Int32, Int32)` — made internal | Pencil/gesture need the same mapping |
| `:504` / `:505` | `if !BCDTouchExtras.replaces(.tap2) { tmAbsoluteClick(...) }` | a bound gesture suppresses upstream's double-tap |
| `:623` | `BCDTouchFeelModel.shared.gameTouched()` | touch on game un-hides controls |
| `:624, :672, :751, :797` | `guard let touches = BCDTouchExtras.filter(self, touches, .began/.moved/.ended/.cancelled) else { return }` | input filter (one static flag when off) |
| `:765` | `&& !BCDTouchExtras.replaces(.tap2)` in touchesEnded | same as :504 |
| `:2726` | `guard visible, !BCDTouchFeel.controlsHidden else { return false }` | hit-test skips controls when auto-hidden |
| `:2745-2750` | `override func sendEvent(_ event: UIEvent) { … BCDTouchFeelModel.shared.controlsTouched(fingers: …) }` | hold-timer feed |
| `:2822` | `@ObservedObject private var feel = BCDTouchFeelModel.shared` | redraw/auto-hide in overlay |
| `:2865` | `private func controls(_ screen: CGSize, session: Bool) -> some View { BCDTouchControlsLive(screen: screen, session: session) }` | **view swap #1** |
| `:2899` | `private var topBar: some View { BCDTouchChromeLive() }` | **view swap #2** |

### Settings / library / presets / menus / per-game prefs

| file:line | snippet | purpose |
|---|---|---|
| `BCDSettingsLive.swift:317` | `func editor(close:) -> AnyView? { AnyView(BCDTouchEditorHost(close: close)) }` | Settings › Controls editor entry |
| `BCDSettingsLive.swift:420-429` | `struct BCDTouchEditorHost … if proxy.size.width > proxy.size.height { TouchControlsOverlay() }` | reuses the **same** overlay full-screen |
| `BCDSettingsSections.swift:578` | `if let editor = backend.editor(close: { editing = false }) { editor }` | presents the host |
| `Library.swift:1181-1183` | comment + `ControlPresetsModel.shared.sessionBegan()` | session start: no default layout on screen |
| `Library.swift:1408-1417` | `entry.controls = …; entry.controlLayout = controls.layoutID; entry.touchControls = …; entry.controlOpacity/size` | per-game save |
| `TouchControlPresets.swift:20` | `// (BCDTouchLive.swift). A library game remembers its layout (LibraryEntry.controlLayout)` | doc |
| `TouchControlPresets.swift:548, :558` | `LogStore.shared.log("[touch] default layout=\"\(BCDTouchNames.layoutName(…))\"…")` | naming/logs moved into `BCDTouchNames` |
| `BCDSessionLive.swift:196` | `menu.custom["touch"] = { AnyView(BCDTouchMenuSectionLive(closeMenu: …)) }` | menu section host |
| `BCDSessionLive.swift:197` | `menu.custom[BCDInputMenu.lookCustom] = { AnyView(BCDTouchLookSampleLive()) }` | look preview |
| `BCDSessionLive.swift:481-482` | `// BCD's touch section (BCDTouchMenuSectionLive, ui-touch) … BCDMenuRow(id:"touch", kind:.custom("touch"))` | row injection |
| `BCDSessionLive.swift:1179, :1233-1236` | same, second menu source | settings/dock menu |
| `BCDInputLive.swift:48` | `BCDTouchExtras.configure(aim:gestures:pencil:title:)` | per-game feature apply |
| `BCDSessionFeelLive.swift:79-81, :108, :161-166` | `BCDTouchFeel.reset()`, `BCDTouchFeelModel.shared.setSuspended(menu \|\| editing)`, `BCDTouchFeel.haptics/tint`, `configure(seconds:)` | session feel |
| `BCDSessionFeelLive.swift:175` | `gateMode(BCDTouchMouse…)` → `TouchMouseGate.override` | touches-miss rule |
| `BCDInputProfile.swift:20, :49` | `var touchLook: BCDTouchLook` | per-game look line |
| `BCDInputPage.swift:133-137` | `choice("look-body" …)` / `choice("look-icons" …)` | game page group `touchlook` |
| `BCDInputMenu.swift:143-146` | same four chips in-menu | |
| `BCDMenuMore.swift:212` | `kind: .choice(BCDTouchMouse.choices…)` | pointer rule row |
| `BCDSessionFeel.swift:174-184, :214, :237, :255` | `static var controlsHidden`, `var touchMouse: String?` | feel flags |
| `BCDTurboLive.swift:10, :21, :108-167` | `BCDTouchLive.send reads touchNeeded`; `passes(_ event: BCDTouchEvent)` | turbo on touch keys |
| `BCDRadialViews.swift:33, :40, :47` | `BCDTouchHaptic.tap()` | haptics helper shared |
| `BCDFocus.swift:163` | `BCDFocusSteppers.step(…)` “(BCDTouchLayouts.swift)” | controller focus |
| `BCDTurboLive.swift:128-167` | `case .mouse(let flags): … .leftDown…` | re-posts BCDTouchEvent flags |

### Xcode project registration (app target only, `app/Madeira.xcodeproj/project.pbxproj`)

| file | PBXBuildFile | PBXFileReference | group | Sources |
|---|---|---|---|---|
| `BCDTouchCore.swift` | :287 (`A1000BD0`) | :709 (`A2000BD0`) | :1029 | :1611 |
| `BCDTouchControls.swift` | :288 (`A1000BD1`) | :710 | :1030 | :1612 |
| `BCDTouchLayouts.swift` | :289 (`A1000BD2`) | :711 | :1031 | :1613 |
| `BCDTouchEditor.swift` | :290 (`A1000BD3`) | :712 | :1032 | :1614 |
| `BCDTouchLive.swift` | :291 (`A1000BD4`) | :713 | :1033 | :1615 |
| `BCDTouchExtrasLive.swift` | :236 (`A1005415`) | :656 | :1064 | :1645 |
| `BCDTouchLookViews.swift` | :247 | :667 | :1075 | :1656 |
| `BCDTouchLook.swift` | :248 | :668 | :1076 | :1657 |
| `BCDTouchFeelModel.swift` | :264 (`A1005108`) | :684 | :1092 | :1673 |

No ObjC, no bridging-header change, no new target. Second build consumer: `tools/ui-preview.py:51` `ENGINE_BOUND |= {"BCDTouchLive.swift"}` and `:84` adds `BCDTouchExtrasLive.swift` — every engine name added to a “pure” file breaks that preview build.

---

## 2. Replace or coexist? — **Replace**, no switch

* Old views **deleted**, not gated: `grep TouchControlButton|MappingPanel|GestureZonesModel|GestureZonesLayer` over BCD's app → **no matches** (present in OURS `ContentView.swift:4288, :4430, :4680`).
* `GestureZones.swift` absent from BCD's tree and from `project.pbxproj`; `ControlPreset.zones` field removed (`TouchControlPresets.swift:35-39` vs OURS `:34-41`).
* `GlassShape` / `glassFace` / `GlassEffectContainer` deleted app-wide (no matches); BCD's layer draws plain fills “no blur, no shadow, no material, no group opacity” (`BCDTouchControls.swift:9-13`).
* Surviving Madeira machinery untouched: `TouchControlsModel`, `ControlPresetsModel`, `TouchControl`, `TouchControlsHost`, `ControlsWindow`, `TouchControlsOverlay` name, `GamepadInput.configureTouch`, `TouchMouseGate.padOverlay`, `TouchPadSurface`.
* Only switches are upstream's: `MADEIRA_CONTROL_PRESETS` (`TouchControlPresets.swift:425`), `MADEIRA_TOUCH_GAME_DEFAULT` (`:434`), `MADEIRA_CONTROLS_XBOX_DEFAULT`, `MADEIRA_TOUCH_MOUSE`. There is **no** old-vs-new overlay switch. (BCD's plan is the opposite of ours: we want `touch-system = voidlink` defaulting to Madeira.)

### Diff of the touch region (OURS `ContentView.swift:3854-4905` vs BCD `:2486-2956`)

| Concern | OURS | BCD | Change |
|---|---|---|---|
| `ControlAction` | 3855-3975 | 2486-2606 | identical API; unchanged |
| `TouchControl` | 3977-3990 | 2608-2623 | identical (`locked` kept) |
| `TouchControlsModel` props | 3996-4022 (`snapToGrid`, `hapticsEnabled`, `editZoneBaseline`) | 2629-2654 (`opacity` published, `sessionPanel` published; no snap/haptics) | view-only fields removed; **opacity moved into the model**; `sessionPanel` added |
| persistence | `madeira-controls.json`; `Saved{haptics}` 4039-4057 | `bcd-controls.json`; `Saved{opacity,layout}` 2667-2689 | **file renamed, no migration from `madeira-controls.json`** |
| `hitsInteractive` | 4084-4109 (topBar = 2 buttons + layout + kbd) | 2716-2738 (3 buttons + layout + kbd; `!BCDTouchFeel.controlsHidden`) | +session button, +auto-hide |
| `ControlsWindow` | 4111-4143: `hitTest` only | 2743-2788: `sendEvent` override + `hitTest` with `m.sessionPanel`, `HardwareInput.pointerHeldByProgram` nil-branch, `library.performanceRect`, `topBar:false` in session | 3 new hit-test rules, 6 lines of `sendEvent` |
| `TouchControlsHost` | 4146-4174 | 2790-2817 | **unchanged** |
| overlay body | 4176-4278: `zones` observer, `GestureZonesLayer`, `MappingPanel`/`GestureZonePanel`, `LibraryHUD`, `GlassEffectContainer` | 2819-2912: `feel` observer + `feel.hidden` gate, `BCDSessionLiveLayer`, `sessionPanel`→`BCDDeskSessionMenu`, `logPlan` call | zones/panels/HUD/glass removed; session layer/menu added |
| `controls(...)` | 4211-4241 (ForEach `TouchControlButton` in glass container) | 2865 one line → `BCDTouchControlsLive` | **swap point #1** |
| `configureGamepad` | 4243-4257 | 2867-2881 | adds `ControlPresetsModel.shared.logPlan(...)` |
| `topBar` | 4280-4385 (Done+/kbd/gamecontroller/ControlLayoutMenu/pencil/snap/haptics/plus/zone) | 2899 one line → `BCDTouchChromeLive` | **swap point #2** |
| `GlassShape`+`glassFace` | 4387-4428 | — | deleted |
| `TouchControlButton` | 4430-4678 (keys/sticks/mouse/pad + `TouchPadSurface`) | — | logic moved to `BCDTouchKeySurface`+`BCDTouchPress` (`BCDTouchControls.swift:402-497`, `BCDTouchCore.swift:216-273`) |
| `MappingPanel` | 4680-4905 | — | → `BCDTouchInspector` (`BCDTouchEditor.swift:243-436`) |
| `TouchControlsHost.attach()` sites | 1427, 1439, 1476, 1537 + `Library.swift:1298` | 1119, 1122 only (`sessionBody`) | BCD consolidated |

---

## 3. Sink usage inside `BCDTouch*`

Only two files call sinks. Pad state never appears here — controller controls are delegated to Madeira's surface.

| file:line | call | args / notes |
|---|---|---|
| `BCDTouchLive.swift:103` | `winios_post_key(vk, down ? 1 : 0)` | `vk` = Windows VK, already Madeira's convention |
| `BCDTouchLive.swift:104` | `winios_pointer(0, 0, flags, 0)` | button flags only, at the engine's cursor |
| `BCDTouchLive.swift:105` | `MetalBackedView.toggleKeyboard()` | `.toggleKeyboard` |
| `BCDTouchLive.swift:109` | `AnyView(TouchPadSurface(control: control, action: name, changed: changed))` | `name` = `"A"…"RT"`, `"LS"/"RS"`; → `GamepadInput.touch(owner:control:value:)` via `TouchGamepad.swift` |
| `BCDTouchCore.swift:157-158` | `leftDown 0x0002, leftUp 0x0004, rightDown 0x0008, rightUp 0x0010` | SendInput flags |
| `BCDTouchCore.swift:193-213 / :196-213` | `stickChange(from:to:keys:)` → per-key `.key(vk,down:)` | WASD `[0x57,0x44,0x53,0x41]`, arrows `[0x26,0x27,0x28,0x25]`; deadzone 22 %, 8-way (`:186-199`) |
| `BCDTouchExtrasLive.swift:245-247` | `winios_pointer(x, y, .move|.absolute, 0)` + `winios_cursor_move(x, y)` | **absolute** placement (Pencil & gesture aim), flags `0x1 | 0x8000` |
| `BCDTouchExtrasLive.swift:248-249` | `winios_pointer(x, y, leftDown|absolute, 0)` etc. | absolute click |
| `BCDTouchExtrasLive.swift:252-254` | `move|absolute` → `down|absolute` → asyncAfter `up|absolute` | tap = press-hold-release; `middleDown 0x20 / middleUp 0x40` (`:241`) |
| `BCDTouchCore.swift:150-159` | `BCDTouchEvent{key,mouse,toggleKeyboard}` | the whole vocabulary — **no wheel, no relative-move, no gyro event** |

**Wheel / relative / gyro are not in `BCDTouch*`:**

| feature | where BCD actually puts it |
|---|---|
| wheel | `BCDInputActions.swift:132, :138` `[(0, wheelFlag 0x0800, ±120)]`, posted by `BCDRadialLive.swift:28` (`winios_pointer(0,0,flags,data)`) and by gestures |
| relative mouse | `ContentView.swift:739` `winios_pointer(ix, iy, F_MOVE 0x1, 0)` (no `F_ABS`); `:557-559` `F_WHEEL 0x800, F_ABS 0x8000` |
| gyro | separate `BCDGyroLive.swift:22-23, :120, :217, :233-244`: mouse via `HardwareInput.postRelative`, stick via `GamepadInput.padSample` merging `state.rx/ry` of `winios_gamepad` |
| turbo/macros on touch events | `BCDTurboLive.swift:108-167` intercepts `BCDTouchEvent` before the sink |

---

## 4. Per-game binding

Two independent mechanisms, both inherited/kept by BCD:

| what | storage | code |
|---|---|---|
| layout for a library game | `LibraryEntry.controlLayout` (+ `controls`, `touchControls`, `controlOpacity`, `controlSize`) in the library JSON | `Library.swift:184-205`, load `:1166-1182`, save `:1408-1417` |
| named layouts | `Documents/bcd-control-presets.json` (`bcd-controls.json` = working copy, remembers `layoutID`) | `TouchControlPresets.swift:10-22, :443-445` |
| auto-bind on first touch-on | `ControlPresetsModel.applyGameDefault(steam:reason:)` — picks `builtin.xbox` for Steam, `builtin.keyboard` otherwise, only when controls empty, visible, not editing | `:532-550`; called from `BCDTouchLive.setVisible` (`BCDTouchLive.swift:203-208`) |
| round-604 per-game input lines (look, aim, gestures, pencil, turbo, pointer) | **UserDefaults** `bcd.input.<feature>` keyed by `windowsPath`, empty path = all games | `BCDInputPrefs.swift:18-36` |
| layout sharing / import | JSON envelope `BCDControlShare.export/parse`, `maxBytes` gate, decoder is second gate, never replaces | `BCDControlShareLive.swift:21-82` |

No `GameConfigs/<hash>.cfg` involvement for layouts. Bind-by-game is by `windowsPath` for input features and by `LibraryEntry` for layouts — two different keys.

---

## 5. Lessons / fragility (shape only, no code copied)

**Worked**

1. Swap at two view factories, not at the host: `TouchControlsOverlay` keeps `GeometryReader`/pinch/gating; only `controls`+`topBar` change (`ContentView.swift:2865, :2899`). This is the cheapest possible hook and survives host refactors.
2. Reuse the same overlay for the Settings editor by wrapping it in a landscape-checking host (`BCDSettingsLive.swift:420-429`) instead of a second editor entry point.
3. One engine adapter file (`BCDTouchLive.swift`) conforming to narrow protocols (`BCDTouchInput`, `BCDTouchEditorActions`, `BCDTouchLayoutActions`) — views stay engine-free and compile in a second preview target (`tools/ui-preview.py:157`).
4. Events modelled as a value enum (`BCDTouchEvent`) so turbo (`BCDTurboLive`) can wrap them without touching views.
5. Delegate controller controls to the existing `TouchPadSurface` rather than re-implementing pad state — zero new sink risk.

**Fragile against upstream churn**

1. `BCDTouchLive.swift:27-73` converts `ControlAction` ↔ `BCDTouchAction` and `TouchControl` ↔ `BCDTouchItem` field-by-field; upstream adding an action case or a `TouchControl` field breaks compilation in the adapter (good) but silently drops fields if the mapping is forgotten.
2. `TouchControlPresets.swift:548, :558` and `BCDTouchNames.layoutName` pull upstream log/naming code into BCD; ours' `[touch]` log (`ContentView.swift:4259-4262`) will move too.
3. Renaming persisted files (`madeira-controls.json` → `bcd-controls.json`, `madeira-control-presets.json` → `bcd-control-presets.json`) with **no migration** (`ContentView.swift:2667-2668`; no `madeira-controls` string anywhere in BCD) throws away an upstream user's controls. Do not copy that.
4. Model churn: BCD added `opacity`/`sessionPanel` to the model and dropped `snapToGrid`/`hapticsEnabled`; upstream wave-5 (`a9ce1d4`) already reworks this area, so every upstream merge into `ContentView.swift` must be re-checked against BCD's overlay deletions.
5. `hitsInteractive` hard-codes the top-bar button count (`ContentView.swift:2722`); BCD's 4th button is encoded there — any new bar button silently breaks hit-testing.
6. `BCDTouchFeel.controlsHidden` is a `nonisolated(unsafe)` static mirror of a `@Published` (`BCDSessionFeel.swift:176-184`) read from `hitTest`; correct only because everything is main-thread.
7. `BCDTouchPress` static `BCDTouchHaptic.tap()` uses one shared `UIImpactFeedbackGenerator` (`BCDTouchLayouts.swift:400-403`).
8. `ContentView.swift:504-505, :765` are conditional deletions of upstream double-tap; upstream refactoring those branches silently loses the “gesture replaces click” rule.
9. `mapPoint` had to become internal (`:344`) for the Pencil — an access-level coupling between ContentView and the extras file.
10. Any engine symbol added to `BCDTouchCore/Controls/Editor/Layouts/Look/FeelModel` breaks the preview build until `ui-preview.py` `ENGINE_BOUND` is updated (`:51, :84`).
11. BCD's style choices that are policy, not shape: no SwiftUI animations at all (“animations over a running game have crashed the app”, `BCDTouchControls.swift:10-11`), and a `.id(feel.revision)` full redraw for tint changes (`BCDTouchLive.swift:308`).

**Licence**

`BCDTouch*.swift` headers are `SPDX-License-Identifier: GPL-3.0-only` + `Copyright 2026 thebcd69 (BCD)` + the “BCD Material” line (verified in all 9 files, `:1-3`). `LICENSE-BCD.md` §1 defines BCD Material; §4(b)(2) requires the About/Licences line `Includes work from BCD by thebcd69 (https://github.com/thebcd69/bcd-games)` if we ship any of it; §4(c) requires marking modified files with a date and forbids presenting a fork as official BCD; §4(d)-(e) forbid using the BCD name/logo for endorsement or as a trademark. Porting **shape only** (protocol split, view-swap points, event enum, adapter file, `TouchPadSurface` delegation) copies no BCD Material; if any line is taken, its header and the §4(b) notice are mandatory. Madeira side remains GPL-3.0-or-later, so a combined work conveys as GPL-3.0.