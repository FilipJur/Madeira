<!-- Scout report captured 2026-10-30 by the lead from VoidLinkRecon. Facts as of that date; [INFERENCE] marks unverified claims. -->

## Summary

**Canonical repo:** `The-Fried-Fish/VoidLink-previously-moonlight-zwm` — a fork of `moonlight-stream/moonlight-ios`. 1,176★ / 125 forks. **Code lives on branch `Integration`**, not the default (`ReadmeBranch` is README-only).

| repo | status |
|---|---|
| **The-Fried-Fish/VoidLink-previously-moonlight-zwm** | **canonical**; latest code commit `fa42805997b7f82f1a9dc04d72e149cde4ebd07b` on `Integration`, **2026-10-28T10:57:38Z** ("restore safeArea option for iPad"); repo `pushed_at` 2026-10-28T11:28:43Z |
| ali0613/VoidLink-… | fork of the above, created 2026-10-25, `pushed_at` 2026-10-25T10:11:49Z, identical tree size (258,759 KB), 0★ — stale mirror |
| jasdeep-dhillon/voidlink | fork of the above, `pushed_at` 2026-10-23T10:25:18Z, 0★ — stale mirror |
| hmy1210/moonlight-ios-NativeMultiTouchPassthrough | fork of the above, `pushed_at` 2025-06-26, 0★ — very stale |
| moonlight-stream/moonlight-ios | upstream, GPL-3.0, `master` |

Other branches on canonical: `@Acaki_frame_pacing_metal`, `iOS26UI` (`691aa9c899f313beea16fec0dac816d1810447a3`), `noWaterMark` (`6db518f4`), `Moonlight-iOS-ZWM-Updated`, `compatibilityArchive-iOS12.0/iOS13`, `tvOS-Buildable`.

**Releases** (none since Aug 2024; development continues on `Integration`): `OSCNative-Hybrid` (published 2024-08-18, "Onscreen control & native multi-touch hybrid mode", ipa `20240818V902-moonlight-iOS-ZWM-AltStore.ipa`), `betterGestureRecognizer` (2024-05-17/updated 2024-08-10), `9.0.2-ImprovedCustomSwipe` (2024-09-07). App Store: `id6747717070` (VoidLink) + `id6755103808` (VoidLink Extreme), per `ReadmeBranch` README.

## License verdict

- **VoidLink**: `LICENSE.txt` = GPLv3 verbatim (35,147 B, "Version 3, 29 June 2007"); GitHub API `license: gpl-3.0`. **No "or later" clause anywhere observed** → **GPL-3.0-only**.
- **moonlight-ios** (parent): GPL-3.0 (API-confirmed).
- **Madeira**: `LICENSE`/`COPYING` (35,150 B) + `LICENSE-EXCEPTION.md` — "GNU General Public License, version 3 **or (at your option) any later version**" plus the *Madeira Converter Exception v1* (GPL-3 §7 permission for Apple Metal Shader Converter + Apple system frameworks), adopted **2026-09-24** by Will Faust.
- **Compatible for the port**: GPL-3.0-only code may be combined into a GPL-3.0-or-later work (§13 permits upgrade; the combined work is then GPL-3.0). Two caveats: (1) almost every OSC file header reads `Copyright © True砖家 @ Bilibili. All rights reserved.` while the repo is GPLv3 — provenance audit needed before verbatim copying; upstream base is moonlight-ios + community PRs moonlight-stream#563/#565; (2) Madeira's §7 exception covers *only* Madeira-authored code, so imported VoidLink files stay plain GPL-3.

## Files (branch `Integration` @ `fa42805`, all paths under `VoidLink/`)

