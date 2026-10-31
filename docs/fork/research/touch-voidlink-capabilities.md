# VoidLink touch profiles: the full expressive range

Research note, 2026-10-31. Source read: `third_party/voidlink/VoidLink/` (the vendored, ported subset; `/tmp/voidlink` no longer exists) plus the port at `app/Madeira/VLTouch/`. Everything about the DSL, widget kinds, properties, gyro and profile storage below is from that source with `file:line`; anything marked **[INFERENCE]** is my reading of behaviour, not a literal statement in code. Templates were decoded from the shipped binaries (§5).

Legend for citations: `CM` = `Input/CommandManager.swift`, `OSWV` = `Input/OnScreenWidgetView.swift`, `MH` = `Input/MotionHandler.swift`, `PM` = `Input/CustomOSC/OSCProfilesManager.swift`, `OBS` = `Input/CustomOSC/OnScreenButtonState.h` / `.m`, `PROF` = `Input/CustomOSC/OSCProfile.h` / `.m` — all under `third_party/voidlink/VoidLink/`. Port paths are absolute-relative to `app/Madeira/VLTouch/`.

## 1. What a profile can express

A profile is `OSCProfile` (per-profile globals + an array of encoded `OnScreenButtonState`) (`PROF.h:37-95`). A widget is **one `cmdString`** plus 47 scalar properties. The `cmdString` is the whole behaviour language; the properties tune it. There is no scripting, no conditional logic, no per-game binding inside the profile — one profile is a flat HUD.

### 1.1 cmdString grammar

| Form | Meaning | Evidence |
|---|---|---|
| `TOKEN` | one command (button) or one pad | `CM:581-660` |
| `TOKEN-TOKEN[-...]` | multi-action widget: first token decides the kind, every token fires on press, all release on lift | `OSWV:481-505`, `2354-2386`, `2403-2450` |
| `...-NNMS` | a bare `NNMS` token is a **pause, not an action**; when it is the last token it becomes the unified delay for every step (`LB-RB-10MS`), inline it delays just that step (`OSCX-100MS-OSCY`) | `OSWV:2311-2325`, `2355-2370`, `2403-2450` |
| `TOKEN.NNms` | per-token self-release: press now, release after NN ms (`handleButtonStringDown` schedules its own up) | `OSWV:2327-2336` — parsed but **not producible** from the current picker/validator (`CM:604-608` rejects `.`), so hand-built archives only **[INFERENCE]** |
| `A+B+C` / `A+` | **legacy** keyboard/mouse macro, fired on **release**, auto-released in reverse after 0.1 s steps | `OSWV:2060-2075`, `CM:526-580`, `738-784` |
| `NULL` | no-op key token (0xFF): label-only widget or combo filler | `CM:214`, port shim drops it `Sink/VLLiShim.m:156-168` |

Rules that matter when designing:

- Validation is a regex over the union of the five token tables, `^(?:keys)(?:-(?:keys))*(?:-\d+MS)?$` (`CM:604-608`). Any token outside the tables makes the whole string invalid → the editor shows "Invalid Input" (`Editor/LayoutOnScreenControlsViewController.swift:1278-1310`).
- A `+` string is **never** a pad; `-` and `+` do not mix (`OSWV:481-512`, `2064`).
- The **first** token decides the widget kind: a leading touchpad token ⇒ touchpad widget; otherwise ⇒ button widget (`OSWV:487-489`). A pad token anywhere else still becomes `touchPadString` and still drives the pad (`OSWV:491-494`, `2862-2864`) — this ordering rule is what makes `OSCA-MOUSEPAD` (button + pad) different from `MOUSEPAD-OSCA` (pad + double-tap A).
- Bare `LSPAD/LSVPAD/LSWHEEL` default their combo to `OSCL3`, the right-hand ones to `OSCR3`, `DS4TOUCH` to `DS4TCHBTN` — but only when the string is *exactly* that token, so prefixing a combo replaces the default (`OSWV:498-505`).
- Pads fire their combo on a **quick double tap** (≤0.2 s), not on press (`OSWV:2465-2467`, `2523-2547`, `2570-2590`).
- `-` combos are pressed in order on finger-down and released in reverse on lift; each OSC flag goes through `pressDownControllerButton:`/`releaseControllerButton:` (`OSWV:2278-2306`). Triggers: `OSCL2/OSCR2` set 0xFF/0x00 (`OSWV:2283-2296`).

### 1.2 Command tables (complete)

