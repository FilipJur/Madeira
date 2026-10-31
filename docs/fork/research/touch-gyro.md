# Gyro aiming: best practice → VoidLink/Madeira settings

Scope: how to configure the VLTouch gyro path for Windows games streamed to an iPhone 15 Pro in
landscape. Sources: Jibb Smart's GyroWiki [G1-G5], JoyShockMapper README [JSM], Steam Input docs
[S1-S3], Nintendo first/secondary material on Splatoon 3 and BotW [N1-N3], mobile-shooter gyro
conventions [M1-M3], Core Motion docs [A1-A2], phone-posture study [E1]. VoidLink/Madeira claims
carry `file:line`; guesses are marked **[INFERENCE]**.

Reference computations used throughout (derived below, §5): for the mouse path
`C = 62.83 × S` counts per real degree, truncation floor `ω_min = 1.91 / S` °/s;
for the stick path full deflection at `45.84 / S` °/s.

## 1. What the literature actually agrees on

| # | Principle | Why | Source |
|---|---|---|---|
| P1 | **The gyro is a mouse**: convert calibrated angular *velocity* to proportional camera/cursor motion; no absolute orientation, no aim assist | Gyro gives directness a stick cannot; aim assist is unnecessary and harmful | [G2]; [S1] "absolute_mouse" |
| P2 | **Natural sensitivity scale**: 1.0 means a real 37.5° turn is a 37.5° turn in game; allow up to 10, players use 4-8 | Transferable skill, no arbitrary "100%" | [G2] |
| P3 | **Gyro as joystick is the fallback, not the goal**: inherits in-game deadzones/accel curves and cannot be converted back | Steam ships it only for parity with console builds | [S1]; [G1 §Local] |
| P4 | **Local space is right for handheld**: ignore gravity, use device axes | Withstands any posture (reclining, bed); world/player space degrade for handheld | [G1]; [G2] "not as good for handheld/mobile" |
| P5 | **Lifting the mouse = a gyro off / on input**: dedicated button, shared rarely-used button, or (3D) while the right stick is used | Otherwise you run out of comfortable rotation and must raise sensitivity | [G2] §Lifting; [JSM §1.7] `GYRO_ON`/`GYRO_OFF` |
| P6 | **Ratchet = momentary disable while repositioning**; toggle = leave gyro off while navigating | Both are used; JSM exposes both, "doesn't affect other mappings on that button" | [JSM §1.7]; [S2] |
| P7 | **Smoothing must be tiered, and never on large input**; below a small threshold only, ramp to zero smoothing at a second threshold, and honour total displacement | Plain rolling average adds latency and feels sloppy; tiered smoothing steadies tremor without costing responsiveness | [G2] §Smoothing; [G5] |
| P8 | **Never use a minimum-velocity cutoff**; use a "tightening" curve instead (scale input toward 0 below a small threshold, never hard-clip) | A cutoff makes slow/distant targets untrackable | [G2] §Minimum velocity |
| P9 | **Sensitivity acceleration** (MIN/MAX sens between two °/s thresholds, linear interpolation) is the preferred range/precision tool | Two slopes, real-world units, easy to explain | [G2] §Acceleration |
| P10 | Calibration: average stationary gyro over ~1-5 s; recalibrate per session; auto-calibration must be optional | Bias drifts with temperature/warm-up | [G2] §Calibration; [JSM §4] |
| P11 | **Flick stick** for turning: stick *angle* → absolute turn (0.1 s flick), stick *rotation* → immediate yaw delta, small-angle tiered smoothing | Controller becomes better than a mouse for big turns; gyro covers precision | [G4] |
| P12 | Lower in-game sensitivity and raise the hardware/gyro sensitivity to keep per-event resolution | Gives the game more counts to work with | [S3] Mouse▸Sensitivity |
| P13 | Games with mouse look: in-game mouse smoothing/accel off, raw input on; ignore OS pointer speed for raw-input titles | Otherwise calibration is meaningless | [JSM §5.1] |