### Widget runtime
| path | bytes | contents |
|---|---|---|
| `Input/OnScreenWidgetView.swift` | 232,963 (~5.1 kLOC) | `@objc class OnScreenWidgetView: UIButton`. **One class renders every widget kind**, dispatched on `cmdString`/`touchPadString`. `WidgetTypeEnum {uninitialized, button, touchPad}` (L81-85). Capability flags (L234-285): `isDisplacementBasedStickPad, hasAnchorMode, isMousePadWithButtonActions, isRegularFunctionalButton, isMotionControlButton, isDirectionPad, hasWalkSprintKeys, hasL3R3Indicator, isStickWheel, isFolder, isMagnifier, hasAutoTap, hasInertia, hasHapticFeedback`. CALayer rendering (`stickAnchorLayer`, `stickThumb`, `stickWheelAxis`, `lrudDirectionLayer`, `buttonDownVisualEffectLayer`, `l3r3Indicator`). cmdString parsing L482-519; combo sequencer L2354-2434; touch handling `moveByTouch` L~2700, `handleControllerTouches*` L2728-2760, touchpad switch L2949-3090, button-action switch L3141-3200, finger-up L3485-3600. |
| `Input/AbstractGamepadOverlayWidgetView.swift` | 21,150 | `AbstractGamepadOverlayView: UIView` + `AbstractGamepadOverlayCloseButtonDelegate`; draggable/resizable abstract analog-pad overlay; persists `AbstractGamepadOverlay.overlay.centerXRatio / centerYRatio / overlay.width` in NSUserDefaults; toggled by `GAMEPADOVERLAY` widget. |
| `Input/OnScreenControls.{h,m}` | 5,084 / 96,838 | legacy CALayer OSC + **bridge to the input sink**: `pressDownControllerButton:`, `releaseControllerButton:`, `updateLeftTrigger:`, `updateRightTrigger:`, `sendLeft/RightStickTouchPadEvent:`, `clearLeft/RightStickTouchPadFlag`, `showLegacyWidgetsWith:`, `drawButtons:`, `setDPadCenter:`, `setAnalogStickPositions:`; L190-212 shows each forwards to `ControllerSupport` + `updateFinished:`. |
| `Input/ControllerSupport.{h,m}` | 3,664 / 103,018 | merges physical + virtual gamepad state; **the only place `LiSendMultiControllerEvent` is emitted** (m:932, tvOS variant m:928); also motion (m:388/438/478/515), controller touchpad (m:1293-1302), arrival (m:1267), battery (m:1053), mouse (m:1624/1636-1654/1670/1681). |
| `Input/CommandManager.swift` | 29,869 | **command vocabulary + DSL parser + macros**. `mouseButtonMappings`, `oscButtonMappings`, `oscRectangleButtonCmds`, `touchPadCmds`, `functionalButtonCmds`, `motionControlButtonCmds`, `keyboardButtonMappings` (full Windows VK + `…MAC` scancodes), `touchPadCmds` subsets, `extractCmdStrings(from:)` L580-660, `extractAutoReleaseButtonStrings(from:)` L525, `sendAutoReleaseComboCommand` L737, `sendKeyComboDown/Up` L785/793; `RemoteCommand` (NSSecureCoding, persisted under `"savedCommands"`). |
| `Input/MotionHandler.swift` | 28,106 | gyro/accel → stick-or-mouse mapping (`GYRO/GYROPAUSE/ACCEL/MOTION` widgets), mixes with vpad stick input. |
| `Input/LayoutOnScreenControls.{h,m}` (in `Input/CustomOSC/`) | 1,886 / 18,731 | container view hosting `OnScreenWidgetView`s + legacy layers; `layoutChanges` undo stack; `updateGuidelinesFor(onScreenWidget:)`. |
| `Input/InputAccessoryBar.swift` | 48,285 | in-stream toolbar, also creates shortcuts/widgets (`WidgetPickerViewControllerDelegate`, L503). |
| `Input/HapticContext.{h,m}` 749/13,336 · `PressureCurve.swift` 37,160 · `PencilHandler.swift` 37,360 · `CursorInertia.swift` 4,712 · `InertialScroller.swift` 1,259 · `SafeTimer.swift` 4,666 · `RadialMenuOverlayView.swift` 7,216 · `ControllerNavigator.swift` 123,838 · `ControllerUtil.swift` 79,891 · `MicHandler.swift` 74,929 | | support/adjacent |
| `Input/{AbsoluteTouchHandler.m 12,344, RelativeTouchHandler.m 18,103, NativeTouchHandler.m 15,913, PureNativeTouchHandler.m 15,001, TrackpadTouchHandler.swift 16,988}` | | the 4 touch/passthrough modes (out of scope) |

