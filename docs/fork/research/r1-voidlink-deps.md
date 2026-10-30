<!-- Scout report R1VoidLinkDeps captured 2026-10-30 by the lead. Sources: Madeira fork/main 67bd667, VoidLink fa42805, BCD 05e9f6f. [INFERENCE] marks unverified claims. -->

# VoidLink dependency closure — touch-widget port subset

All paths relative to `/tmp/voidlink/VoidLink/` unless prefixed `VoidLinkPreview/`, `/tmp/voidlink/`. Sizes are KiB as reported by the filesystem listing; LOC is exact (counted via out-of-range read on each file). Branch `Integration` @ `fa42805`.

## Summary

| # | Finding | Evidence |
|---|---|---|
| 1 | **Three of the listed roots are dead code.** `LayoutOnScreenControlsViewController.m` (2 083 LOC) and its `.h` are absent from `project.pbxproj` — the Swift rewrite is what compiles; the storyboard's `customClass=` resolves to the Swift class via the Swift runtime name. | `VoidLink.xcodeproj/project.pbxproj:50,373,705` (only `.swift`); no `.m`/`.h` file ref anywhere |
| 2 | `HapticContext.{h,m}` is **not referenced by the subset at all** — only `ControllerSupport.m:994-997` and `VoidController.h:49-52`. Widget vibration is `UIImpactFeedbackGenerator`. | `OnScreenWidgetView.swift:220,780-783` |
| 3 | `CursorInertia` is **not referenced by the subset** — only `RelativeTouchHandler.m:87` (an out-of-scope touch mode). | `Input/RelativeTouchHandler.m:45,87` |
| 4 | **`WidgetPickerViewController` lives in `VoidLinkPreview/`**, not `VoidLink/`, and drags 3 SwiftUI files: `WidgetPickerView` 4 324, `AbstractGamepadView` 2 546, `VirtualKeyboardView` 1 710 → **+8 580 LOC** for the picker slice. | `VoidLinkPreview/WidgetPickerViewController.swift:13-24`; `project.pbxproj:601-602` (member of VoidLink target) |
| 5 | **Model→Pickers hard dependency:** `OSCProfilesManager` (Model) calls `ProfileFileContainer.unpackedData`, whose only declaration is inside `ProfileSelectorViewController.swift` (Pickers). | `OSCProfilesManager.swift:250` ← `ProfileSelectorViewController.swift:153-186` |
| 6 | Editor is **storyboard-bound**: 90 `@IBOutlet` implicitly-unwrapped properties; instantiated only via `UIStoryboard(name: "iPhone"/"iPad").instantiateViewController(withIdentifier: "LayoutOnScreenControlsViewController")`. No nib fallback, no programmatic init path. | `LayoutOnScreenControlsViewController.swift:38-189`; `MainFrameViewController.m:1298-1308`; `StreamFrameViewController.m:322-334`; `SettingsViewController.swift:251-260` |
| 7 | **Madeira has no storyboards, xibs, or .xcstrings at all**, and no SVGKit. Every non-code dependency below is net-new. | glob `app/**/*.storyboard|*.xib|*.lproj/*` → empty |
| 8 | Third-party: **SVGKit 3.x + SVGKitSwift via SPM** only (`libxml2.tbd` linkage), used solely through `GraphicUtils.makeSVGLayer`. No CocoaPods, no vendored libs, no custom fonts. | `project.pbxproj:2222-2251,633-634`; `GraphicUtils.swift:2-31` |
| 9 | Localization: **997 keys** in `Localization/Localizable.xcstrings` (656.5 KiB), plus storyboard string catalogs 251 (`mul.lproj/iPhone.xcstrings`) / 265 (`mul.lproj/iPad.xcstrings`) keys and `en.lproj/InfoPlist.strings` (45 B). | jq `(.strings|length)` |
| 10 | Assets are **runtime bundle resources**, not `UIImage(named:)`: 7 SVG files loaded by `Bundle.main.url(forResource:withExtension:"svg")` from the synchronized `SVGs/` folder; only 6 are referenced (`StickWheelAxis-0.15.svg` unused). Editor uses 2 PNG/SVG imagesets. | `GraphicUtils.swift:20-21`; `project.pbxproj:904` (SVGs in Resources) |

## 1. File table

### 1a. Roots