### Consoles confirm the split
| Title | Behaviour | Take-away |
|---|---|---|
| Splatoon 3 | Motion is always on for aiming; **separate motion sensitivity for TV/tabletop vs handheld**; stick sensitivity set higher than motion; Nintendo advises lowering motion sensitivity if screen shake bothers you | Handheld needs its own tuning, and screen-shake comfort is a first-class setting [N1][N2] |
| BotW | Motion **only while a bow is drawn** (ZR); stick does coarse, gyro does fine; toggleable in options | "Gyro only while aiming" is the mainstream third-person pattern [N3] |
| CoD Mobile / PUBG Mobile | `Gyroscope: Always On` vs `On Scope/ADS only`; separate gyro sensitivities for hip-fire, red dot, and each scope | Mobile players ship the same two-mode design; per-zoom sensitivity is expected [M1][M2][M3] |

## 2. Phone-specific: which axis, roll vs yaw, drift, sickness

**Axis convention.** Core Motion reports `rotationRate` around the *device* axes (x across the short
edge, y along the long edge, z out of the screen); `CMDeviceMotion.rotationRate` already has bias
removed by Core Motion [A1][A2]. VoidLink treats it as rad/s (its ×30/×10 constants assume that).
In landscape the camera-yaw axis is **the device x axis** — the short, vertical axis in the plane of
the screen. VoidLink applies exactly this, with the sign chosen per interface orientation:

| Orientation | yaw source | pitch source | roll source | Code |
|---|---|---|---|---|
| landscapeLeft | `+x` | `-y` | `-z` | `Widgets/MotionHandler.swift:430-436` |
| landscapeRight | `-x` | `+y` | `-z` | `:437-443` |
| portrait | `-y` | `-x` | `-z` | `:444-450` |
| portraitUpsideDown | `+y` | `+x` | `-z` | `:451-457` |

So "pan left/right" = rotate about the axis that runs vertically *through the screen*, not about the
phone's long edge. Rotating about the long edge is pitch (aim up/down); the remaining axis (z, screen
normal) is roll = twisting the phone like a steering wheel.

**Roll vs yaw.** Roll-for-yaw is a real convention: Fortnite's Switch default shipped roll-as-yaw
because Joy-Cons in handheld face up, where local roll *is* the player's yaw [G2]. A phone held in
landscape is the same geometry, so expect some players to want it. VoidLink's `swapYawAndRoll`
(`OSCProfile.h:45`) is applied **only to controller gyro** (`MotionHandler.swift:487-492`); the
built-in phone path never swaps axes. Workaround today: pitch/yaw *factors* (below) can zero an axis
but cannot swap.

**Drift.** On iOS drift is mostly handled for you (Core Motion removes bias [A1]). VoidLink keeps an
*additional* manual bias (`MotionHandler.swift:311` comment; `gyroBiasX/Y/Z` `:139-148`) but
`calibrateGyroBias(duration:)` (`:600`) has **no caller anywhere** in VoidLink or the port — dead
API, and the non-view bias is memory-only. Practical consequence: no calibration UI is needed to be
"usable", but per-session recalibration is the documented best practice [G2][JSM §4] and is missing.

**Holding a phone: ergonomics and comfort.** Looking down at a phone costs neck load: ~12 kg at 15°
flexion, 27 kg at 60° [E1] — keep the phone near eye level and pitch with the wrists, elbows braced.
Because the *screen itself* moves, comfort tracks sensitivity: Nintendo's own advice for motion
discomfort is "lower the sensitivity" [N2]. Also cap yaw range: a phone has roughly ±30° of
comfortable yaw **[INFERENCE]**, so players compensate with high sensitivity, which is exactly what
P5/P6 (ratchet) exists to avoid.
**[INFERENCE]** Vection-type sickness is unlikely (the world stays fixed on screen); the realistic
failure modes are neck/wrist fatigue, screen shake at high sensitivity, and judder from 120 Hz input
delivered on the main thread (§5).