| Table | Count | Contents | Line |
|---|---|---|---|
| `oscButtonMappings` | 37 | `OSCA/OSCB/OSCX/OSCY`, `OSCL1\|L1\|LB`, `OSCR1\|R1\|RB`, `OSCL3\|L3\|LS`, `OSCR3\|R3\|RS`, `OSCSTART\|OSCPLAY`, `OSCSELECT\|OSCBACK`, `OSCUP/DOWN/LEFT/RIGHT`, `OSCHOME`→SPECIAL, `DS4TCHBTN`, `PADDLE1..4`, `MISC`, `OSCL2\|L2\|LT`, `OSCR2\|R2\|RT` (trigger sentinels, value 0) | `CM:97-135` |
| `keyboardButtonMappings` | 252 (155 Windows + 97 `*MAC`) | Windows VK: `A-Z`, `0-9`, `F1-F12`, `CTRL/SHIFT/ALT`(+R), `ESC SPACE ENTER TAB BACKSPACE INSERT DEL HOME END PG_UP/DOWN`, arrows (`UP_ARROW\|UPARR`…), `NUMPAD0-9 MULTIPLY ADD SUBTRACT DECIMAL DIVIDE`, OEM punctuation (`SEMI_COLON COMMA MINUS PERIOD FORWARD_SLASH GRAVE_ACCENT OPEN/CLOSE_BRACKET BACKSLASH SINGLE_QUOTE EQUALS`), media/volume, `WIN/LWIN/RWIN APPS`, `CAPS_LOCK NUMLCK SCRLCK PAUSE PR_SCR`, `NULL`=0xFF. The 97 `*MAC` tokens are macOS keycodes — irrelevant to a Wine target | `CM:212-483` |
| `mouseButtonMappings` | 12 | `M_LEFT\|MLEFT`, `M_MIDDLE\|MMIDDLE`, `M_RIGHT\|MRIGHT`, `M_X1\|MX1`, `M_X2\|MX2`, `WHEELUP`(0xFF), `WHEELDOWN`(-0xFF) → 3-notch scroll | `CM:81-95`, `OSWV:2343-2349` |
| `touchPadCmds` | 22 | see §2 | `CM:148` |
| `functionalButtonCmds` | 24 | `SETTINGS TOOLBOX DISCONNECT QUITAPP PIP WIDGETTOOL ABSGAMEPAD WIDGETPROFILES PROFILES PICKPROFILE PICKPRFL SOFTKEYBOARD ABSTCHDRAG FOLDER LABELEDFOLDER PRESSURECURVE PENCILHOVER BRUSH ERASER NOSINGLETOUCH DISABLETILT DISABLETOUCH GAMEPADOVERLAY PUSHTOTALK` | `CM:159-184` |
| `motionControlButtonCmds` | 4 | `GYRO GYROPAUSE ACCEL MOTION` | `CM:201` |
| helper sets | — | `oscRectangleButtonCmds`, `mousePadWithButtonActions`(MOUSEPAD/ABSMOUSE/ABSMOUSEPAD), `mousePads`(+TRACKBALL), `directionPads`, `stickTouchPads`, `displacementBasedStickPads`, `stickWheels`, `velocityBasedTouchPads`, `inertialTouchPads`, `verticalTouchPads`, `singleDimensionActiveTouchpads`, `freeModeFunctionalButtons`(PUSHTOTALK), `functionalTouchPadCmds`(MAGNIFIER), `pencilProButtonCmds`, `shortcutAllowedFunctionalButtonMappings`(BRUSH/ERASER/FOLDER/LABELEDFOLDER) | `CM:137-210` |

Functional buttons are tap-actions dispatched on finger-up to the host delegate (`OSWV:3300-3410`); in the Madeira port they land on `VLTouchHost` (TOUCH-PORT.md host contract). Only `FOLDER` is a hold-to-reveal widget: `slideAndHold` + `FOLDER` unfolds on press and folds on release (`OSWV:3262-3268`, `3337-3339`).

## 2. Widget kinds (22 pad tokens)

All behaviour below is in `handleTouchPadMoveEvent` (`OSWV:2944-3101`), `touchesBegan` (`OSWV:2491-2560`) and `touchesEnded` (`OSWV:3460-3600`). "Sink" = what the host receives.

| Token | Behaviour | Sink | Gameplay use |
|---|---|---|---|
| `LSVPAD`/`RSVPAD` | velocity stick: per-frame **delta** × `VectorStickFactor`(1.5167) × sensitivity → stick (velocityBased) (`OSWV:298`, `3013-3030`) | left/right stick | twin-stick shooters, camera swipes with optional inertia (`CM:156`) |
| `LSPAD`/`RSPAD` | displacement stick: **offset from centre** (or from touch point if anchored) × sensitivity, radial `circulated()` clamp (`OSWV:2995-3012`, `2922-2926`) | left/right stick | classic fixed/floating analog stick; supports `minStickOffset` |
| `LSWHEEL`/`RSWHEEL` | displacement stick with a rotating wheel graphic; small wheel below `walkModeThreshold` (visual only) (`OSWV:1641-1677`) | left/right stick | "steering wheel" for racing; 2×2.6 default size, sensitivity 0.42 (`OSWV:593-608`) |
| `LTPAD`/`RTPAD` | vertical offset × 4.5 → analog trigger 0-255 (`OSWV:3031-3042`, `2268-2276`) | LT/RT | throttle/brake, ADS pressure, variable-rate fire |
| `DPAD` | 8-way sectors at ±67.5° from centre, no dead zone when sensitivity 0 (`OSWV:1809-1912`) | `UP/DOWN/LEFT/RIGHT_FLAG` | menu/inventory, retro pad; diagonals work |
| `WASDPAD` | same sectors, emits `W/A/S/D` VKs; plus sprint/walk keys (§4.2) | keyboard | PC games on keyboard; **the** movement widget for Wine |
| `ARROWPAD` | same, emits arrow VKs | keyboard | menus, emulators |
| `MOUSEPAD` | relative mouse: delta ×1.7 × sensitivity, slide gate, 2-finger scroll (hovering only) (`OSWV:2950-2957`, `3077-3090`) | mouse move / scroll | look/aim; with `mouseButtonAction` becomes fire+aim (§4.1) |
| `TRACKBALL` | relative mouse with momentum + `decelerationRate` (`OSWV:2958-2969`, `1962-1980`) | mouse move | flick-to-turn camera with coast |
| `ABSMOUSE` | relative move re-based to absolute cursor, re-centres on edge hit (`OSWV:2970-2988`) | abs mouse | games that capture/clamp the cursor |
| `ABSMOUSEPAD` | absolute position of the finger, plus button action with 5 ms delay (`OSWV:2989-2992`, `OSWV:713`) | abs mouse | direct-point cursor, RTS/point-and-click |
| `WHEEL`/`MOUSEWHEEL` | 2-axis high-res scroll, delta ×7.5 (`OSWV:3047-3058`) | H/V scroll | zoom, weapon wheel, map zoom |
| `DISCRETEWHEEL`/`DSWHEEL` | tick scroll (1 notch per `tickCycle/\|sens\|` frames, ±3) (`OSWV:3059-3070`) | scroll | weapon switching, hotbar |
| `DS4TOUCH` | forwards touches as controller touchpad pointers (`OSWV:2736-2763`) | `LiSendControllerTouchEvent` — **no-op in port** | DualSense touchpad games |
| `MAGNIFIER` | pans/zooms the stream view itself; double-tap resets (`OSWV:3102-3136`, `2548-2552`) | host view transform | reading small UI text in a 1424×656 stream |
| `DUMMYPAD` | no handler (no case in `OSWV:2949-3070`): a touch-blocking placeholder **[INFERENCE]** | none | dead zone where a thumb rests |