### Data model / persistence
| path | bytes | contents |
|---|---|---|
| `Input/CustomOSC/OSCProfile.h` + `.m` | 4,702 / 16,903 | `OSCProfile : NSObject <NSCoding, NSSecureCoding, NSMutableCopying>`. |
| `Input/CustomOSC/OnScreenButtonState.h` + `.m` | 5,344 / 9,877 | per-widget descriptor + `OnScreenWidgetType{Legacy,Custom}`, `WidgetSizeReference{longSide,shortSide}`, `MouseButtonAction{hovering,leftButtonDown,middleButtonDown,rightButtonDown,noClick}`, `ButtonMode{slideToToggle,slideAndHold,regular,tapToToggle,movable}`, `RevealMode{coexist,exclusive}`. |
| `Input/CustomOSC/OSCProfilesManager.swift` | 24,400 | CRUD, NSKeyedArchiver persistence, import/export, bundled-template import (`PresetConfigs/widgetTemplates{IPhone,}.bin` via `ProfileFileContainer.unpackedData(from:)`). |
| `PresetConfigs/widgetTemplates.bin`, `widgetTemplatesIPhone.bin` | | shipped default profiles (binary keyed archive). |
| `Stream/StreamConfiguration.h` | | `appID`, `gyroMode`, `gamepadMask`, `swapABXYButtons`, `buttonVisualFeedback`, `emulatedControllerType`… **no OSC-profile field**. |

### Editor UI
| path | bytes |
|---|---|
| `ViewControllers/CustomOSCViewControl/LayoutOnScreenControlsViewController.swift` | 131,955 |
| `ViewControllers/CustomOSCViewControl/LayoutOnScreenControlsViewController.m` | 109,688 |
| `ViewControllers/CustomOSCViewControl/Table/ProfileSelectorViewController.swift` | 69,499 |
| `ViewControllers/CustomOSCViewControl/{WidgetPanelStackView.m 761, ToolBarContainerView.m 580}` | small |
| `ViewControllers/SettingsSwiftUI.swift` | 361,309 (session settings incl. `Safe Area`/`FullScr` options) |

`WidgetPickerViewController` (shared SwiftUI picker) is referenced from `LayoutOnScreenControlsViewController.swift:~1551`, `ToolboxViewController.swift:517/554`, `InputAccessoryBar.swift:503`; its declaration is in a file I did not enumerate — [INFERENCE] a SwiftUI file of the target not matching `*Picker*`.

## Architecture

```
StreamView.m  ── updateTouchHandlerWithProfile: (StreamView.m:289-329)
   │              → Absolute | Relative | Native | PureNative | Disabled handler
   │              → in non-absolute modes also: [_onScreenControls handleTouchDown/Moved/UpEvent:]
   ▼
OnScreenControls.m (legacy CALayer pad)   InputStreamView (hosts widgets)
   │                                         └── LayoutOnScreenControls.m  ← container + undo store
   │                                              └── OnScreenWidgetView (×N, Swift)
   │                                                   ├── parse cmdString via CommandManager
   │                                                   ├── combo sequencer (sendComboButtonsDown/UpEvent)
   │                                                   └── per-kind touch maths
   ▼
ControllerSupport.m  ── merges physical GCGamepad state + virtual flags/triggers/sticks
   │                    setButtonFlag:/clearButtonFlag:/updateLeftTrigger:/updateRightTrigger:/updateFinished:
   ▼
moonlight-common-c (submodule → github.com/TrueZhuangJia/voidlink-c.git)  LiSend* IPC
```