## 3. VoidLink's gyro model, mapped

| Setting | Location | Meaning |
|---|---|---|
| `useBuiltinGyro` | `OSCProfile.h:44`, applied `MotionHandler.swift:68` | phone IMU vs. controller IMU (forced on for iOS, off on tvOS/Mac-iPad) |
| `mapGyroTo` | `OSCProfile.h:19-23`, `:46` | `mapGyroToMouse` / `mapGyroToControllerStick` / `driftCorrection` (**unused enum case**) |
| `gyroSensitivityYaw/Pitch/Roll` | `OSCProfile.h:50-52`, defaults 1.0 `OSCProfile.m:114-116` | raw multipliers |
| `yawPitchToRightStick`, `rollToLeftStick` | `OSCProfile.h:47-48` | stick-output routing: aim to RS, lean-steer to LS |
| `gyroToStickMinOffset` | `OSCProfile.h:56`, default 0 | **anti-deadzone**: lifts any non-zero output to at least this magnitude (`ControllerUtil.swift:1688-1702`) |
| `synthesizePhysicalStick` | `OSCProfile.h:49` | mix a real controller's stick into the same axis |
| per-widget `yawFactor`/`pitchFactor`/`rollFactor` | `OnScreenWidgetView.swift:259-266`, `346-347` | per-gyro-button multipliers, −1…+1 (sign = invert) |
| `GYRO` / `GYROPAUSE` widgets | `CommandManager.swift:201`; start `MotionHandler.swift:183-207`; stop `:264-276` | `GYRO` starts, `GYROPAUSE` stops; both are *on-screen buttons* |

Math actually executed, per 120 Hz device-motion callback (`MotionHandler.swift:163-172`, `:503-521`):

```
mouse:  count = ω_rad × S × widgetFactor × 30     (fixed 30, no dt)      :504-506
stick:  out   = clamp(32766 × (ω_rad × S × factor × 10) / 8)             :513-521, :596-598
roll→LS: out  = −32766 × (Δroll_angle_since_start / π) × 3 × S_roll      :525-535
```

| Best practice | VoidLink setting | Status |
|---|---|---|
| P1 gyro as relative mouse | `mapGyroTo = .mapGyroToMouse` → `LiSendMouseMoveEvent` | **yes** (`:503-506`) |
| P1 gyro as stick | `.mapGyroToControllerStick` + `yawPitchToRightStick` | **yes** (`:512-522`) |
| P2 natural scale | — | **missing** (arbitrary S, ×30 constant, no cm/360 or REAL_WORLD_CALIBRATION) |
| P3 no deadzone on gyro | `gyroToStickMinOffset` default 0 | **yes, by default**; setting it >0 is the *opposite* of a deadzone |
| P4 local space | fixed device-axis mapping per orientation | **yes** — correct choice for a phone |
| P5 gyro off / on input | `GYRO` and `GYROPAUSE` widgets; `tapToToggle` vs `regular` mode | **partial** (see §4) |
| P6 ratchet vs toggle | default `.tapToToggle` (`OnScreenWidgetView.swift:570`) = latched toggle; `.regular` (restored `VLTouchLayer.swift:257`) = hold | **yes**, via button mode |
| P7 tiered smoothing | — | **missing** |
| P8 tightening (soft) | — | **missing**; no cutoff either (good default) |
| P9 acceleration | — | **missing** |
| P10 calibration | `calibrateGyroBias` exists, **no caller** | **missing UI** (iOS bias removal covers most of it) |
| P11 flick stick | — (MOUSEPAD is displacement-only; `pointerVelocityModeDivider`/`touchPointerVelocityFactor` are dead fields) | **missing** |
| P12 lower in-game sens, raise gyro sens | user-side; truncation floor punishes low S | **works**, documented in §5 |
| per-zoom sensitivity | one S per profile + per-widget factors; switching factors requires stop/start | **partial** |
| axis swap for phone gyro | `swapYawAndRoll` controller-only | **missing** for builtin |
| controller-gyro activation fields | `controllerGyroSwitchMode/Hold/Toggle`, `reverseGyroHoldButton` (`OSCProfile.h:59-62`) | **dead** (no consumer) |