| path | KiB | LOC | lang | verdict | provides / reason |
|---|---|---|---|---|---|
| `Input/OnScreenWidgetView.swift` | 227.5 | 5035 | Swift | **keep** | `OnScreenWidgetView`, `WidgetTypeEnum`, `OnScreenWidgetLayoutUpdateDelegate`, `OnScreenFunctionalWidgetDelegate`, `static mapping` registry, all widget kinds |
| `Input/OnScreenControls.h` | 5.0 | 138 | ObjC | **keep** | façade decl: `pressDownControllerButton:`, `releaseControllerButton:`, `update{Left,Right}Trigger:`, `send{Left,Right}StickTouchPadEvent::`, `clear{Left,Right}StickTouchPadFlag`, `+shared`, `+layerVibrationStyleDic`, draw/level API |
| `Input/OnScreenControls.m` | 94.6 | 2097 | ObjC | **keep, trim** | legacy CALayer pad + 9 forwarders to `ControllerSupport`; the `drawButtons:`/`showLegacyWidgetsWith:` legacy path can be dropped with the Legacy widget type |
| `Input/CustomOSC/OSCProfile.h` | 4.6 | 98 | ObjC | **keep** | archive schema (all per-profile globals incl. gyro/pencil blocks) |
| `Input/CustomOSC/OSCProfile.m` | 16.5 | 262 | ObjC | **keep** | `NSCoding/NSSecureCoding/NSMutableCopying` impl |
| `Input/CustomOSC/OnScreenButtonState.h` | 5.2 | 119 | ObjC | **keep** | per-widget descriptor + `OnScreenWidgetType`, `WidgetSizeReference`, `MouseButtonAction`, `ButtonMode`, `RevealMode` |
| `Input/CustomOSC/OnScreenButtonState.m` | 9.6 | 145 | ObjC | **keep** | archive impl |
| `Input/CustomOSC/OSCProfilesManager.swift` | 23.8 | 593 | Swift | **keep** | CRUD, `sharedManager:`, `getSelectedProfile`, `getEncodedProfiles`, `importEncodedProfiles`, `importDefaultTemplates`, `persistProfileOrder`, `unarchiveButtonStateEncoded`, normalize/denormalize |
| `Input/CustomOSC/LayoutOnScreenControls.h` | 1.8 | 42 | ObjC | **keep** | container subclass decl, `layoutChanges`, `updateGuidelinesForOnScreenWidget:` |
| `Input/CustomOSC/LayoutOnScreenControls.m` | 18.3 | 366 | ObjC | **keep** | guideline snapping + legacy-layer drag/undo store |
| `Input/CommandManager.swift` | 29.2 | 802 | Swift | **keep** (stub one type) | DSL parser, VK/mouse tables, `touchPadCmds` & friends, combo sequencer, `RemoteCommand`, `savedCommands` persistence |
| `Input/MotionHandler.swift` | 27.4 | 688 | Swift | **keep** | gyro/accel → stick or mouse; mixing with vpad |
| `Input/CursorInertia.swift` | 4.6 | 124 | Swift | **drop** | unreachable from subset (finding 3) |
| `Input/InertialScroller.swift` | 1.2 | 36 | Swift | **keep** | `InertialScroller(decelerationRate:displayLinkRate:)`, `.vector`, `.timer`, `.handler` |
| `Input/SafeTimer.swift` | 4.6 | 147 | Swift | **keep** | `@objc(SafeTimer)` interval timer used for auto-tap/auto-dock |
| `Input/HapticContext.h` | 0.7 | 25 | ObjC | **drop** | finding 2 |
| `Input/HapticContext.m` | 13.0 | 341 | ObjC | **drop** | finding 2 |
| `Input/AbstractGamepadOverlayWidgetView.swift` | 20.7 | 545 | Swift | **keep** | `AbstractGamepadOverlayView`, `AbstractGamepadOverlayCloseButtonDelegate`; consumer is only `StreamFrameViewController.m:2571-2573` → needs a **host** owner |
| `Input/RadialMenuOverlayView.swift` | 7.0 | 203 | Swift | **keep\*** | consumed only by `ControllerNavigator.swift` (207-700); requires `RadialMenuView` (661) + `ThemeManager` + `ControllerNavigationElement` → 3.6 kLOC of collateral, unrelated to widgets |
| `ViewControllers/CustomOSCViewControl/LayoutOnScreenControlsViewController.swift` | 128.9 | 2657 | Swift | **keep** | the editor; 90 outlets, 8 IBActions, bulk edit/undo/trash |
| `…/LayoutOnScreenControlsViewController.m` | 107.1 | 2083 | ObjC | **drop** | not in target (finding 1); still calls nonexistent `[GenericUtils getAtrributedPlaceHolderWithText:]` |
| `…/LayoutOnScreenControlsViewController.h` | 0.5 | 18 | ObjC | **drop** | not in project either; ObjC consumers get the type from `VoidLink-Swift.h` |
| `ViewControllers/CustomOSCViewControl/Table/ProfileSelectorViewController.swift` | 67.9 | 1660 | Swift | **keep** | profile list + select/dup/delete/rename/import/export/reorder **and** `ProfileFileContainer`/`ProfilePayloadCompression` (lines 130-205) |
| `…/WidgetPanelStackView.h` | 0.2 | 14 | ObjC | **keep** | `WidgetPanelStackView` (storyboard class for the panel) |
| `…/WidgetPanelStackView.m` | 0.7 | 26 | ObjC | **keep** | `pointInside:` phone-specific passthrough |
| `…/ToolBarContainerView.h` | 0.4 | 18 | ObjC | **keep** | toolbar container class |
| `…/ToolBarContainerView.m` | 0.6 | 24 | ObjC | **keep** | `pointInside:` tab passthrough |
| `VoidLinkPreview/WidgetPickerViewController.swift` | 10.2 | 249 | Swift | **keep** | `WidgetPickerViewController`, `WidgetPickerViewControllerDelegate` (declared **here**, not in `VoidLink/`) |
| `PresetConfigs/widgetTemplates.bin` | 71.6 | – | binary | **keep** | iPad default profiles (NSKeyedArchiver) |
| `PresetConfigs/widgetTemplatesIPhone.bin` | 67.2 | – | binary | **keep** | iPhone defaults; selected at `OSCProfilesManager.swift:244` |