`OnScreenWidgetView` **never** calls `LiSend*` for gamepad state — it only calls `onScreenControls.pressDownControllerButton:` / `updateLeftTrigger:` etc., which funnel into `ControllerSupport`. It *does* call `LiSend*` directly for keyboard, mouse, mouse-position, scroll and controller-touchpad.

## Report

### 1. Example command strings (the DSL that defines a widget)
Parsed at `OnScreenWidgetView.swift:482-519`; tokens split on `-`, validated against the union of the five mapping tables with regex `^(?:keys)(?:-(?:keys))*(?:-\d+MS)?$` (`CommandManager.swift:~610`). `+`-joined strings are *legacy* multi-key combos (L510, L2063).

- `OSCA` → single pad button. `LSWHEEL` → stick wheel with implicit `OSCL3` combo (L498-505).
- `OSCX-OSCY-100MS-OSCB` → multi-action button: press X, 100 ms, press Y, 100 ms, press B (a "macro"), all released on finger-up (`sendComboButtonsDownEvent`, L2354).
- `WASDPAD-OSCL1-OSCL3` → WASD mini-stick pad that also holds L1 (sprint) / L3 (walk) with thresholds (`walkModeThreshold`, `sprintKeyThreshold`).
- `DPAD-OSCA` → d-pad whose double-tap fires the A combo.
- `MOUSEPAD-MRIGHT` / `ABSMOUSEPAD` / `DS4TOUCH-DS4TCHBTN` / `TRACKBALL` / `DISCRETEWHEEL` / `MAGNIFIER` / `FOLDER` / `LABELEDFOLDER` / `GYRO` / `GAMEPADOVERLAY`.

**Widget catalogue** (`CommandManager.touchPadCmds`): `LSVPAD, RSVPAD` (velocity sticks) · `LSPAD, RSPAD` (displacement sticks) · `LSWHEEL, RSWHEEL` (stick wheels) · `LTPAD, RTPAD` (trigger pads) · `DS4TOUCH` (DS4/DualSense touchpad) · `MOUSEPAD, ABSMOUSEPAD, ABSMOUSE, TRACKBALL` · `MOUSEWHEEL, WHEEL, DISCRETEWHEEL, DSWHEEL` · `DPAD, WASDPAD, ARROWPAD` · `MAGNIFIER, DUMMYPAD`.
Functional buttons: `SETTINGS, TOOLBOX, DISCONNECT, QUITAPP, PIP, WIDGETTOOL, ABSGAMEPAD, WIDGETPROFILES, PROFILES, PICKPROFILE, PICKPRFL, SOFTKEYBOARD, ABSTCHDRAG, FOLDER, LABELEDFOLDER, PRESSURECURVE, PENCILHOVER, BRUSH, ERASER, NOSINGLETOUCH, DISABLETILT, DISABLETOUCH, GAMEPADOVERLAY, PUSHTOTALK`.
Motion: `GYRO, GYROPAUSE, ACCEL, MOTION`.

### 2. Data model
`OSCProfile`: `name`, `buttonStatesEncoded:NSMutableArray<NSData*>` (each = archived `OnScreenButtonState`), `isSelected` (exactly one), plus per-profile globals — `touchMode`, `pointerVelocityModeDivider`, `touchPointerVelocityFactor`, `normalizedStreamViewOffset`, `streamViewScale`, `gamepadOverlayEnabled`, `dualSenseTransient`, pencil block (`pressureCurvePoints`, `phase1/2StrokeSampleIndexEnd`, `doubleTapShorcutEnabled`, `brushShortcut`, `eraserShortcut`, `squeeze*Shortcut`, `pencilPausesNativeTouch`, `pencilAndHoverMode`), gyro block (`useBuiltinGyro, swapYawAndRoll, mapGyroTo{mouse,controllerStick,driftCorrection}, yawPitchToRightStick, rollToLeftStick, synthesizePhysicalStick, gyroSensitivity{Yaw,Pitch,Roll}, accelSensitivity{X,Y,Z}, gyroToStickMinOffset, physicalLeft/RightStickMinOffset, controllerGyroSwitch{Mode,Hold,Toggle}, reverseGyroHoldButton`), folder bookkeeping (`unfoldedExclusiveFolderSequence`, `postExclusiveUnfoldedSequences`).