## 4. Widget-level behaviour that limits "multi-function" gyro buttons

These are the mechanics a preset must respect (all verified in code):

| Behaviour | Detail |
|---|---|
| A widget that contains `GYRO` also contains its other commands | `motionControlButtonString` is parsed out of the combo (`OnScreenWidgetView.swift:495`), so `GYRO+MRIGHT` both starts gyro and presses RMB |
| Such a widget **defaults to latched toggle** | `if !self.motionControlButtonString.isEmpty { self.buttonMode = .tapToToggle }` (`:570`); saved `buttonMode` is restored later (`VLTouchLayer.swift:257`), so the editor can set **Regular** = hold-to-gyro |
| Toggle latches because touch-up is skipped | `.tapToToggle` never calls `handleFingerUpOrSlideout` on lift (`:3640-3643`); the *next* tap raises the up path (`:2610-2614`), which stops gyro (`:3227-3239`) |
| Only one gyro "starter" can be active | `startMotionControlByOnScreenButton` no-ops when `motionStarter != nil` (`MotionHandler.swift:189-196`) ⇒ two gyro buttons cannot OR together; releasing the starter stops gyro even if a second is held |
| Factors stick until gyro is stopped | widget factors are captured only on start (`:186-189`), so switching to a scoped button requires toggling gyro off first |
| Stopping clears the stick, not the mouse | `stopMotionUpdate` → `clearGyroInput` recenters RS/LS (`:264-276`, `:571-595`); mouse mode simply stops emitting |
| Stopping does **not** clear `motionStarter` | so `GYROPAUSE` up resumes with the previous factors (`OnScreenWidgetView.swift:3245-3250`) |

## 5. Output choice: mouse vs stick

| | Mouse (`mapGyroToMouse`) | Stick (`mapGyroToControllerStick`) |
|---|---|---|
| Reaches game as | `winios_pointer(dx, dy, 0x0001, 0)` → `INPUT_MOUSE` relative move; wineserver feeds `WM_INPUT` `x-cursor.x` **before** clip clamping, so raw-input mouse-look never stalls at a screen edge (`r2-madeira-sinks.md:21,63`) | `GamepadSample` right stick Int16 via `GamepadInput` (`OnScreenControls.m:170-178`) |
| Physics | linear, no deadzone, no curve — matches P1/P2 | inherits the game's stick deadzone/accel curve (P3) |
| Range | bounded by comfortable rotation; needs a ratchet | unbounded, but the *game* decides turn rate |
| Precision | count-level; **truncated** to whole counts per sample | 16-bit but the game quantises to its own curve |
| Use for | any game with mouse look (FPS, TPS with KB/M support, RTS, cursor games) | controller-only games, console-first ports, menus that reject mouse, games whose mouse-look is disabled in the port |
| Mixing | independent of on-screen sticks | sums with the RSPAD touch value then clamps (`MotionHandler.swift:514-521`) — "stick coarse + gyro fine" works |

**Truncation, and why S must not be too low.** `Int16(yaw)` drops the fraction every sample
(`:506`). One count per sample = 120 counts/s, so the *smallest* angular velocity that produces any
motion is `1.91 / S` °/s:

| S | 0.2 | 0.35 | 0.5 | 0.9 | 2.0 |
|---|---|---|---|---|---|
| slowest trackable rotation | 9.6 °/s | 5.5 °/s | 3.8 °/s | 2.1 °/s | 0.95 °/s |