### 1b. Transitive references

| path | KiB | LOC | lang | verdict | provides to subset |
|---|---|---|---|---|---|
| `VoidLinkPreview/WidgetPickerView.swift` | 180.8 | 4324 | Swift | **keep** | `WidgetPickerView`, `WidgetPickerTab`, `WidgetPickerPresentationState`, `WidgetPoolItem`, `FunctionalButtonOption`, `PoolActionChip`… |
| `VoidLinkPreview/VirtualKeyboardView.swift` | 79.6 | 1710 | Swift | **keep** | `VirtualKeyboardView`, `VirtualKeyboardMode`, `Key`, `Row`, `KeyboardWidgetOption` |
| `VoidLinkPreview/AbstractGamepadView.swift` | 98.5 | 2546 | Swift | **keep** | gamepad tab UI |
| `VoidLinkPreview/RadialMenuView.swift` | 24.7 | 661 | Swift | keep\* | `RadialMenuView`, `RadialMenuStyle`, `RadialMenuSector`, `RadialMenuSelectionState` |
| `Utility/PublicUtils.swift` | 29.3 | 747 | Swift | **stub→grow** | see §2.1 (≈24 members used) |
| `Utility/GenericUtils.swift` | 40.0 | 1037 | Swift | **stub** | see §2.2 (13 members) |
| `Utility/PublicExtensions.swift` | 8.2 | 259 | Swift | **keep** | `String.localized`, `.localizedProfileName`, `UISegmentedControl.previousSelectedSegmentIndex` |
| `Utility/GraphicUtils.swift` | 4.2 | 140 | Swift | **keep** | `makeSVGLayer`, `changeColor`, `_makeSVGLayer` |
| `AlertControllerUtil.swift` | 8.1 | 219 | Swift | **keep** | countdown alert; small and self-contained |
| `ThemeManager.swift` | 14.0 | 461 | Swift | **stub** | `userInterfaceStyle()`, `ThemeDidChangeNotification`, `appPrimaryColor` only |
| `Input/ControllerUtil.swift` | 78.0 | 2009 | Swift | **stub** | see §2.3 (6 members) |
| `Input/ControllerNavigator.swift` | 120.9 | 2712 | Swift | keep\* / **stub** | `ControllerNavigationElement`, `radialMenuButtonPosition`, `setUINavigationDelegate`, `restorePreviousUINavigationDelegate(ifCurrentDelegateIs:)` |
| `Input/UITouchUtil.swift` | 2.0 | 51 | Swift | **keep** | `touches(in:from:)`, `vector(of:in:)`, `midPointVector(between:and:in:)` |
| `Input/ControllerSupport.h` | 3.6 | 89 | ObjC | **stub** (façade) | 9 selectors, §5 |
| `Input/ControllerSupport.m` | 100.6 | 2384 | ObjC | **drop** | replaced by façade over `GamepadInput` |
| `Input/StreamView.h` | 4.0 | 114 | ObjC | **stub shim** | `+sharedInstance`, `touchDisabled`, `singleTouchDisabled` |
| `Input/StreamView.m` | 97.6 | — | ObjC | **drop** | out of scope |
| `Input/CustomTapGestureRecognizer.h` | 1.1 | 28 | ObjC | **keep** | class test at `OnScreenControls.m:1529-1532` |
| `Input/CustomTapGestureRecognizer.m` | 5.0 | 105 | ObjC | **keep** | needed for that `isKindOfClass:` |
| `Input/VoidController.h` | 3.1 | 80 | ObjC | **stub** | `VoidController *` handle type only (`OnScreenControls.m:81,230`) |
| `Input/PencilHandler.swift` | 36.5 | 964 | Swift | **stub** | `PencilHandler.shared`, `.disableTilt` (`OnScreenWidgetView.swift:1363-1364`) |
| `Input/PressureCurve.swift` | 36.3 | 777 | Swift | **stub** | reached only via `presentPressureCurveVC()` delegate (`:66,3399`) |
| `Input/MicHandler.swift` | 73.2 | 1639 | Swift | **stub** | `MicHandler.requestPermission` (`:3279`) |
| `Input/InputAccessoryBar.swift` | 47.2 | 1223 | Swift | **drop** | no reference inside subset (only a peer picker client) |
| `Database/DataManager.swift` | 6.9 | 247 | Swift | **stub** | `DataManager().getSettings()?.redirectMic`, `retrieveSettings()?.unlockDisplayOrientation` |
| `Database/TemporarySettings.swift` | 11.6 | — | Swift | **drop** | no direct reference; only supplies `CursorInertiaDefaultsKey` for dropped `CursorInertia` |
| `Stream/StreamConfiguration.h` | 1.4 | 51 | ObjC | **stub** | `swapABXYButtons`, `buttonVisualFeedback` only |
| `Localization/LocalizationHelper.h` | 0.5 | ~20 | ObjC | **keep** | `+localizedStringForKey:,\...` (varargs) |
| `Localization/LocalizationHelper.m` | 0.5 | 22 | ObjC | **keep** | `NSLocalizedStringFromTable(key,@"Localizable")` |
| `Localization/LocalizationHelperExtension.swift` | 0.4 | 10 | Swift | **keep** | `localizedString(forKey:_:)` variadic Swift form |
| `Localization/Localizable.xcstrings` | 656.5 | – | JSON | **keep** | 997 keys |
| `Base.lproj/iPhone.storyboard` | 169.9 | – | XML | **keep scene** | editor scene `:149` (toolbar `:154`, panel `:304`) |
| `Base.lproj/iPad.storyboard` | 171.9 | – | XML | **keep scene** | editor scene `:184` |
| `mul.lproj/iPhone.xcstrings` / `iPad.xcstrings` | 175.1 / 187.0 | – | JSON | optional | 251 / 265 storyboard-object keys |
| `SVGs/{StickWheel,StickWheelSmall,StickWheelAxis,StickWheelAxis-0.75,sprintSign,walkSign}.svg` | 2.0/2.0/0.9/0.9/0.9/0.9 | – | SVG | **keep** | `OnScreenWidgetView.swift:1606,1612,1621,2107,2114,2124` |
| `SVGs/StickWheelAxis-0.15.svg` | 0.9 | – | SVG | **drop** | never referenced |
| `Images.xcassets/ChevronCompactDown|Up.imageset` | – | – | PNG | **keep** | `LayoutOnScreenControlsViewController.swift:1728,1738` |
| `ViewControllers/ToolboxViewController.swift` | 67.0 | — | Swift | **stub 1 type** | `CommandManager.viewController: ToolboxViewController?` (`CommandManager.swift:488,658`) |