`OnScreenButtonState`: `name, alias, folded, revealMode, bulkMoveEnabled, sequence, parentSequence, sequenceSet, autoDockTimer, dockedAlpha, position(normalized CGPoint), isHidden, buttonMode, widgetType, sizeReference, widthFactor, heightFactor, componentSizeFactor, borderWidth, highlightSizeFactor, sensitivityFactorX/Y, slideThreshold, yaw/pitch/rollFactor, decelerationRateX/Y, touchPointAnchored, stickIndicatorOffset, walkModeThreshold, minStickOffset, widgetShape, oscLayerSizeFactor, backgroundAlpha, labelAlpha, borderAlpha, highlightAlpha, vibrationStyle, mouseButtonAction, animatesTransition, autoTapInterval, autoTapRepeats, walkKeyActionType/Threshold, sprintKeyActionType/Threshold`. `sequence/parentSequence` = arbitrary folder tree.

**Persistence format** (no JSON, no plists-as-dicts): `NSKeyedArchiver` with `requiringSecureCoding:true`, whitelists `[NSString, NSMutableData, NSMutableArray, OSCProfile, OnScreenButtonState]` (profile) and `[NSString, OnScreenButtonState, NSSet, NSNumber]` (state) — `OSCProfilesManager.swift:52-65`. Stored as `Data` under `NSUserDefaults.standard` key **`"OSCProfiles"`** = archived array of archived profile `Data`. Template-refresh sentinel `"widgetProfileUpdated-20261016"` (bumped key ⇒ re-import bundled templates). Defaults shipped as `PresetConfigs/widgetTemplates.bin` / `widgetTemplatesIPhone.bin` inside a `ProfileFileContainer` wrapper. Export/import = the same archive; name collisions get `" - Restored"`; profile index 0 named `Default` cannot be deleted (`deleteCurrentSelectedProfile`, L~110). Macros: `RemoteCommand{identifier,cmdString,alias}` array archived (insecurely) under key `"savedCommands"`.

**No per-game binding**: neither `OSCProfile` nor `StreamConfiguration.h` carries an app ID — the selection is global (`isSelected`) and switched at runtime from the in-stream toolbar / `PICKPROFILE` widget / profile selector VC. Per-game profiles would be new work.

### 3. Editor UI (`LayoutOnScreenControlsViewController`, Swift 132 KB + ObjC 110 KB + storyboard `LayoutOnScreenControlsView`)
`viewDidLoad` binds `OSCProfilesManager.sharedManager(view.bounds)`; `reloadOnScreenWidgetViews` → `loadWidgets(from:to:)` builds the widget tree from `buttonStatesEncoded`; `denormalizeWidgetPosition` converts normalized → points (L334). Operations present: add (`addTapped` → SwiftUI `WidgetPickerViewController`, fallback `presentLegacyAddWidgetAlert`), edit (`editTapped` → `presentLegacyEditWidgetAlert`), duplicate (in picker payload `pickerAction`), delete (`trashCanTapped` + drag-over-trash detection L2562), undo (`layoutChanges` stack + `undoTapped`), bulk/batch edit (7 sliders: width/height/alpha/borderAlpha/labelAlpha/borderWidth/highlightAlpha/highlightSize — `bulkEditButtonTapped`), resize sliders (`widgetSizeSliderMoved`, `widgetHeightSliderMoved`, `componentSizeSliderMoved`), per-widget sensitivity X/Y, `slideThresholdSliderMoved`, `anchorModeChanged`, `decelerationRateSliderMoved`, `autoDockTimerSliderMoved` + `dockedAlphaSliderMoved`, `animationChanged`, `mouseDownButtonChanged`, `buttonModeChanged`, `collectionHiddenChanged`(folded), `revealModeChanged`, `bulkMoveChanged`, `vibrationStyleChanged`, `walkKeyActionChanged`/`sprintKeyActionChanged` + thresholds, `yawFactorSliderMoved`/`pitch`/`roll`, `stickIndicatorOffsetSliderMoved`, `minStickOffsetSliderMoved`, save/load/import/export (`saveTapped`, `loadTapped`, `importFromOtherButtonTapped`), orientation relayout (`viewWillTransition`, `handleOrientationChangeForOnScreenWidgets`), guideline snapping (`updateGuidelinesForOnScreenWidget`, `isHorizontallyAligned/alignedX`).
`ProfileSelectorViewController.swift` (69,499 B) = profile list: select / duplicate / delete / rename / import / export / reorder / share.