Below that the aimer stutters — the P8 failure mode, caused by integer quantisation rather than a
cutoff. Fix (preferred, ~4 lines): keep a `Double` remainder and emit `Int`s only when ≥1 count
accumulates; Steam implements exactly this as "Minimum Movement Threshold … accumulate movement
until this threshold has been passed" [S3]. Meanwhile, obey P12: raise S, lower in-game mouse sens.

**Other mouse-path caveats.** No `dt` multiply — the ×30 assumes exactly 1/120 s, so a late callback
changes effective sensitivity **[INFERENCE]**; the callback runs on `.main`
(`MotionHandler.swift:352-359`), so UI work can jitter it. The Wine ring holds 256 events and drops
the *newest* when the guest is not pumping messages (`r2-madeira-sinks.md:105`), so a stalled frame
eats gyro input. `roll` is ignored entirely in mouse mode (`:503-506`).

## 6. Starting values, iPhone 15 Pro, landscape

Calibrate once with the 90° test (P2/[JSM §5.2]): pick a landmark, rotate the phone exactly 90° in
~0.5 s, measure the in-game turn, then `S_new = S_old × target/actual`.

| Profile | `mapGyroTo` | S yaw | S pitch | Result |
|---|---|---|---|---|
| FPS, mouse, "≈1:1" starting point | mouse | **0.45** | **0.30** | 28 counts/deg; floor 4.2 °/s |
| FPS, mouse, after 90° test at 2× | mouse | 0.6-1.0 | 0.4-0.7 | floor 2-3 °/s |
| TPS, stick, aim-held | stick | **0.20** | **0.12** | full stick at 229 °/s yaw, 382 °/s pitch |
| Lean-steer (racing) | stick + `rollToLeftStick` | S roll **1.0** | — | full LS at ±60° lean (`out = 32766·(θ/π)·3·S`) |
| Everything | `gyroToStickMinOffset` | **0** | — | any lift >0 creates jumps |

Set `pitchFactor` on the GYRO widget between 0.6 and 1.0 of yaw (most players run less vertical);
use **−1** on yaw or pitch to fix an inverted axis without touching the profile.

## 7. Three ready presets

Common: `useBuiltinGyro = true`, `synthesizePhysicalStick = false`,
`gyroToStickMinOffset = 0`; profile values are applied at layout build (`VLTouchLayer.swift:197`) —
**there is no gyro settings screen in the port yet**, so these ship as profile data or need a small
form exposing exactly `mapGyroTo`, `gyroSensitivityYaw/Pitch`, `yawPitchToRightStick`,
`rollToLeftStick`, `gyroToStickMinOffset`, `useBuiltinGyro`.

### A. "Gyro aim always on" — FPS, mouse output
| Item | Value |
|---|---|
| Profile | `mapGyroTo = .mapGyroToMouse`, S yaw 0.45, S pitch 0.30 |
| Widget 1 (left thumb, small) | `GYRO`, button mode **Tap to toggle** (default) — tap = gyro on, tap = off |
| Widget 2 (right thumb edge) | `GYROPAUSE`, mode **Tap to toggle** — ratchet for repositioning (P5/P6) |
| Widget 3 (right half) | `MOUSEPAD`, sensitivity factor 1.0-2.0, mouse action **LMB** → drag-look with tap-to-fire |
| Widget 4 | `GYROPAUSE` alt: place under the fire button's heel so the trigger pull pauses gyro [INFERENCE: avoids recoil kick] |
| In game | mouse smoothing/acceleration **off**, raw input **on**, aim assist off, in-game sens **halved** then S raised (P12/P13) |
| Tune | 90° test to 1:1; then if distant targets wobble, add ±0.1 S; if slow tracking stutters, raise S and lower in-game sens (floor table §5) |