Buttons can carry a pad token too (kind = button, pad still driven): `OSWV:487-494` + `2862-2864`.

## 3. Per-widget properties (`OnScreenButtonState`)

Defaults are the decoder's fallbacks (`OBS.m:84-142`); ranges are the editor's slider bounds (`OSWV:249-267`). Persisted key names differ from property names (`slideMode` = `buttonMode`, `buttonType` = `widgetType`) — `OBS.m:33-82`.

| Property | Type / range | Effect | Gameplay use |
|---|---|---|---|
| `name` | string | the cmdString (widget identity) | — |
| `alias` | string | on-screen label | short glyph labels (`=jump`, `💉`) |
| `position` | normalized CGPoint | centre, 0-1 of layout view (`PM:422-445`) | resolution independence |
| `sequence`, `parentSequence`, `sequenceSet` | int16 / set | folder tree: parent id, children ids (`OSWV:4340-4390`) | nested radial folders |
| `folded`, `revealMode` | bool, 0=coexist/1=exclusive | folder open state; exclusive closes sibling exclusive folders (`OSWV:4370-4385`) | one drawer open at a time |
| `buttonMode` | 0 `slideToToggle`, 1 `slideAndHold`, 2 `regular`, 3 `tapToToggle`, 4 `movable` (`OBS.h:98-104`) | touch semantics: slide-in/slide-out capture, hold-while-touching, press-release, tap latches, drag-to-move (`OSWV:2607-2621`, `2809-2858`, `3632-3648`) | slide from a fire button onto a second action; latch ADS; movable widget |
| `mouseButtonAction` | 0 `hovering`, 1 `left`, 2 `middle`, 3 `right`, 4 `noClick` (`OBS.h:90-96`) | pad press/lift drives a mouse button; `hovering` = tap-click + drag-look + 2-finger scroll + right-click on 2-finger tap; `noClick` = pad only, double-tap fires combo (`OSWV:3137-3204`, `3478-3486`) | fire+aim, ADS+aim, look-only pad |
| `slideThreshold` | px, 0-20 (default 6) | movement before a pad emits anything (`OSWV:2904-2912`) | kills jitter on look pads |
| `sensitivityFactorX/Y` | 0-16 (mouse pads), -4..4 (single-axis) (`OSWV:650-672`) | per-axis gain | separate horizontal/vertical aim gain |
| `decelerationRateX/Y` | 0-1 (default 0.5) | inertia on lift for `inertialTouchPads`; active when >0.50001 (`OSWV:3456-3457`, `751-756`) | coasting camera, momentum trackball |
| `touchPointAnchored` | bool | floating stick: centre = where the finger landed, else widget centre (`OSWV:2922-2926`, `2530`) | thumb never misses the stick |
| `stickIndicatorOffset` | px (default 95/120) | where the thumb/anchor graphic is drawn above the touch (`OSWV:4820-4834`) | keep the visual out from under the thumb |
| `minStickOffset` | 0..32766 | radial dead-zone compensation: rescales output so magnitude ≥ minOffset (`ControllerUtil.swift:1688-1702`) | remove fine control near centre, snap to 8 directions |
| `walkModeThreshold` | 0..32766 (default 0.2×max) | stick-wheel graphic switches small/large; **no key is sent** (`OSWV:1641-1656`) | wheel visual feedback |
| `walkKeyThreshold`, `walkKeyActionType` | 0-1 (0.08), 0 hold/1 toggle | WASDPAD/ARROWPAD inner zone emits `comboButtonStrings[1]` (`OSWV:1786-1807`) | walk toggle / walk modifier |
| `sprintKeyThreshold`, `sprintKeyActionType` | 0-1 (0.6), 0 hold/1 toggle | outer zone emits `comboButtonStrings[0]` (`OSWV:1761-1785`) | auto-sprint at full deflection |
| `autoTapInterval`, `autoTapRepeats` | ms (0/≤49 = off), count (0 = endless) | timer taps the button down/up (25 ms pulse); repeats then stops (`OSWV:730-749`, `3748-3800`) | hold-to-autofire, semi-auto cap |
| `yawFactor`, `pitchFactor`, `rollFactor` | -1..1 | per-GYRO-button multiplier on gyro axes (`OSWV:668-677`, `MH:183-197`) | precision mode button, ADS-halved gyro |
| `widthFactor`, `heightFactor` | ≤10 = ×baseline (round 60/70, square 70×65, largeSquare 170×150 pt), >10 = per-10000 of long/short side (`OSWV:1154-1206`) | size | thumb-reach sizing |
| `sizeReference` | 0 longSide, 1 shortSide (`OBS.h:84-87`) | which screen edge the factors reference | orientation-stable size |
| `componentSizeFactor` | multiplier | stick knob / wheel diameter (`OSWV:1583-1600`) | knob size for feel |
| `widgetShape` | `default`/`round`/`square`/`largeSquare` | shape + auto corner radius (`OSWV:1207-1287`) | circles for buttons, rects for pads |
| `backgroundAlpha`, `labelAlpha`, `borderAlpha`, `highlightAlpha`, `borderWidth`, `highlightSizeFactor` | 0-1 / pt | visual only (`OSWV:813-930`, `2197-2234`) | keep the HUD invisible over gameplay |
| `vibrationStyle` | UIImpactFeedback style; only 0-3 vibrate, ≥4 is silent (`OSWV:764-766`) | haptics on press, on sprint/walk threshold crossing, on double-tap (`OSWV:758-786`, `1783`, `4795-4800`) | confirm a threshold without looking |
| `autoDockTimer`, `dockedAlpha` | seconds, 0-1 | after idle, widget glides to the nearest edge and fades to `dockedAlpha`; first touch restores it (`OSWV:3861-3865`, `3945-3980`, `4053-4128`) | clear the view when not shooting |
| `animatesTransition` | bool | folder/magnifier animation | polish |
| `bulkMoveEnabled` | bool | folder children move together in the editor (`OSWV:4210-4445`) | authoring |
| `oscLayerSizeFactor` | float | legacy `OnScreenControls` layers only (`PM:447-475`) | n/a for custom widgets |
| `isHidden` | bool | visibility | A/B variants |