### 4. Input-sink calls a port must re-implement
All from moonlight-common-c (`voidlink-c` fork submodule). Evidence = file:line above.

| # | call | emitted by | needed for |
|---|---|---|---|
| 1 | `LiSendMultiControllerEvent(playerIdx, activeGamepadMask, buttonFlags, lTrigger, rTrigger, lStickX, lStickY, rStickX, rStickY)` | `ControllerSupport.m:932` | **the one merged virtual-gamepad state push**; every OSC button/trigger/stick ends here |
| 2 | `LiSendControllerMotionEvent(idx, LI_MOTION_TYPE_ACCEL\|GYRO, x,y,z)` | `ControllerSupport.m:388/438/478/515/1976` | `GYRO/ACCEL/MOTION` widgets, `MotionHandler` |
| 3 | `LiSendControllerTouchEvent(idx, LI_TOUCH_EVENT_DOWN\|MOVE\|UP, pointerId, x, y, pressure)` | `OnScreenWidgetView.swift:2736/2747/2757`, `ControllerSupport.m:1293-1302` | `DS4TOUCH` widget + physical touchpad |
| 4 | `LiSendMouseMoveEvent(dx, dy)` | widget `:2954/2963/1967`, `ControllerSupport.m:1624` | `MOUSEPAD`, `TRACKBALL`, inertia |
| 5 | `LiSendMouseMoveAsMousePositionEvent(dx, dy, w, h)` | widget `:2975` | `ABSMOUSE` edge-warping |
| 6 | `LiSendMousePositionEvent(x, y, w, h)` | widget `:2991/2980/3142/3199` | `ABSMOUSEPAD`, `ABSMOUSE` |
| 7 | `LiSendMouseButtonEvent(BUTTON_ACTION_PRESS\|RELEASE, BUTTON_LEFT\|MIDDLE\|RIGHT\|X1\|X2)` | widget `:1926/1932/2349/2398/3151-3182`, `StreamView.m:1516/2115` | mouse-button widgets, mouse-pad tap modes |
| 8 | `LiSendScrollEvent(d)` / `LiSendHighResScrollEvent(d)` / `LiSendHighResHScrollEvent(d)` / `LiSendHScrollEvent(d)` | widget `:2347/3052/3055/3067/3084/3087`, `StreamView.m:1842/1851/1878/1886` | `WHEEL/DISCRETEWHEEL/DSWHEEL/MOUSEWHEEL` |
| 9 | `LiSendKeyboardEvent(keycode, KEY_ACTION_DOWN\|UP, mods)` | `CommandManager.swift:788/796`, widget `:2342/2395/3578-3587` | `WASDPAD/ARROWPAD`, keyboard-command widgets, macros |
| 10 | `LiSendKeyboardEvent2(keycode, action, mods, SS_KBE_FLAG_NON_NORMALIZED)` | `StreamView.m:2023/2025` | non-US scancodes from command tool |
| 11 | `LiSendUtf8TextEvent(utf8, len)` | `StreamView.m:1931/1981` | text-entry (not OSC) |
| 12 | `LiSendPenEvent` / `LiSendPenEventWithBarrelRoll` | `StreamView.m:1335/1266` | `BRUSH/ERASER/PENCILHOVER` |
| 13 | `LiSendControllerArrivalEvent(...)` / `LiSendControllerBatteryEvent(...)` | `ControllerSupport.m:1267/1053` | announce virtual pad so the host enables gamepad |
| 14 | `LiGetHostFeatureFlags()` | `StreamView.m:1235` | gate pen vs. synthesized touch |