## 2. Symbols needed from stub/dropped files

### 2.1 `PublicUtils` (used at these call sites)
`isIPhone` (OnScreenWidgetView 624,625,1268,1430,1448,1456,3858; LayoutVC.swift 219,651; ProfileSelector 46,50,56,61,70,72,76,78,80,337,488,500,510,517,546-549,553,562-565,576,653,657,662,669,671,675,678,682,1169; AbstractGamepad 169; RadialMenuOverlay 21; WidgetPickerView 952,953,3789; VirtualKeyboardView 1541,1557) · `isTVOS` (OnScreenWidgetView 629,4122; MotionHandler 68; OSCProfilesManager 234; ProfileSelector 371,1172; RadialMenuOverlay 21) · `isIPad` (OnScreenWidgetView 3398) · `isSimulator` (OnScreenWidgetView 562; LayoutVC.swift 411) · `screen(for:)` (ProfileSelector 353; LayoutVC.swift 224; OnScreenWidgetView 4672) · `screenForView:` (LayoutVC.m 78,79 — dead file) · `currentScreen` (OnScreenWidgetView 459,4636,4654; WidgetPickerView 1330) · `isFoldableRAMCached` (OnScreenWidgetView 1268; OSCProfilesManager 244; MotionHandler 296) · `isFoldableIPhone`/`hingeStatus`/`isLandscape()` (WidgetPickerView 440,441,445,952,953,1043,1059) · `isRunningOnMacAsiPadApp` (MotionHandler 68,296) · `viewIsLandscape` (ProfileSelector 348) · `topViewController()` (ProfileSelector 440) · `runOnMain` (ProfileSelector 728,1289,1315,1330) · `openUrl:` (LayoutVC.swift 1103) · `isGUIWidgetPickerAvailable` (CommandManager 584) · `iOS26Available` (OnScreenWidgetView 4102) · `quitSymbol`/`disconnectSymbol` (ControllerNavigator 655-656 — only with radial menu).