### B. "Gyro only while aiming/firing" — third person, stick output
| Item | Value |
|---|---|
| Profile | `mapGyroTo = .mapGyroToControllerStick`, `yawPitchToRightStick = true`, `rollToLeftStick = false`, S yaw 0.20, S pitch 0.12 |
| Widget 1 (right side) | `RSVPAD` (camera stick) — gyro sums on top of it (`:514-521`) |
| Widget 2 (aim, e.g. where RMB/ADS lives) | combo `GYRO+MRIGHT`, button mode **Regular** → gyro only while the aim button is held (BotW pattern [N3]) |
| Widget 3 (optional) | `GYRO`, mode **Tap to toggle**, yaw/pitch factors 0.4 → "scoped" gyro; requires toggling off/on to switch (§4) |
| Widget 4 | `GYROPAUSE` for the ratchet |
| Caveats | If the combo widget cannot be authored, use two overlapping buttons (gyro button behind the ADS button) — **[INFERENCE]** the topmost widget takes the touch, so keep the GYRO ring at the button's edge; two gyro buttons do not OR together (§4) |
| Prefer mouse | If the game accepts mouse look, use preset A instead: stick gyro inherits the game's camera curve (P3) |

### C. "Gyro off + flick-style look pad" — no IMU at all
| Item | Value |
|---|---|
| Profile | no `GYRO`/`GYROPAUSE` widget anywhere (gyro never starts); gyro fields irrelevant |
| Widget 1 (right half) | `MOUSEPAD`, sensitivity factor **4-6**, mouse action **LMB** (tap-to-fire) → a ~300 pt swipe ≈ 90-130° in a 22.7-count/deg game (`counts/pt = 1.7 × F`, so `degrees ≈ 22.5 × F`) |
| Widget 2 (right, optional) | `TRACKBALL` variant with `Inertia` on → flick and let it coast (Steam "Trackball Mode" [S3]) |
| Fine aim | left stick / D-pad nudges, crouch-walk; or add a `RSVPAD` for slow camera |
| Honest limit | this is **not** flick stick: VoidLink has no angle→absolute-turn mode (P11/[G4]); a true flick stick needs a one-shot yaw delta computed from pad angle + a real-world calibration constant |
| Slider cap | if the editor's sensitivity factor maxes below ~5, lower in-game mouse sens instead — only the product matters |

## 8. Smallest code changes that unlock the rest

| Gap | Fix | Files |
|---|---|---|
| truncation floor (§5) | accumulate sub-count remainder before `Int16(...)` | `MotionHandler.swift:503-507` |
| callback-time sensitivity drift | replace ×30 with `ω × S × (dt × 3600)` | same |
| P7 smoothing | tiered smoothing as in [G2]/[G5]: two thresholds, direct+smoothed mix, always push into the buffer | `MotionHandler.swift:503-507` |
| P8 tightening | scale magnitude by `min(1, |ω|/thr)` before emission | same |
| P9 acceleration | min/max sens between two °/s thresholds | profile + `handleMotionData` |
| phone axis swap | honour `swapYawAndRoll` in the builtin branch | `MotionHandler.swift:421-465` |
| P10 calibration UI | call the existing `calibrateGyroBias(duration:)` from a `SETTINGS`-side row; persist `gyroBiasX/Y/Z` | `MotionHandler.swift:600`, profile |
| P11 flick stick | new touchpad mode: pad angle → one-shot yaw delta over 0.1 s, rotation → immediate delta, small-angle tiered smoothing | `OnScreenWidgetView` + new sink |
| per-zoom factors | allow factor update while gyro runs (drop the `motionStarter != nil` no-op for factor-only changes) | `MotionHandler.swift:189-196` |

