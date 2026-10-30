# VLTouch port: file map, sink contract, slicing

Lead document, fork only. Inputs: `research/r1-voidlink-deps.md` (R1), `r2-madeira-sinks.md` (R2), `r3-overlay-host.md` (R3), `r4-bcd-hook.md` (R4), all 2026-10-30 against Madeira `fork/main` `67bd667`, VoidLink `fa42805`, BCD `05e9f6f`. Status: D1-D3 decided by user 2026-10-30; D4 pending.

## Verdicts

| Question | Answer | Evidence |
|---|---|---|
| Wine/driver changes needed? | **No.** `winios_pointer` forwards raw `MOUSEEVENTF_*` + `mouseData` (relative move, absolute move, L/M/R/X1/X2, V/H wheel); `winios_post_key` takes any VK | R2 §3-4, §8 |
| Gamepad path | `GamepadInput.shared.touch(owner:control:value: GamepadSample?)` takes a **full sample per owner** (buttons, `lt/rt` 0-255, sticks Int16), merged by OR / max / stronger vector (`TouchGamepad.swift:84-106`). One owner + one control UUID carries VoidLink's whole virtual pad, analog triggers included. (R2 called analog values a gap; lead verified it is not.) | `GamepadInput.swift:153-160` |
| Button flags | Moonlight low 16 bits == XInput bits (`A_FLAG 0x1000` … `SPECIAL_FLAG 0x0400`); `PADDLE1-4 0x10000-0x80000`, `TOUCHPAD 0x100000`, `MISC 0x200000` have no XInput lane | `moonlight-common-c/src/Limelight.h` (upstream master; VoidLink's `voidlink-c` fork assumed identical [INFERENCE]) |
| Where to host | Inside the existing `ControlsWindow` / `TouchControlsOverlay`; swap only `controls(_:session:)`. Same shape BCD used (R4 §5 "Worked" 1) | R3 §6, R4 §2 |
| Per-game binding | New `LibraryEntry.vlTouchProfile: String?` next to `controlLayout` (`Library.swift:203`), load in `begin()` 1343-1362, save in `saveCurrentProfile()` 1505-1517 | R3 §3 |
| Editor | Storyboard-bound (90 outlets). Extract the one scene into `VLEditor.storyboard`; the `.m` editor is dead code (not in VoidLink's target, verified in its `project.pbxproj`) | R1 finding 1, 6 |

## Sink contract (`app/Madeira/VLTouch/Sink/`)

Widget code keeps calling Moonlight names; only the bodies change.

| VoidLink call | Madeira implementation |
|---|---|
| `ControllerSupport setButtonFlag/clearButtonFlag/updateLeftTrigger/updateRightTrigger/updateLeftStick/updateRightStick` | accumulate into one `GamepadSample` (buttons `& 0xFFFF`) |
| `ControllerSupport updateFinished:` | `GamepadInput.shared.touch(owner: VLSink.owner, control: VLSink.control, value: sample.isZero ? nil : sample)` on main actor |
| `VLSink.control` registration | `configureGamepad` passes `[VLSink.control]` to `GamepadInput.configureTouch` when VLTouch is active (hook H3) |
| `PADDLE*`, `MISC` | dropped (logged once). `TOUCHPAD_FLAG` dropped in wave 1 |
| `LiSendKeyboardEvent(vk, action, mods)` | expand `mods` to `VK_SHIFT/CONTROL/MENU` down/up around `winios_post_key(vk & 0xFF, down)` |
| `LiSendMouseMoveEvent(dx, dy)` | `winios_pointer(dx, dy, 0x0001, 0)` |
| `LiSendMousePositionEvent(x, y, w, h)` / `…MoveAsMousePositionEvent` | scale to `winios_screen_size` pixels, `winios_pointer(X, Y, 0x8001, 0)` |
| `LiSendMouseButtonEvent` | L `0x2/0x4`, R `0x8/0x10`, M `0x20/0x40`, X1/X2 `0x80/0x100` with data 1/2 |
| `LiSendScrollEvent(n)` / `HighRes` / `H*` | `winios_pointer(0, 0, 0x0800 or 0x1000, UInt32(bitPattern: delta))`, notch 120; Moonlight `LiSendScrollEvent` takes notches → ×120 |
| `LiSendControllerTouchEvent`, `LiSendControllerMotionEvent` | no-op in wave 1. Needs a HID publish path in upstream `GamepadInput.swift` and `MADEIRA_PAD_MODE=dualsense` (R2 §5). Later phase |
| Gyro widgets (`GYRO`, `MotionHandler` → stick/mouse) | work through the stick/mouse rows above; no extra sink |
| Threading | `winios_*` any thread; `GamepadInput.touch` main actor. Release all holds on `willResignActive` (R3 §1) |

## Host contract (`app/Madeira/VLTouch/Host/` + three hooks)

- `VLTouchLayer: UIViewRepresentable` → `VLTouchContainer: UIView` that loads `OSCProfilesManager.sharedManager(bounds)`, builds widgets as `StreamView.m:1000-1070` does, answers `point(inside:)` from widget frames.
- `VLTouchLayer.active` = `touch-system` (`MadeiraConfig.gameValue ?? MadeiraConfig.get ?? "madeira"`, same 3-source order as `TouchMouseGate`, `ContentView.swift:60-67`). New key must be added via `build/tools/gen-config-catalog.py` or the catalog check fails.
- `ContentView.swift` hooks (~6 lines): H1 `ControlsWindow.hitTest` after line 4121; H2 first branch of `controls(_:session:)` at 4232; H3 `configureGamepad` 4248-4257. `TouchControlsHost.attach()` unchanged.
- `Library.swift` (~12 lines): field, load, save, restore on `finish()`, settings toggle (global `3033-3036`, per game `3884-3888`, session menu `5142-5149`).
- `OnScreenFunctionalWidgetDelegate` (22 methods) implemented by the host: `SETTINGS` → `LibraryModel.shared.showMenu()`, `QUITAPP`/`DISCONNECT` → `requestQuit()`, `SOFTKEYBOARD` → `LibraryKeyboard.show()`, `PROFILES`/`PICKPROFILE` → `ProfileSelectorViewController`, `WIDGETTOOL` → editor; the rest no-op (R3 §5).

## File map

Verdicts from R1 §1. Paths: VoidLink `VoidLink/…` → `app/Madeira/VLTouch/…`.

| Group | Files (keep, verbatim except marked import/shim lines) | LOC |
|---|---|---|
| Model | `OSCProfile.{h,m}`, `OnScreenButtonState.{h,m}`, `OSCProfilesManager.swift`, `ProfileFileContainer.swift` (moved out of `ProfileSelectorViewController.swift:130-205`), `PresetConfigs/*.bin` | ~1.3k |
| Commands | `CommandManager.swift` | 0.8k |
| Widgets/runtime | `OnScreenWidgetView.swift`, `OnScreenControls.{h,m}` (trim legacy draw), `LayoutOnScreenControls.{h,m}`, `MotionHandler.swift`, `InertialScroller.swift`, `SafeTimer.swift`, `UITouchUtil.swift`, `CustomTapGestureRecognizer.{h,m}`, `AbstractGamepadOverlayWidgetView.swift`, 6 SVGs | ~9.5k |
| Editor | `LayoutOnScreenControlsViewController.swift`, `WidgetPanelStackView.{h,m}`, `ToolBarContainerView.{h,m}`, `VLEditor.storyboard` (scene from `iPhone`/`iPad.storyboard`), 2 imagesets | ~2.7k |
| Pickers | `ProfileSelectorViewController.swift`, `WidgetPickerViewController.swift`, `WidgetPickerView.swift`, `AbstractGamepadView.swift`, `VirtualKeyboardView.swift` | ~10.5k |
| Support (real) | `LocalizationHelper.{h,m}` + Swift ext (table renamed `VLTouch`), `VLTouch.xcstrings` (997 keys, **English values only**, D3), `PublicExtensions.swift`, `AlertControllerUtil.swift`, `GraphicUtils.swift` (SVGKit replaced by `CAShapeLayer` paths, D2) | ~0.7k |
| Compat stubs | `PublicUtils` (~24 members), `GenericUtils` (13, tips → no-op), `ControllerUtil` (5), `ThemeManager` (3), `DataManager`, `StreamConfiguration`, `VoidController`, `StreamFrameViewController` flags, `PencilHandler`, `PressureCurve`, `MicHandler`, `ToolboxViewController`, `ControllerNavigator` + `ControllerNavigationElement` (API stub: `setUINavigationDelegate`, `restorePreviousUINavigationDelegate`, `radialMenuButtonPosition`) | new, small |
| Sink | `ControllerSupport.h` (façade), `VLLiShim.{h,m}` (Li* + constants) | new |
| Dropped | `HapticContext`, `CursorInertia`, `LayoutOnScreenControlsViewController.{h,m}`, `InputAccessoryBar`, `ControllerSupport.m`, `StreamView.*`, `TemporarySettings`, `RadialMenuOverlayView` + `RadialMenuView` (consumer is controller navigation only, R1 §6.4) | |

Total ported ≈ 25k LOC, ~90% verbatim.

## Changes to PLAN.md (approved, D1)

R1 shows the P3 slices are not independently compilable: `OnScreenWidgetView` consumes Model, Commands, Runtime and Sink; the Editor consumes all of those plus Pickers; Model depends on a Pickers file. The planned "stub every API, then 7 workers port in parallel" needs hand-written stubs for hundreds of cross-slice symbols, then each worker swaps a stub for verbatim code and re-fixes the same imports. Proposed instead:

**P2 Import (1 worker + parallel helpers), compile-first:**
1. `third_party/voidlink/` = only the files in the map above, verbatim, plus `LICENSE.txt`, `PROVENANCE.md` (commit, per-file SHA-1, header-licence note).
2. Copy them into `VLTouch/`, change only import lines (`VoidLink-Swift.h` → `Madeira-Swift.h`, `<Limelight.h>` → `VLLiShim.h`), storyboard `customModule`, `ProfileFileContainer` move, each tagged `// VLTouch:`.
3. Compat stubs, `VLLiShim` with **no-op** bodies, `ControllerSupport` façade with no-op `updateFinished`.
4. Register everything in `project.pbxproj` + bridging header + resources; `tools/fork/app-check.sh`.
5. `touch-system` key (default `madeira`) + catalog regen; nothing hooked yet.
Acceptance: app target builds with all VoidLink code linked; upstream touch controls unchanged.

**P3 wave (5 isolated workers, disjoint files, all against P2):**

| Slice | Agent | Owns | Done when |
|---|---|---|---|
| S1 Sink | worker | `VLTouch/Sink/*` | contract table above implemented; throwaway harness proves bytes reaching `winios_*` |
| S2 Host | ui-worker | `VLTouch/Host/*`, `ContentView.swift` (3 hooks), `Library.swift` (field/load/save/toggles) | `touch-system = voidlink` shows the selected profile's widgets in a session; switch off = upstream unchanged |
| S3 Editor | ui-worker | `VLTouch/Editor/*`, `VLEditor.storyboard` | editor opens from `WIDGETTOOL` + Settings, add/move/resize/delete/undo/save round-trip |
| S4 Pickers | ui-worker | `VLTouch/Pickers/*` | profile select/dup/rename/delete/import/export; widget picker adds widgets |
| S5 Model+Compat | worker | `VLTouch/Model/*`, `VLTouch/Compat/*` | iPhone templates import on first run; profile lookup by name for per-game binding; stubs that the runtime actually needs made real (`PublicUtils`, `ControllerUtil.compensated/circulated`) |

`OnScreenWidgetView.swift`, `CommandManager.swift`, `OnScreenControls.m`, `MotionHandler.swift` stay verbatim and unowned in P3; fixes to them happen only in G2 fix rounds, one owner each. Old P4 folds into S2. DS4 touchpad + controller motion become a later phase (they need `GamepadInput.swift` changes).

## Decisions

| # | Decision | Result |
|---|---|---|
| D1 | Restructure P2/P3 as above | **approved** |
| D2 | SVGKit (SPM + `libxml2`, used only by `GraphicUtils` for 6 SVGs ≤2 KB) | **no dependency**: `CAShapeLayer` paths generated once from the 6 SVGs (~150 LOC); `changeColor` keeps working on shape layers |
| D3 | Localization | **English only**: `VLTouch.xcstrings` keeps the `en` value of each key (keys like `=disableTilt` are identifiers, so the English values are required, not the keys) |
| D4 | `RadialMenuOverlayView` + `RadialMenuView` + full `ControllerNavigator` (≈3.6k LOC): drive VoidLink's own screens with a physical controller | pending; lead pick drop (small `ControllerNavigator` stub stays either way, the picker/profile screens reference its API) |