### 2.2 `GenericUtils`
`handleStickWheelTip` (OnScreenWidgetView 2493) · `handleVelocityBasedTouchpadTip` (2506) · `handleMagnifierTip` (2543) · `handleGyroButtonTip` (3207) · `canActivatePushToTalk(in:redirectMic:)` (3277) · `autoPopSoftKeyboard` (LayoutVC.swift 1549,1579,2030,2033) · `getAtrributedPlaceHolder(text:)` (LayoutVC.swift 1418) · `handleLayoutToolTip` (313) · `isFirstTappingFolderInLayoutTool` (1120) · `handleGamingLayoutFolderTip` (1125) · `handleWidgetPanelTip` (2576) · `handleButtonModeTip` (2319) · `isFirstLaunchGamepadOverlayFeature`/`gamepadOverlayFeatureTipTitle`/`…Message` (AbstractGamepad 406,411,412) · `pencilProPurchaseProcessedWithImportingWidgetTemplates` (OSCProfilesManager 346).

### 2.3 `ControllerUtil`
`gamepadArrivalReported` (OnScreenWidgetView 2249,2265,2339,3211,3214,4586,4593,4617; LayoutVC.swift 872,1648; MotionHandler 541) · `compensated(offsetVector:minOffset:circulate:)` (OnScreenWidgetView 2243,2259; MotionHandler 521,533) · `circulated(offsetVector:)` (MotionHandler 546,554) · `activeStreamingGCControllers` (OnScreenWidgetView 4102; MotionHandler 226) · `primaryGCController` (ProfileSelector 476).

### 2.4 `StreamFrameViewController` shim (host-owned)
`sharedInstance()` (OnScreenWidgetView 1352,1357,3369,3375) · `touchDisabled` (1353,3370-3371) · `singleTouchDisabled` (1358,3376-3377). Also implement `OnScreenFunctionalWidgetDelegate` (`OnScreenWidgetView.swift:53-79`): 22 methods (`expandSettingsView`, `disconnectRemoteSession`, `disconnectAndQuitApp`, `enterPip`, `bringUpToolboxMenu`, `openWidgetLayoutTool`, `openWidgetProfileTable(pickProfile:)`, `bringUpSoftKeyboard`, `alterAbsTouchDragWith(mouseButton:)`, `enable/disablePencilHover`, `handleDisableSingleTouchButtonUp`, `replaceBrush/Eraser`, `presentPressureCurveVC`, `handleTouchDisableButtonUp`, `toggleGamepadOverlay(overlayEnabled:)`, `magnifierMoveStreamView(translation:)`, `…(translation:pinchDelta:)`, `setMagnifierViewportInteractionEnabled`, `resetMagnifierStreamView(animated:)`, `restoreMagnifierStreamView(offset:scale:)`, `startStreamViewInteractionTimer`).

### 2.5 `DataManager` / `StreamConfiguration` seams
`DataManager().getSettings()?.redirectMic` (OnScreenWidgetView 3276) · `DataManager().retrieveSettings()?.unlockDisplayOrientation` (LayoutVC.swift 214-216). `streamConfig.swapABXYButtons` / `.buttonVisualFeedback` (OnScreenControls.m 233-234). `ControllerSupport` façade selectors: `setButtonFlag:flags:`, `clearButtonFlag:flags:`, `updateLeftTrigger:left:`, `updateRightTrigger:right:`, `updateLeftStick:x:y:`, `updateRightStick:x:y:`, `updateFinished:`, `updateTimerStateForOsc`, `getOscController` (`OnScreenControls.m:172-230`).

## 3. ObjC ↔ Swift seams