## Sources
- [G1] GyroWiki, *Player Space Gyro (and Alternatives) Explained* — https://gyrowiki.jibbsmart.com/blog:player-space-gyro-and-alternatives-explained
- [G2] GyroWiki, *Good Gyro Controls Part 1: The Gyro is a Mouse* — https://gyrowiki.jibbsmart.com/blog:good-gyro-controls-part-1:the-gyro-is-a-mouse
- [G4] GyroWiki, *Good Gyro Controls Part 2: The Flick Stick* — https://gyrowiki.jibbsmart.com/blog:good-gyro-controls-part-2:the-flick-stick
- [G5] GyroWiki, *Tight and Smooth: Soft Tiered Smoothing* — https://gyrowiki.jibbsmart.com/blog:tight-and-smooth:soft-tiered-smoothing
- [JSM] JoyShockMapper README (§1.7 Gyro Button, §4 Gyro Mouse Inputs, §5 Real World Calibration, `GYRO_SPACE`, `GYRO_CUTOFF_*`, `GYRO_SMOOTH_*`, `MIN/MAX_GYRO_SENS`) — https://github.com/Electronicks/JoyShockMapper/blob/master/README.md
- [S1] Steamworks, *Getting Started for Developers* (`absolute_mouse` vs `joystick_move`) — https://partner.steamgames.com/doc/features/steam_controller/getting_started_for_devs
- [S2] Steamworks, *Mode Shifting* (Gyro shift targets: DPad, Button Pad, Mouse, Mouse Joystick, Joystick Move, Joystick Camera) — https://partner.steamgames.com/doc/features/steam_controller/mode_shifting
- [S3] Steamworks, *Input Source Modes* (Mouse: Sensitivity, Smoothing, Minimum Movement Threshold, Trackball; Joystick Move) — https://partner.steamgames.com/doc/features/steam_controller/input_source_modes
- [N1] Twinfinite, *How to Change Motion Control Settings in Splatoon 3* (separate TV/tabletop vs handheld motion sensitivity) — https://twinfinite.net/guides/how-to-change-motion-control-settings-in-splatoon-3/
- [N2] Nintendo, *Beginner Basics for Splatoon 3* (motion sensitivity in Options; lower it if screen shake bothers you) — https://splatoon.nintendo.com/en/news/beginner-basics-for-splatoon-3-choosing-the-right-weapons/
- [N3] Galaxus, *Gyro aiming is the future* (BotW: motion active only while a long-range weapon is drawn) — https://www.galaxus.at/en/page/aiming-with-sticks-so-yesterday-gyro-aiming-is-the-future-24968
- [M1] trucoman, *COD Mobile sensitivity settings* (gyroscope: "Only when scoped" vs always on) — https://trucoman.com/en/codm-sensitivity/
- [M2] Smartprix, *BGMI camera/ADS/gyroscope* — https://www.smartprix.com/bytes/mastering-bgmi-sensitivity-settings-optimal-camera-ads-and-gyroscope-configuration-for-battlegrounds-mobile-india/
- [M3] Revibyte, *Best Gyroscope Settings for PUBG Mobile* (Always On vs Scope On; polling-rate/drift note on budget devices) — https://www.revibyte.blog/pubgmobile/best-gyroscope-settings-pubgmobile-2026/
- [A1] Apple, *CMDeviceMotion.rotationRate* ("bias has been removed by Core Motion algorithms") — https://developer.apple.com/documentation/coremotion/cmdevicemotion/rotationrate
- [A2] Apple, *CMRotationRate* — https://developer.apple.com/documentation/coremotion/cmrotationrate
- [E1] Hansraj, *Assessment of stresses in the cervical spine caused by posture and position of the head* (2014), summarized at https://www.npr.org/sections/thetwo-way/2014/11/20/365473750/keep-your-head-up-text-neck-can-take-a-toll-on-the-spine
- Secondary (ratchet/gyro-enable-button practice on Steam Deck, no Valve doc found): https://evezone.evetech.co.za/build-lab/gyro-aiming-steam-deck-setup-that-makes-it , https://mygamepadtester.com/blogs/gyro-aiming-explained