Plus the non-`Li` glue an adapter must mirror: `ControllerSupport` methods `setButtonFlag:flags:`, `clearButtonFlag:flags:`, `updateLeftTrigger:left:`, `updateRightTrigger:right:`, `updateFinished:`; `OnScreenControls` `sendLeft/RightStickTouchPadEvent::`, `clearLeft/RightStickTouchPadFlag`; and the button-flag constants `A_FLAG, B_FLAG, X_FLAG, Y_FLAG, LB_FLAG, RB_FLAG, LS_CLK_FLAG, RS_CLK_FLAG, PLAY_FLAG, BACK_FLAG, UP/DOWN/LEFT/RIGHT_FLAG, TOUCHPAD_FLAG, PADDLE1..4_FLAG, MISC_FLAG, SPECIAL_FLAG` (`CommandManager.swift` `oscButtonMappings`).

**Madeira mapping**: because `OnScreenWidgetView` only pushes flags/triggers/sticks through `OnScreenControls → ControllerSupport`, the port surface is ~6 ObjC methods + 14 free functions. Implement a `ControllerSupport`-shaped façade over Madeira's virtual pad (XInput/HID into the Wine/FEX session) and 11–13 become no-ops/rewrites; keep the `Li*`-shaped signatures so widget code compiles unchanged.

### 5. Port value ranking
**Take**: profile model + manager (archive format, templates, export/import, "Restored" merge), `OnScreenWidgetView` widget catalogue and touch maths (sticks/triggers/d-pad/wheels/mouse pads/discrete wheels/magnifier/folders/auto-dock/walk-sprint/auto-tap/inertia), cmdString DSL + MS-delay combo sequencer, `CommandManager` VK table + `RemoteCommand` macros, the whole layout editor (batch edit, undo, trash, picker), `AbstractGamepadOverlayView`, gyro field set + `MotionHandler`.
**Drop / Moonlight-only**: `StreamView` touch handlers and all four touch modes, `AbsoluteTouchHandler/RelativeTouchHandler/NativeTouchHandler/PureNativeTouchHandler`, host discovery + `Crypto/` (PIN/cert), `Metal/`, `Stats/`, `Network/`, `MicHandler`, `ControllerUtil`'s MFi mapping (unless MFi support is wanted), and all `LiSend*` bodies (re-point to Madeira's sink).
**Watch**: size (§ above) — `OnScreenWidgetView.swift` 233 KB and `LayoutOnScreenControlsViewController.swift` 132 KB are monoliths; hard deps to stub are `ControllerUtil.gamepadArrivalReported`, `OnScreenControls.shared()`, `PublicUtils`, `LocalizationHelper`, `GenericUtils`, `AlertControllerUtil`, `SafeTimer`. Total subsystem ≈ **1.4 MB source ≈ 35 kLOC** (`Input/` ~1.05 MB/~26 kLOC, editor subtree ~350 KB/~9 kLOC) [INFERENCE from byte sizes at ~38 B/line — measured sizes, estimated LOC].

URLs: repo https://github.com/The-Fried-Fish/VoidLink-previously-moonlight-zwm · code branch https://github.com/The-Fried-Fish/VoidLink-previously-moonlight-zwm/tree/Integration · blob root for citations `https://raw.githubusercontent.com/The-Fried-Fish/VoidLink-previously-moonlight-zwm/fa42805997b7f82f1a9dc04d72e149cde4ebd07b/` · upstream https://github.com/moonlight-stream/moonlight-ios · Madeira https://github.com/willfaust/Madeira (license exception: `/blob/main/LICENSE-EXCEPTION.md`)