Bridging header `VoidLink-Bridging-Header.h` (25 lines) — subset-relevant imports: `ControllerSupport.h`, `OnScreenControls.h`, `OnScreenButtonState.h`, `OSCProfile.h`, `LayoutOnScreenControls.h`, `ToolBarContainerView.h`, `LocalizationHelper.h`, plus `NativeTouchPointer.h`, `StreamFrameViewController.h`, `TemporaryHost/TemporaryApp`, `Settings+CoreDataClass.h`, `<Limelight.h>`, `<moonlight_haptics/authored_haptics.h>`.

| ObjC file | imports `VoidLink-Swift.h` | Swift symbols it uses |
|---|---|---|
| `OnScreenControls.m` | `:23` | `OSCProfilesManager` (`:223`); Swift statics via `+shared`/`layerVibrationStyleDic` callers |
| `LayoutOnScreenControls.m` | `:14` | `OnScreenWidgetView` class + statics `isHorizontallyAligned/alignedY/isVerticallyAligned/alignedX` (`:141-186,214,233`), `isFolder/bulkMoveEnabled/sequenceSet/sequence/folded` |
| `OSCProfile.m` | `:13` | none observed (import only) |
| `OnScreenButtonState.m` | `:13` | none observed (import only) |
| `HapticContext.m` | `:16` | none observed |
| `LayoutOnScreenControlsViewController.m` | `:16` | `OSCProfilesManager`, `OnScreenWidgetView`, `WidgetPickerViewController`, `AlertControllerUtil`, `GenericUtils`, `PublicUtils` — **dead file, ignore** |

`@objc` Swift API consumed from ObjC in live files: `OnScreenWidgetView` (`widgetWithCmdString:buttonLabel:shape:profile:` `:14-17`; `+setWithWidget:for:`; `+clearMappings`; `+mapping`; `+trackPointEnabled`; `+editMode`; `+isTweakingHighlight`; `+unfoldedExclusiveFolderSequence`), `OSCProfilesManager` (`@objc(sharedManager:)` `:28`), `AlertControllerUtil` (`showAlertIn:…` + 6 statics `:80-85`), `GenericUtils` (`autoPopSoftKeyboard` `:951`), `PublicUtils` (`@objc(screenForView:)` `:479`), `ThemeManager` (`@objcMembers` `:12`), `ControllerNavigationElement`.

ObjC→Swift name collision risk: storyboard `customClass="LayoutOnScreenControlsViewController" customModule="VoidLink"` resolves to the **Swift** class (ObjC impl not linked), so the module name in the storyboard must be updated to Madeira's module.

## 4. Non-code needs

| Need | Scope | Can it be avoided? |
|---|---|---|
| `iPhone.storyboard` + `iPad.storyboard` editor scene | 90 outlets, 8 IBActions (`closeTapped:`, `undoTapped:`, `trashCanTapped:`, `saveTapped:`, `loadTapped:`, `addTapped:`, `editTapped:`, `importFromOtherButtonTapped:`, `clearFolderButtonTapped:`, `bulkEditButtonTapped:`), custom classes `ToolBarContainerView` (`:154`), `WidgetPanelStackView` (`:304`), SF-symbol images `arrow.left.square.fill`, `arrow.uturn.backward` | **No** — outlets are `!` and code dereferences them in `viewDidLoad`/`viewDidAppear`. Options: (a) copy both storyboards wholesale, (b) extract the one scene into `OSCEditor.storyboard` (recommended), (c) hand-build the ~120-view hierarchy in code (large rewrite, not in scope). |
| Segues into editor | none — presented modally by identifier (`MainFrameViewController.m:1298-1308`) | trivially re-targeted |
| `SVGKit` + `SVGKitSwift` SPM (≥3.0.0) + `libxml2.tbd` | `project.pbxproj:2222-2251,633-634` | Only consumer is `GraphicUtils`; either add the package or reimplement `makeSVGLayer` with `CAShapeLayer`/PDF assets (~140 LOC). |
| SVG resources (6) | bundle-root resources, name lookup | must ship; names are load-bearing |
| `Localizable.xcstrings` (997 keys) + `LocalizationHelper` | all UI strings; subset uses `localizedString(forKey:)` and `"…".localized` | A passthrough `LocalizationHelper` returning the key compiles everything but ships English-only key text (`"=disableTilt"`, `"Slide threshold: %.2f"`). |
| Storyboard string catalogs (251/265) | only if storyboards are copied | optional |
| Fonts | none used (`Roboto/` in `Font/` is unrelated) | n/a |
| Nibs | none | n/a |

## 5. Sink / app-model references inside the subset (grouped, `file:line`)