## 4. Answers

### 4.1 One button that fires **and** aims

Three distinct expressions, all from the same code paths:

1. **`MOUSEPAD` with `mouseButtonAction = leftButtonDown` (or `rightButtonDown` for ADS).** Finger-down presses LMB/RMB immediately (`OSWV:3174-3204`), every drag frame emits a relative mouse move (`OSWV:2950-2957`), lift releases (`OSWV:3137-3172`). One thumb: hold = fire, slide = aim, lift = stop. This is the "combined fire and aim" that COD Mobile reaches by floating its fire button over the look area ([GameFAQs HUD thread](https://gamefaqs.gamespot.com/boards/271403-call-of-duty-mobile/78121239), [Activision control guide](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls)). Cost: with `leftButtonDown` the 2-finger scroll and 2-finger right-click are disabled (they are `hovering`-only, `OSWV:3077-3090`, `3483-3485`).
2. **`OSCA-MOUSEPAD` (button kind, pad token second).** The button holds A while the same touch streams mouse moves: gamepad fire + mouse aim, no mouse-button state to leak (`OSWV:487-494`, `2007-2020`, `2862-2864`). Order matters — `MOUSEPAD-OSCA` is a pad whose A only fires on double tap.
3. **`MOUSEPAD-OSCA` + `noClick`.** Aim-only pad; quick double tap fires A once (`OSWV:3199-3203`). Best when the fire input should be a gamepad button for in-game aim-assist, at the cost of one extra tap.

The bundled FPS template does **none** of these: `=kbmfps` keeps `MOUSEPAD` at `noClick` and puts a separate 1291-unit round `M_LEFT` button at (0.075, 0.335) — a two-thumb layout (§5).

### 4.2 Run stick that sprints past a threshold

`WASDPAD-OSCL1-OSCL3` (or `-SHIFT-CTRL`, as the bundled templates do):

- `comboButtonStrings[0]` = sprint key, `[1]` = walk key (`OSWV:1770-1805`).
- Distance is measured from the pad centre (or the anchor point) in points; the compare is `dist > sprintKeyThreshold * 150` and `dist < walkKeyThreshold * 150` (`keyboardDpadThresholdRef = 300`, halved — `OSWV:376`, `1762-1763`).
- `hold` holds the key while inside the band; `toggle` taps it for 25 ms on entry (`OSWV:1768-1782`). Defaults: sprint 0.6, walk 0.08, both `hold` (`OSWV:377-380`).
- Haptics fire on each threshold crossing (`OSWV:1783`), and the widget draws sprint/walk signs plus threshold rings in the editor (`OSWV:2139-2180`).
- Movement keys are plain `W/A/S/D` with ±67.5° sectors and released all at once on lift (`OSWV:1809-1912`, `3576-3585`).
- Only `WASDPAD`/`ARROWPAD` get this; `DPAD` does not (`OSWV:690-691`).

This mirrors the standard virtual-joystick "outer ring" design (threshold past which a second action fires): Microsoft's Touch Adaptation Kit example switches walk→sprint at 0.75 ([MS GDK joystick](https://learn.microsoft.com/en-us/gaming/gdk/_content/gc/reference/system/touchadaptationkit/controls/game-streaming-touch-joystick)); Steam Input calls it an outer-ring binding ([SteamInputWiki](https://github.com/SteamInputWiki/SteamInputWiki/blob/main/chapter-2/02b06_joystick_move.md)); Warframe's mobile port does the same with thumb distance ([Warframe guide](https://support.warframe.com/hc/en-us/articles/32633646081421-Warframe-Mobile-Touch-Control-Guide)).

### 4.3 Gyro: every option, and what the port can do

Profile-level fields (`PROF.h:44-62`, encoded `PROF.m:37-55`, defaults `PROF.m:108-126`), applied in `MotionHandler.shared(profile:)` (`MH:65-80`):

| Field | Meaning | Port status |
|---|---|---|
| `useBuiltinGyro` | iPhone IMU vs. physical controller motion (`MH:68`, `215-249`) | works on device; forced off when running as a Mac/iPad app (`MH:68`) |
| `mapGyroTo` | 0 `mapGyroToMouse`, 1 `mapGyroToControllerStick`, 2 `driftCorrection` (`PROF.h:19-23`) | 0 and 1 work; **`driftCorrection` is an enum value with no implementation anywhere** (only `PROF.h:22`) |
| `swapYawAndRoll` | controller-gyro axis swap (`MH:487-492`) | only used for controller gyro |
| `yawPitchToRightStick` / `rollToLeftStick` | which axes go to which stick (`MH:511-537`) | works (stick sink) |
| `synthesizePhysicalStick` | adds a physical stick vector into the mix (`MH:48-57`) | effectively unused — the port has no physical pad path |
| `gyroSensitivityYaw/Pitch/Roll` | axis gain; mouse path ×30, stick path ×10 then `max*in/8` (`MH:504-506`, `513-517`, `596-598`) | works |
| `accelSensitivityX/Y/Z` | accelerometer gain (`PROF.h:53-55`) | **unused**: `handleAccelerometerData` is empty (`MH:376-378`) |
| `gyroToStickMinOffset` | radial dead-zone compensation for gyro→stick (`MH:521-533`) | works |
| `physicalLeft/RightStickMinOffset` | same for a physical pad | unused in port |
| `controllerGyroSwitchMode/Hold/Toggle`, `reverseGyroHoldButton` | bind a controller button to toggle gyro (`PROF.h:59-62`) | decoded/stored only; no consumer in this source |
| `pointerVelocityModeDivider`, `touchPointerVelocityFactor`, `touchMode`, `streamViewScale`, `normalizedStreamViewOffset`, `dualSenseTransient` | stream-view/touch-mode settings, Moonlight-specific (`PROF.h:63-68`) | port keeps touchMode but has no touch modes (dropped) |

Widget-level:

- **`GYRO`** on a *button* starts gyro on press and stops it on lift; `init` **forces `buttonMode = tapToToggle`** on any widget carrying a motion token (`OSWV:568-570`), so out of the box it is a latch. The editor's mode selector can change it back to `regular`/`slideAndHold` for true hold-to-gyro (`OSWV:661`, `3632-3648`). Two GYRO buttons share one starter; releasing a non-starter re-starts with the starter's factors (`OSWV:3225-3244`).
- **`GYROPAUSE`** stops gyro on press and restarts on lift — the "ratchet" gesture (`OSWV:3212-3215`, `3246-3250`). Ratcheting is the standard way to recentre a gyro aim ([Steam gyro setup](https://steamgamer.com/articles/controller/steam-controller-gyro-grip-sense-setup-guide/), [rewasd](https://www.rewasd.com/blog/post/how-to-use-gyro-controls-on-pc)).
- **`ACCEL`** and **`MOTION`** exist as tokens but both handlers are empty (`OSWV:3216-3219`, `3250-3253`); the port's `LiSendControllerMotionEvent` is a no-op anyway (TOUCH-PORT.md sink table).
- **`yawFactor`/`pitchFactor`/`rollFactor`** exist only on `GYRO` buttons, and only for the axes the profile actually maps (`OSWV:668-677`).
- A GYRO token on a **touchpad** widget is inert: `handleMotionControlButtonDown` is reached only from `handleButtonDown`, which touchpads never call (`OSWV:2007-2020`, `2607-2621`). The shipped `GYRO-RSVPAD` in `=vGamepad1`/`=kbmfps` therefore only decorates the pad (label, yaw/pitch slider availability) and — because its combo replaces the default — **loses the pad's double-tap R3** (`OSWV:498-505`). **[INFERENCE]** from those call paths; flagged as a template bug rather than a feature.

Port reality: gyro→mouse lands on `LiSendMouseMoveEvent` → `winios_pointer(dx,dy,VL_MOUSE_MOVE,0)` (`Sink/VLLiShim.m:199-202`); gyro→stick lands on `OnScreenControls.sendRightStickTouchPadEvent` → `ControllerSupport` → one `GamepadSample` (TOUCH-PORT.md sink table). `MotionHandler` is ported verbatim and attached per widget in `Host/VLTouchLayer.swift:197-219`. The port has **no UI** for any profile-level gyro field (`mapGyroTo` is referenced only in `Model/OSCProfile.*` and `Widgets/MotionHandler.swift`), so a profile's gyro mode is whatever the imported archive says. iPhone bundle: `Default`/`=vGamepad1/2/3`/`=null` ship `mapGyroTo = 1` (stick) with yaw/pitch sensitivity 5.0; `=legacyWidgets` `= 1` at 1.0; `=kbmfps` `= 0` (mouse) at 3.05; `=buttonModeDemo` `= 0` at 1.0. To get gyro→mouse in Madeira today, start from `=kbmfps` or edit the archive. Orientation is handled per-interface-orientation with persisted bias (`MH:415-465`, `600-687`); rate is 120 Hz (`MH:163-171`).

### 4.4 How profiles are stored, created, imported

- Store: `UserDefaults.standard["OSCProfiles"]` = one `NSKeyedArchiver` blob of an array of per-profile blobs (`PM:16`, `75-101`). Secure coding whitelists `NSString, NSMutableData, NSMutableArray, OSCProfile, OnScreenButtonState` (`PM:52-65`). Widget states are archived individually (`PM:447-529`, `OBS.m:33-82`). Positions are normalized on save and denormalized on load (`PM:422-445`).
- First run / template refresh: sentinel key `widgetProfileUpdated-20261016`; if absent, `importDefaultTemplates()` unpacks the bundled file and imports (`PM:19`, `334-352`). File selection: `widgetTemplatesIPhone.bin` on iPhone (non-foldable), else `widgetTemplates.bin` (`PM:243-246`).
- Container format: `VLPR` magic, version 1, compression byte (2 = LZ4), little-endian original length, then an Apple-Compression LZ4 block that decompresses to an `NSKeyedArchiver` plist (`Model/ProfileFileContainer.swift:30-72`).
- Import merge: profile named `Default` at index 0 is preserved/replaced specially, collisions get `" - Restored"`, a single imported profile becomes selected (`PM:178-241`).
- Create: **duplicate the selected profile** (`PM:398-420`); index 0 (`Default`) cannot be overwritten or deleted (`PM:103-123`, `384-396`). UI: `Pickers/ProfileSelectorViewController.swift:691-746` (duplicate), `767-848` (delete/rename), `862-928` (export), `933+` (import), `945-948` (restore bundled templates).
- Per-game binding: `LibraryEntry.vlTouchProfile` stores the profile *name*; the session switches to it on engage and restores the previous selection on exit (`app/Madeira/Library.swift:205`, `1516`, `VLTouch/Host/VLTouchSwitch.swift:44-62`).
- Authoring a widget: GUI picker builds the cmdString by joining chosen tokens (`Pickers/WidgetPickerView.swift:3202-3267`) and offers only `GYRO`/`GYROPAUSE` as motion buttons (`:2363-2374`); the legacy text alert accepts **any** token string and validates it against the tables (`Editor/LayoutOnScreenControlsViewController.swift:1278-1310`, `1440-1500`, `1520-1560`) — that is the escape hatch for `ACCEL`, `MOTION`, `DS4TOUCH`, `M_*`, and hand-built combos. Property sliders for buttonMode, mouse action, thresholds, sensitivity, deceleration, anchor, min offset, auto-tap live in the editor (`:458-492` load, `:637-960` UI, `:929-954` thresholds).

## 5. Bundled templates (decoded)

Method (reproducible): Swift harness decompresses the `VLPR` payload with `compression_decode_buffer(..., COMPRESSION_LZ4)`, then Python `plistlib` walks `$objects`/`$top` twice (outer array → profile blob → `buttonStates` blobs) and maps the coder keys from `OBS.m`/`PROF.m`. Positions below are the stored normalized centres, 2 dp.

`widgetTemplatesIPhone.bin` — 8 profiles, 206+23+22+33+22+2+21+23 = 352 widgets. Folder integrity is uneven: `=kbmfps` and folder `16` of `=vGamepad1/2` resolve; every other `parentSequence` in the bundle points at a folder widget that is absent from the archive, so those widgets load flat (`OnScreenWidgetView.mapping[parentSequence]` is nil). Both surviving folders ship `folded=true`, i.e. their contents start hidden behind one tap.

| Profile | Widgets | Character |
|---|---|---|
| `Default` | 206 | **flat showcase, not a playable HUD**: 206 custom widgets, zero folder widgets, nothing folded or hidden, and every `parentSequence` points at a sequence that is absent from the profile (422, 16, 446, 317, 445, 190, 157, 147, 154, 261, 23, 267, 237, 523), so no folder logic can hide anything — all 206 render at once. Contains three `MOUSEPAD`s (sens 2.0 / 2.56 / 12.03), `WHEEL`, `LSWHEEL`, `RSVPAD` (6.55), `GYRO` (tapToToggle), `WASDPAD-SHIFT-CTRL`, `LB-RSPAD`, `LB-LSPAD`, `Q-MOUSEPAD`, `E-MOUSEPAD`, `M_LEFT=shoot`, `M_RIGHT=ads`, `MAGNIFIER`, `DUMMYPAD`, and the whole A-Z/0-9/F1-F12 key grid. Read it as a widget catalogue |
| `=vGamepad1` | 23 | gamepad + gyro pad: `DPAD` (0.18,0.23), `LSWHEEL` (0.16,0.73), `RSVPAD` (0.74,0.68, sens 6.55), `LT/RT/LB/RB`, `OSCA/B/X/Y`, `OSCHOME/BACK/PLAY`, `WIN`, `LB-RSPAD` (0.16,0.57), `RB-LSPAD` (0.76,0.57), `GYRO-RSVPAD` (0.74,0.19), `PUSHTOTALK`; folder `16 =widgets` (slideAndHold) holding `PICKPRFL`+`WIDGETTOOL`; `FOLDER 468 =bumperRadial` (regular mode; its `sequenceSet` lists the two bumper pads, whose own `parentSequence` says the missing 23) |
| `=vGamepad2` | 22 | same shell with `LSPAD`/`RSPAD` displacement sticks (sens 0.6, `noClick`) instead of the wheel/velocity pair; no GYRO widget at all |
| `=vGamepad3` | 22 | older iPad-ish layout, no folder widgets: `OSCX` (995 wide), `OSCA/B/X/Y`, `OSCR1/2`, `OSCL2`, `OSCSTART/SELECT`, `DPAD`, `LSWHEEL`, `RSVPAD` (sens 6.03, decelX 0.91, minOffset 1508), `LB-RSPAD`, `ESC`, `WIN`; the settings buttons (`SETTINGS/TOOLBOX/WIDGETTOOL/PICKPRFL/SOFTKEYBOARD/DISABLETOUCH`) point at missing folder 21, everything else at 17 |
| `=kbmfps` | 33 | keyboard+mouse FPS: see below |
| `=legacyWidgets` | 21 | 19 `OnScreenButtonState` with `buttonType=0` for the legacy pad layers (`aButton`, `leftStick`, …) + `PICKPRFL`, `WIDGETTOOL` (missing parent 1) |
| `=null` | 2 | only `PICKPRFL` (0.75,0.12) and `WIDGETTOOL` (0.83,0.24), missing parent 21 |
| `=buttonModeDemo` | 23 | teaching profile, flat: 7 `NULL` label widgets plus `CTRL`/`SHIFT`/`ESC` in `slideAndHold` (mode 1), `LB` in `tapToToggle` (3) with autoTap 101 ms, `CTRL-SHIFT-ESC-20MS`, `LB-RB-10MS`, auto-tap demo `Q`/`W`/`E` (49/50/56/98 ms), `WIDGETTOOL`/`PICKPRFL` movable (4) |

`=kbmfps` in full (cmd, label, mode, mba, shape, pos, notable props) — this is the closest shipped starting point for a Wine FPS:

| cmd | label | mode | mba | shape | pos | props |
|---|---|---|---|---|---|---|
| `WASDPAD-SHIFT-CTRL` | Wasdpad-Shift-Ctrl | 0 | 0 | largeSquare | 0.12,0.79 | sens 0, sprint 0.52 |
| `MOUSEPAD` | Mousepad | 0 | 4 | largeSquare | 0.81,0.75 | sens 12.03 |
| `Q-MOUSEPAD` | =left | 2 | 0 | round | 0.84,0.55 | sens 3.01 |
| `E-MOUSEPAD` | =right | 2 | 0 | round | 0.91,0.55 | sens 3.01 |
| `WHEEL` | Wheel | 0 | 0 | largeSquare | 0.88,0.38 | sens 1.0/0.98 |
| `M_LEFT` | =shoot | 2 | 0 | round | 0.07,0.33 | sens 0.27, w/h 1291 |
| `M_RIGHT` | =ads | 2 | 0 | round | 0.96,0.30 | w/h 1033 |
| `GYRO` | =gyro | 3 | 0 | round | 0.79,0.09 | tapToToggle, yaw/pitch 1.0 |
| `SPACE` | =jump | 0 | 0 | round | 0.82,0.36 | — |
| `Z` | =prone | 0 | 0 | round | 0.18,0.25 | — |
| `C` | =squat | 0 | 0 | round | 0.18,0.47 | — |
| `F` | =pickup | 2 | 0 | round | 0.78,0.48 | — |
| `T` | =interact | 0 | 0 | round | 0.74,0.57 | autoTap 49 |
| `R` | =reload | 0 | 0 | round | 0.69,0.88 | — |
| `U` | =flash | 0 | 0 | round | 0.26,0.54 | autoTap 49, dock 5 s |
| `V` | =skill1 | 2 | 0 | round | 0.70,0.66 | — |
| `G` | =skill2 | 2 | 0 | round | 0.64,0.66 | — |
| `X` | =ult | 0 | 0 | round | 0.74,0.93 | — |
| `I` | =inspect | 2 | 0 | round | 0.97,0.47 | autoTap 49, dock 5 s |
| `M` | =map | 2 | 0 | square | 0.11,0.11 | — |
| `TAB` | 🎒 | 2 | 0 | round | 0.32,0.93 | — |
| `Y` | =laser | 2 | 0 | round | 0.97,0.58 | — |
| `1` | 1 | 0 | 0 | square | 0.61,0.88 | vib 2 |
| `2` | 2 | 0 | 0 | square | 0.55,0.79 | vib 2 |
| `3` | 🗡 | 0 | 0 | square | 0.64,0.79 | vib 2 |
| `6` | 💉 | 0 | 0 | round | 0.92,0.93 | — |
| `ESC` | ESC | 0 | 0 | square | 0.96,0.11 | — |
| `F3`/`F4` | F3/F4 | 0 | 0 | round | 0.32,0.10 / 0.38,0.10 | — |
| `PUSHTOTALK` | =pushToTalk | 3 | 4 | square | 0.88,0.11 | — |
| `FOLDER` | =widgets | 1 | 0 | square | 0.83,0.95 | folded |
| `WIDGETTOOL` | =widgetTool | 4 | 0 | square | 0.75,0.95 | in folder 16 |
| `PICKPRFL` | =pickProfile | 4 | 0 | square | 0.83,0.82 | in folder 16 |

`widgetTemplates.bin` (iPad / foldable) — 9 profiles: `Default` (225), `Pencil Pro` (27), `=vGamepad1` (23), `=vGamepad2` (22), `=kbmfps` (35, gyro 2.9), `=vGamepad3` (22, gyro 3.5), `=null` (2), `=legacyWidgets` (22), `=buttonModeDemo` (24). Same names, slightly different tuning.

## 6. Design pattern → exact widget

| Design pattern | cmdString | Kind | Key properties |
|---|---|---|---|
| Fire + aim, one thumb | `MOUSEPAD` | pad | `mouseButtonAction=1` (LMB), `sensitivityFactorX/Y≈8-12`, `slideThreshold≈4` |
| ADS + aim, one thumb | `MOUSEPAD` | pad | `mouseButtonAction=3` (RMB), lower sensitivity |
| Gamepad fire + mouse aim | `OSCA-MOUSEPAD` | button+pad | `buttonMode=2` (forced), `sensitivityFactorX/Y`, `vibrationStyle` for the shot |
| Aim pad, tap to fire | `MOUSEPAD-OSCA` | pad | `mouseButtonAction=4` (noClick); double tap fires `OSCA` and shows the indicator ring |
| Look pad + scroll | `MOUSEPAD` | pad | `mouseButtonAction=0` (hovering), tap = click, 2-finger = scroll |
| Run + auto-sprint | `WASDPAD-OSCL1-OSCL3` | pad | `sprintKeyThreshold≈0.55-0.7`, `sprintKeyActionType=0`, `walkKeyThreshold≈0.08`, `walkKeyActionType=1`, `vibrationStyle` |
| Run + walk + sprint on keys | `WASDPAD-SHIFT-CTRL` | pad | same two thresholds, `sensitivityFactorX/Y=0` (no dead zone) |
| Analog throttle | `RTPAD` | pad | `sensitivityFactorY≈1`, `sizeReference=shortSide` |
| Camera with coast | `TRACKBALL` | pad | `decelerationRateX/Y≈0.85-0.95`, `sensitivityFactorX/Y` |
| Flick-turn camera | `RSVPAD` | pad | `decelerationRateX>0.5`, `sensitivityFactorX/Y≈3-6`, `minStickOffset` small |
| Gyro toggle that also fires | `GYRO-OSCA` (button) | button | `buttonMode=3` (forced by init; each tap fires `OSCA`), `yawFactor≈0.5`, `pitchFactor≈0.35`; profile `mapGyroTo=0` for mouse |
| Gyro hold-to-aim | `GYRO` alone | button | set `buttonMode=2` (regular) in the editor to override the forced toggle |
| Gyro ratchet (gyro always on) | `GYRO` latched + `GYROPAUSE` | buttons | `GYRO` `tapToToggle`; `GYROPAUSE` left at its default so a hold pauses gyro |
| Gyro fine-tune on ADS | second `GYRO` button | button | `yawFactor/pitchFactor≈0.3`, `tapToToggle` |
| Hold-to-autofire | `OSCA` or `M_LEFT` | button | `autoTapInterval=50-120`, `autoTapRepeats=0` |
| Burst / macro | `OSCX-OSCY-100MS-OSCB` | button | trailing `NNMS`; all release on lift |
| Keyboard macro on tap | `CTRL+SHIFT+ESC+` | button | legacy `+`, fires on release (`CM:738-784`) |
| Weapon switch | `DISCRETEWHEEL` | pad | `sensitivityFactorY≈1`, small `heightFactor` |
| Radial menu | `FOLDER` + children | button + folder | `buttonMode=1` (slideAndHold), `revealMode=1` on exclusive folders, children `parentSequence` |
| Thumb-rest dead zone | `DUMMYPAD` | pad | `backgroundAlpha=0.001`, `borderAlpha=0` |
| Clear HUD when idle | any | — | `autoDockTimer≈8-10`, `dockedAlpha=0.2` |
| Floating stick | `LSPAD`/`RSPAD` | pad | `touchPointAnchored=true`, `stickIndicatorOffset≈95`, `minStickOffset≈3000` |
| Text/UI legibility | `MAGNIFIER` | pad | `widthFactor/heightFactor≈5000`, `animatesTransition` |

## 7. Limits a profile designer must respect

1. No conditional logic, no per-game switching inside a profile; per-game choice is one name in `LibraryEntry.vlTouchProfile` (`Library.swift:205`).
2. One gyro mode per profile (`mapGyroTo` is profile-level, `PROF.h:46`) — you cannot have gyro→mouse for hip-fire and gyro→stick for vehicles in the same profile.
3. Per-widget gyro factors apply only to `GYRO` buttons, and only for mapped axes (`OSWV:668-677`).
4. `ACCEL` and `MOTION` have empty handlers in the source (`OSWV:3216-3219`, `MH:376-378`); `driftCorrection` has no implementation (`PROF.h:22`); the controller-gyro switch fields have no consumer; `PADDLE*`/`MISC`/`DS4TOUCH` have no sink lane in the Madeira port (TOUCH-PORT.md sink table), though `DS4TOUCH` works upstream.
5. Stick pads cannot carry arbitrary double-tap combos if you also want the L3/R3 default, and a GYRO token on a pad silently costs you that default (`OSWV:498-505`).
6. `walkModeThreshold` is cosmetic; sprint/walk *keys* come only from `walkKeyThreshold`/`sprintKeyThreshold` on WASDPAD/ARROWPAD.
7. `autoTapInterval < 50 ms` disables auto-tap entirely (`OSWV:87`, `1987`).

## Sources

- VoidLink (read): `third_party/voidlink/`, upstream https://github.com/The-Fried-Fish/VoidLink-previously-moonlight-zwm (blob root `fa42805`).
- Port: `app/Madeira/VLTouch/`, `docs/fork/TOUCH-PORT.md`.
- Design references: [MS GDK touch joystick (walk→sprint threshold)](https://learn.microsoft.com/en-us/gaming/gdk/_content/gc/reference/system/touchadaptationkit/controls/game-streaming-touch-joystick) · [SteamInputWiki outer ring](https://github.com/SteamInputWiki/SteamInputWiki/blob/main/chapter-2/02b06_joystick_move.md) · [Warframe mobile touch guide](https://support.warframe.com/hc/en-us/articles/32633646081421-Warframe-Mobile-Touch-Control-Guide) · [COD Mobile controls (Activision)](https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls) · [COD Mobile floating fire button](https://gamefaqs.gamespot.com/boards/271403-call-of-duty-mobile/78121239) · [Gyro ratcheting / as-mouse](https://steamgamer.com/articles/controller/steam-controller-gyro-grip-sense-setup-guide/) · [Gyro sensitivity yaw/pitch](https://mygamepadtester.com/blogs/gyro-aiming-guide-1) · [Gyro aiming overview](https://www.rewasd.com/blog/post/how-to-use-gyro-controls-on-pc) · [Flick Stick](https://en.wikipedia.org/wiki/Flick_Stick).