| symbol | call sites |
|---|---|
| `LiSendKeyboardEvent` | `OnScreenWidgetView.swift:1843,1844,1852,1853,1861,1862,1870,1871,1879,1880,1888,1889,1897,1898,1906,1907,2342,2395,3578,3579,3580,3581,3584,3585,3586,3587`; `CommandManager.swift:747,762,774,789,797` |
| `LiSendMouseButtonEvent` | `OnScreenWidgetView.swift:1926,1932,1945,1947,1954,1956,2349,2398,3151,3153,3155,3159,3178,3180,3182`; `CommandManager.swift:750,765,776` |
| `LiSendMouseMoveEvent` | `OnScreenWidgetView.swift:1967,2954,2963`; `MotionHandler.swift:506` |
| `LiSendMouseMoveAsMousePositionEvent` | `OnScreenWidgetView.swift:2975` |
| `LiSendMousePositionEvent` | `OnScreenWidgetView.swift:2980,2991,3142,3199` |
| `LiSendScrollEvent` | `OnScreenWidgetView.swift:2347,3067` |
| `LiSendHighResScrollEvent` | `OnScreenWidgetView.swift:3052,3087` |
| `LiSendHighResHScrollEvent` | `OnScreenWidgetView.swift:3055,3084` |
| `LiSendControllerTouchEvent` | `OnScreenWidgetView.swift:2736,2747,2757` |
| `LiGet*` | **none in subset** (`LiGetHostFeatureFlags` only at `StreamView.m:1235`) |
| `Limelight.h` constants used | `KEY_ACTION_DOWN/UP`, `BUTTON_ACTION_PRESS/RELEASE`, `BUTTON_LEFT/MIDDLE/RIGHT`, `LI_TOUCH_EVENT_{DOWN,MOVE,UP}`, `A_FLAG…RIGHT_FLAG`, `LS_CLK_FLAG/RS_CLK_FLAG`, `PLAY_FLAG`, `BACK_FLAG`, `STICK_CLICK_RATE` (`OnScreenControls.m`, `OnScreenWidgetView.swift`) |
| `ControllerSupport` | `OnScreenControls.h:13,21`; `OnScreenControls.m:80,172-230,1176,1193,1270,1520,1658` (9 selectors, §2.5); `LayoutOnScreenControls.h:29-30`; `LayoutOnScreenControls.m:34-35` |
| `StreamView` | **no direct reference** in any subset file (only the delegate protocol it implements) |
| `StreamConfiguration` | `OnScreenControls.h:21` (`@class`), `OnScreenControls.m:218,232-234`; `LayoutOnScreenControls.h:29-30`, `.m:34` |
| `DataManager` | `OnScreenWidgetView.swift:3276`; `LayoutOnScreenControlsViewController.swift:214-216` |
| `TemporarySettings` | **none** |
| CoreData | none directly; only through `DataManager` |
| `TemporaryHost` / `TemporaryApp` | import-only in `OnScreenControls.m:25-26` (no use); dead in `LayoutVC.m:19-20`, `HapticContext.m:14-15` |

## 6. Slicing check against PLAN.md P3

### Dependency edges (consumer → provider)

| consumer | needs |
|---|---|
| W-A Model | `PublicUtils.isIPhone/isFoldableRAMCached/isTVOS`, `GenericUtils.pencilProPurchase…`, **`ProfileFileContainer` (in a W-D2 file)**, `widgetTemplates*.bin` |
| W-A2 Commands | **W-B** (`LiSend*`), `PublicUtils.isGUIWidgetPickerAvailable`, `ToolboxViewController` (app type) |
| W-B Sink | `ControllerSupport.h`, `StreamConfiguration.h`, `VoidController.h`, `Liminal.h` flags |
| W-C1 Widget | W-A (`OSCProfile`), W-A2 (`CommandManager` statics + `shared`), W-C2 (`SafeTimer`, `InertialScroller`, `MotionHandler`, `OnScreenControls`), **W-B** (`LiSend*`), `ControllerUtil`, `UITouchUtil`, `PublicUtils`, `GenericUtils`, `LocalizationHelper`, `GraphicUtils`+SVG, `DataManager`, `PencilHandler`, `MicHandler`, `StreamFrameViewController` (flags) |
| W-C2 Runtime | W-C1 (`OnScreenWidgetView` statics + `isKindOfClass:`), W-A (`OSCProfile`), **W-B** (`ControllerSupport`), `StreamConfiguration`, `VoidController`, `CustomTapGestureRecognizer` |
| W-D1 Editor | W-A (`OSCProfilesManager`, `OnScreenButtonState`), **W-A2** (`CommandManager.shared.extractCmdStrings/extractAutoReleaseButtonStrings` + 5 mapping tables, `:1273-1279`), W-C1 (`mapping`, `editMode`, `set(widget:for:)`, `clearMappings`, `isTweakingHighlight`, `trackPointEnabled`, `unfoldedExclusiveFolderSequence`, `setPostExclusiveUnfoldeds`), W-C2 (`LayoutOnScreenControls`, `OnScreenControls.shared()` `:1649,2415,2429`), **W-D2** (`ProfileSelectorViewController`, `WidgetPickerViewController`), storyboard, `DataManager`, `ControllerUtil`, `ControllerNavigator`, `AlertControllerUtil`, `GenericUtils`, `PublicUtils`, `LocalizationHelper` |
| W-D2 Pickers | W-A (`OSCProfilesManager`, `OSCProfile`), `ThemeManager`, `ControllerUtil`, `ControllerNavigator`, `PublicUtils`, `LocalizationHelper`, `WidgetPickerView`→`AbstractGamepadView`+`VirtualKeyboardView`. **No `CommandManager` reference** (`WidgetPickerView` keeps its own cmd catalogs). |

### Files that would need two owners
1. **`ProfileSelectorViewController.swift`** — W-D2 UI + `ProfileFileContainer`/`ProfilePayloadCompression` used by W-A (`OSCProfilesManager.swift:250`). *Amend:* move those two types (≈75 LOC, `:130-205`) into `Model/ProfileFileContainer.swift`; then W-A compiles standalone and W-D2 only consumes.
2. **`OnScreenWidgetView.swift`** — W-C1, but also the host contract (`OnScreenFunctionalWidgetDelegate`) that P4 implements and the registry W-C2/W-D1 mutate. Keep C1 as sole owner; the host conforms.
3. **`ControllerUtil.swift`** — consumed by W-C1, W-C2, W-D1, W-D2. Nobody in the P3 table owns it.
4. **`AbstractGamepadOverlayWidgetView.swift` + `RadialMenuOverlayView.swift`** — consumers are `StreamFrameViewController` and `ControllerNavigator` respectively, i.e. **outside every slice**. As written, W-C2 would own files with no W-C2 consumer, and `RadialMenuOverlayView` silently pulls `ControllerNavigator` (2 712) + `RadialMenuView` (661).
5. **`PresetConfigs/*.bin` + `Localizable.xcstrings` + `SVGs/`** — resources shared by W-A/W-C1/W-D1/W-D2; `project.pbxproj` + bridging header are declared shared, but these aren't mentioned in PLAN.md.

### Recommended split (evidence-driven deltas to P3)
| change | why |
|---|---|
| Add **W-0 Support** (owner: one worker, lands before the wave): `PublicUtils` subset, `GenericUtils` subset, `LocalizationHelper`(+ext), `Localizable.xcstrings`, `AlertControllerUtil`, `ThemeManager` stub, `ControllerUtil` stub, `UITouchUtil`, `GraphicUtils`+SVGs, `SafeTimer`. | 5 slices consume 6 of these; otherwise the first parallel wave triplicates stubs and merges conflict in the same files. |
| Move `ProfileFileContainer` to **Model** | breaks the Model→Pickers compile cycle (finding 5). |
| Move `AbstractGamepadOverlay*` + `RadialMenuOverlayView` (with `ControllerNavigator` + `RadialMenuView`) to a **W-E Extras** slice, or drop from wave 1 | no P3 slice consumes them; they are host/controller-navigation features (3.6 kLOC collateral). |
| Split **W-D2** into D2a `WidgetPickerViewController`+`WidgetPickerView`+`AbstractGamepadView`+`VirtualKeyboardView` (8.7 kLOC) and D2b `ProfileSelectorViewController` (1 660 LOC, export/import + `Compression`) | D2 as planned is the largest single slice by far and has zero overlap with D2b's file; also 2 of its 4 files live in a *different target group* (`VoidLinkPreview/`), so P2 must register them explicitly. |
| W-B must additionally own the shims `StreamConfiguration.h`, `VoidController.h`, `StreamFrameViewController` flags | all three are sink-adjacent types whose only consumer is the sink chain. |
| P2 must add: `SVGKit` package, `SVGs/` folder reference, 2 `.bin` resources, 1 storyboard (both idioms), `Localizable.xcstrings` | none exist in Madeira today (finding 7). |

Not verified: whether Madeira's `GamepadInput` can supply `swapABXYButtons`/`buttonVisualFeedback` equivalents, and whether `winios_pointer` supports the relative-move/scroll semantics `MOUSEPAD`/`WHEEL` need — that is R2's scope, not observable from sources read here. `[INFERENCE]` `RadialMenuOverlayView`'s only purpose in the subset is the `ControllerNavigator` radial menu, so dropping it does not regress any touch widget.