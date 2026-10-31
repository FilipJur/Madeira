# VoidLink touch profiles by genre

Six profiles for the fork's ported VoidLink widget system (`app/Madeira/VLTouch/`), each buildable
in the in-app editor (`WIDGETTOOL` → `VLTouchHost.openEditor()`): widget table + ASCII layout +
rationale + in-game settings, then a build order and test checklists.

**Reference frame.** iPhone 15 Pro, landscape, stream view = **852 × 393 pt** (2556 × 1179 px @3×).
Positions are the stored normalized fractions of that view (host denormalizes them at
`Host/VLTouchLayer.swift:334-337`; editor/save path `Model/OSCProfilesManager.swift:484,537-545`).
`x` right, `y` down; all `x,y` below are widget **centres**.

**Source map.** `CM:` = `third_party/voidlink/VoidLink/Input/CommandManager.swift`; `W:` =
`.../OnScreenWidgetView.swift`; `MH:` = `.../MotionHandler.swift`; `PR:`/`PRh:` =
`.../Input/CustomOSC/OSCProfile.m`/`.h`; `PB:` = `OnScreenButtonState.h`; `WP:`/`EP:`/`HL:` =
`app/Madeira/VLTouch/{Pickers/WidgetPickerView,Editor/LayoutOnScreenControlsViewController,Host/VLTouchLayer}.swift`.
`/tmp/voidlink` paths resolve to `third_party/voidlink/` (verbatim, same bytes).

## 1. Size math (what the editor's Size/Height sliders mean)

| Shape | Used by | Rendered size (pt) | Editor "Size"/"Height" slider |
|---|---|---|---|
| `round` | buttons from the gamepad tab | `d = 60·wf` | `wf` = px/60 |
| `square` | keyboard/mouse/functional buttons | `70·wf × 65·hf` | px/70, px/65 |
| `largeSquare` | **every** touchpad (forced, `W:1507-1510`) | `170·wf × 150·hf` | px/170, px/150 |

Baselines: `W:1162-1176` (60/70/65 and 170/150, `sizeReference = longSide`). Stored factor is
`px/852·10000` (`OSCProfilesManager.swift:537-545`), so a 60 pt button stores `704`. Editor Size/
Height sliders run 0.36-7.0 (`VLEditor.storyboard`, Size/Height), i.e. 61-1190 pt for a pad and
22-420 pt for a round button, so the full-screen pads in §8-§9 are reachable. Minimum comfortable
target: 48 pt; index-finger keys 48-54 pt, thumb keys 60-72 pt.

## 2. Command vocabulary used here (all tokens verified in `CM`)

| Token | Widget type | Behaviour | Evidence |
|---|---|---|---|
| `WASDPAD` | direction pad | digital W/A/S/D, 8-way (67.5° half-angle); `combo[0]`=sprint key, `combo[1]`=walk key | `W:690,1761-1795,1843-1908`; `CM:148` |
| `ARROWPAD` | direction pad | arrow keys (camera pan) | `W:1852-1908`; `CM:151` |
| `DPAD` | direction pad | controller d-pad flags | `W:1845`; `CM:151` |
| `MOUSEPAD` | mouse pad | relative mouse `Δ·1.7·sens`; `.hovering`: tap = LMB click, 2-finger tap = RMB, 2-finger drag = scroll | `W:2950-2958,3156-3157,3480,3074-3090`; `CM:148-149` |
| `ABSMOUSEPAD` | mouse pad | absolute cursor at touch point (+ optional held button) | `W:2989-2993,3198-3201` |
| `WHEEL`/`MOUSEWHEEL`, `DISCRETEWHEEL` | wheel pad | high-res V/H scroll by drag; discrete = ±3 notches/tick | `W:3047-3057,3059-3078` |
| `LSPAD`/`RSPAD` (absolute), `LSVPAD`/`RSVPAD` (velocity) | stick pad | analog stick; absolute = offset from centre, velocity = finger delta | `W:2995-3022,3013-3031,3492-3521`; `CM:153,155` |
| `LTPAD`/`RTPAD` (analog) vs `LT`/`RT` (digital) | trigger pad / button | 0-255 from `-offsetY·4.5·sensY`, resets on lift; digital = 0xFF/0 | `W:3033-3043,3569-3572,2286-2299`; `CM:129-137` |
| `OSCA/B/X/Y`, `LB`, `RB`, `OSCSTART`, `OSCSELECT` | button | pad flags | `CM:97-145` |
| `GYRO` | motion | starts gyro using **this widget's** yaw/pitch/roll factors; `buttonMode` forced `.tapToToggle` | `W:567-570,3206-3214` |
| `GYROPAUSE` | motion | stops / resumes gyro | `W:3216-3222,3338-3345` |
| `FOLDER` / `LABELEDFOLDER` | functional | `regular` = tap toggles open/closed; `slideAndHold` = hold opens, release folds | `W:693,3262-3265,3317-3319` |
| `MLEFT`, `M_RIGHT`, `MMIDDLE`, `MX1`, `MX2`, `WHEELUP`, `WHEELDOWN` | button | mouse press/release; wheel = 3 notches per press | `CM:82-93`; `W:2347-2351` |
| `SPACE TAB CTRL SHIFT ALT E R Q 1-9 ESC PAUSE I J K L C M END DEL` | button | Windows VK down/up | `CM:212-300` |
| `-<n>MS` suffix | grammar | inter-token delay; only meaningful for pad+key combos | `CM:612`; `W:2352-2371` |

**Grammar.** `TOKEN(-TOKEN)*(-<n>MS)?` (`CM:612`). The GUI picker path just splits on `-` and does
**not** validate tokens (`CM:584-590`), so a typo produces a silent dead button — verify in-game.
Picker order matters: a pad that is not priority-first is kept at the pool tail (`WP:1679-1696`),
which is how `MLEFT-MOUSEPAD` (button **first**) is produced.

## 3. Multi-function primitives (the point of this design)

| Primitive | How it is built | Why it works | Evidence / precedent |
|---|---|---|---|
| Look pad that fires on tap | `MOUSEPAD` + `mouseButtonAction = hovering` | move gate is `mousePointerMoved`; no move ⇒ single click on lift, move ⇒ pure aim | `W:3156-3157,1922-1947`; trackpad "click action" model [1] |
| Fire button that aims on drag | **button+pad hybrid** `MLEFT-MOUSEPAD` | `widgetType=button` (first token not a pad) keeps `comboButtonStrings=[MLEFT]`; `touchPadString` non-empty forces `.regular` (`W:564-567`) and `touchesMoved` still runs the pad path (`W:2859-2861`) ⇒ press = LMB down, drag > `slideThreshold` = mouse move | `W:477-500,564-567,2859-2861,2950-2958`; "tap fire and drag at the same time" [6] |
| Two more functions on the look pad | 2-finger tap = RMB, 2-finger drag = wheel | `twoTouchesDetected` + `!scrollEventSent` ⇒ right click; 2-finger move ⇒ high-res scroll | `W:3480,3074-3090` |
| Run stick that sprints past a threshold | `WASDPAD-SHIFT`, `sprintKeyThreshold` | sprint key held while `dist > thr·300·0.5` pt | `W:1763-1780` |
| Aim + gyro on one key | `MRIGHT-GYRO` | combo sent **and** gyro started on the same press; forced toggle | `W:2007-2022,2043-2060,567-570` |
| Slide-chords | `slideAndHold` on the anchor button | press stays down when the finger slides off, so a second key can be added without lifting | `W:2809-2848,2764-2794` |
| Auto-fire | `autoTap` 50-… ms + repeats | timer drives press/release cycles while held | `W:731-749` |
| Analog trigger without an analog trigger | `LTPAD`/`RTPAD` vs digital `LT`/`RT` | 0-255 from vertical offset vs 0/255 | `W:3033-3043,2286-2299` |
| Direct-touch cursor / drag-select | full-screen `ABSMOUSEPAD` + `mouseButtonAction = leftButtonDown` | absolute position on every move, LMB held from touch-down to lift; pads render **below** buttons (`HL:311-317`) so buttons still win | `W:2989-2993,3137-3207`; mobile RTS "drag box = LMB held" [7]; mouse regions move the cursor only unless actions are bound explicitly [2] |

## 4. Profile 1 — PC FPS, mouse+keyboard native (Portal 2, Half-Life 2)

| # | Kind | cmdString | x, y | Size (pt) | buttonMode | Key properties |
|---|---|---|---|---|---|---|
| 1 | pad | `WASDPAD-SHIFT` | .115, .62 | largeSquare 1.10/1.10 (187×165) | — | sprint key SHIFT, `sprintKeyActionType=hold`, `sprintKeyThreshold=0.45`; walk key none; sensX/Y 1.0 |
| 2 | pad | `MOUSEPAD` | .775, .50 | largeSquare 1.35/1.35 (230×203) | — | `mouseButtonAction=hovering`, `slideThreshold=8`, sens 1.6/1.6 |
| 3 | hybrid | `MLEFT-MOUSEPAD` | .80, .875 | square 1.00/1.00 (70×65) | `regular` (forced) | `slideThreshold=4`, sens 0.8/0.8, autoTap blank |
| 4 | btn | `SPACE` | .60, .13 | round 0.90 (54) | `slideToToggle` | jump |
| 5 | btn | `CTRL` | .68, .13 | round 0.90 (54) | `tapToToggle` | sticky crouch |
| 6 | btn | `E` | .76, .13 | round 0.90 (54) | `regular` | use |
| 7 | btn | `R` | .84, .13 | round 0.90 (54) | `regular` | reload |
| 8 | btn | `MRIGHT` | .92, .13 | round 0.90 (54) | `slideAndHold` | secondary / ADS; **variant:** `MRIGHT-GYRO` |
| 9 | motion | `GYRO` | .06, .28 | round 0.85 (51) | `tapToToggle` (forced) | yaw 0.40, pitch 0.30 |
| 10 | func | `FOLDER` | .10, .14 | square 0.90/0.90 (63×58) | `regular` | `revealMode=exclusive`; weapon wheel |
| 11 | btn | `1`…`5` | .20/.29/.38/.47/.56, .09 | round 0.85 (51) | `regular` | folder children |
| 12 | btn | `Q` | .20, .23 | round 0.85 (51) | `regular` | child, last weapon |

```
x 0    .2    .4    .6    .8   1.0
 +----------------------------------+
0| [W][1..5]  [J][C][E][R][RMB]    |
 |[G]                              |
 |                    +-----------+ |
 |     +-------+      |  LOOK PAD | |
 |     | WASD  |      | tap = fire| |
 |     |+SHIFT |      | 2f = RMB  | |
 |     +-------+      +-----------+ |
 |                           [FIRE] |
 +----------------------------------+
```
`[W]`=FOLDER, `[G]`=GYRO, `[J]`=SPACE, `[C]`=CTRL, `[RMB]`=MRIGHT.

**Rationale.** The game reads W/A/S/D + SHIFT, so the left thumb gets a digital 8-way pad, not an
analog stick — a keyboard game cannot use analog magnitude, and the sprint threshold gives "push to
the rim = run" without a second button (67.5 pt at 0.45, `0.45·300·0.5`, `W:1764`). The right thumb
owns the mouse: the big `MOUSEPAD` aims and doubles as fire (tap) and secondary/weapon (2-finger tap
/ drag), keeping three frequent actions on one surface. The hybrid `MLEFT-MOUSEPAD` is the spray
button: press starts LMB down, drag turns it into a second, slower mouse pad, so tracking fire needs
no second finger — the "tap-fire-and-drag-simultaneously" idea mobile shooters train [6]. Gyro is a
toggle (`W:567-570`), mounted where the left index rests and tuned low (0.40/0.30) as a correction
layer over the pad — the usual "stick turns, gyro corrects" split [3][4], with the ratchet habit of
lifting and re-centring [5]. Everything else sits on the top edge so the thumbs never leave move/aim.

**In-game settings.** Mouse sensitivity low (≈2.0-2.5 in Source), mouse acceleration/smoothing off,
windowed-fullscreen; Portal 2 has no sprint/reload (drop the SHIFT suffix and row 7, empty the
folder); HL2 keeps both and uses row 8 for secondary fire; on ADS-capable games swap row 8 for
`MRIGHT-GYRO` so one tap = zoom + gyro.

## 5. Profile 2 — Third-person action, controller-native

| # | Kind | cmdString | x, y | Size (pt) | buttonMode | Key properties |
|---|---|---|---|---|---|---|
| 1 | pad | `LSPAD` | .14, .66 | largeSquare 1.15/1.15 (196×173) | — | `touchPointAnchored=false`, `minStickOffset=1200`, sens 1.0 |
| 2 | pad | `RSPAD` | .68, .56 | largeSquare 1.15/1.15 (196×173) | — | `minStickOffset=1200`, sens 1.0/1.0 |
| 3 | btn | `OSCY` | .885, .585 | round 1.00 (60) | `slideToToggle` | |
| 4 | btn | `OSCX` | .815, .735 | round 1.00 (60) | `slideAndHold` | anchor for chords |
| 5 | btn | `OSCB` | .955, .735 | round 1.00 (60) | `slideToToggle` | |
| 6 | btn | `OSCA` | .885, .885 | round 1.00 (60) | `slideAndHold` | |
| 7 | btn | `LB` / `RB` | .42/.58, .10 | round 0.90 (54) | `slideAndHold` | |
| 8 | btn | `LT` / `RT` | .72/.86, .08 | round 1.00 (60) | `slideAndHold` | analog alt: `LTPAD`/`RTPAD` |
| 9 | pad | `DPAD` | .06, .18 | largeSquare 0.55/0.55 (94×83) | — | quick items |
| 10 | motion | `GYRO` | .30, .14 | round 0.85 (51) | `tapToToggle` (forced) | yaw 0.35, pitch 0.30 |
| 11 | btn | `OSCSTART` | .18, .06 | round 0.75 (45) | `regular` | pause |

```
x 0    .2    .4    .6    .8   1.0
 +----------------------------------+
0|  [ST][G] [LB]    [RB] [LT][RT]   |
 |[DPAD]                            |
 |                      +---------+ |
 |     +-------+        |  RIGHT  | |
 |     | LEFT  |        |  STICK  | |
 |     | STICK |        +---------+ |
 |     +-------+          [X][B]    |
 |                          [Y]     |
 |                          [A]     |
 +----------------------------------+
```
`[ST]`=OSCSTART, `[G]`=GYRO.

**Rationale.** Controller games want familiar geometry, not cleverness: self-centering absolute
left stick, absolute right stick (camera precision beats fling), and a diamond whose A/X are
`slideAndHold` so attack-and-jump chords are one rolling thumb. Triggers are digital `LT`/`RT` by
default because most action games only test the threshold; switch to `LTPAD`/`RTPAD` when the game
wants analog. Gyro is the ADS layer: `mapGyroToControllerStick` + `yawPitchToRightStick` makes
MotionHandler *compose* gyro with the touch stick rather than fight it (`MH:511-538`,
`W:2240-2252`), so a light tilt corrects while the thumb keeps the big turn. Motion buttons can only
toggle (`W:567-570`), so gyro is a one-tap switch beside the d-pad, not a hold-on-LT.

**In-game settings.** Enable the controller/gamepad input; camera sensitivity ≈40-50 %, aim assist
on, deadzone as low as the game allows; set invert-Y to taste (VoidLink's stick Y is already
inverted at `W:2238,2254`); disable "sprint toggle" if the game has one.

## 6. Profile 3 — Platformer / puzzle with controller (Portal 2 pad mode, Hollow Knight)

| # | Kind | cmdString | x, y | Size (pt) | buttonMode | Key properties |
|---|---|---|---|---|---|---|
| 1 | pad | `DPAD` | .10, .70 | largeSquare 0.85/0.85 (145×128) | — | primary movement (digital precision) |
| 2 | pad | `LSPAD` (alt) | .28, .72 | largeSquare 0.80/0.80 (136×120) | — | swap-in for stick players; `minStickOffset=2000` |
| 3 | btn | `OSCX` | .815, .735 | round 1.00 (60) | `slideAndHold` | attack (HK) / use (Portal 2) |
| 4 | btn | `OSCA` | .885, .885 | round 1.05 (63) | `slideAndHold` | jump |
| 5 | btn | `OSCB` | .955, .735 | round 1.00 (60) | `slideToToggle` | focus/cast (HK) / crouch (P2) |
| 6 | btn | `OSCY` | .885, .585 | round 1.00 (60) | `slideToToggle` | dream nail (HK) / partner view (P2) |
| 7 | btn | `LT` | .58, .10 | round 1.05 (63) | `slideAndHold` | super dash (HK) / orange portal (P2) |
| 8 | btn | `RT` | .70, .10 | round 1.05 (63) | `slideAndHold` | dash (HK) / blue portal (P2) |
| 9 | btn | `LB` / `RB` | .46/.82, .10 | round 0.85 (51) | `regular` | quick map / quick cast |
| 10 | btn | `OSCSELECT` / `OSCSTART` | .36/.26, .10 | round 0.85 (51) | `regular` | inventory / pause |

```
x 0    .2    .4    .6    .8   1.0
 +----------------------------------+
0|       [ST][SE][LB] [LT][RT] [RB]  |
 |  +------+                   [Y]   |
 |  | DPAD |      +------+   [X] [B] |
 |  +------+      |LSPAD |     [A]   |
 |                +------+           |
 +----------------------------------+
```

**Rationale.** Precision platforming punishes analog deadzones and diagonals, so movement is a
`DPAD` (Hollow Knight accepts stick *or* d-pad) with an optional stick beside it. The diamond keeps
each game's own default mapping rather than "improving" it — A jump, X attack, B focus, Y dream nail
for HK; A jump, B crouch, X use, Y partner view for Portal 2 [12][13] — because console muscle memory
is the point. Dash/super-dash sit on the triggers where HK puts them, and A/X are `slideAndHold` so
jump↔attack is one rolling thumb. No gyro: neither game has a free-look axis worth tilting for.

**In-game settings.** Enable gamepad; leave HK's default bindings untouched; Portal 2 pad mode
(same table, rows 3-6 relabelled); if the game offers a stick deadzone slider set it low; turn off
any "hold to run" so the d-pad stays 8-way.

## 7. Profile 4 — Racing

| # | Kind | cmdString | x, y | Size (pt) | buttonMode | Key properties |
|---|---|---|---|---|---|---|
| 1 | motion | `GYRO` | .32, .14 | round 0.85 (51) | `tapToToggle` (forced) | **rollFactor 0.35** (tilt → left-stick X) |
| 2 | pad | `LSPAD` | .12, .74 | largeSquare 0.90/0.90 (153×135) | — | steering trim / fallback, sens 0.8 |
| 3 | pad | `LTPAD` | .68, .58 | largeSquare 0.65/1.45 (110×217) | — | brake, sensY 0.70 |
| 4 | pad | `RTPAD` | .86, .58 | largeSquare 0.65/1.45 (110×217) | — | throttle, sensY 0.70 |
| 5 | btn | `OSCA` | .50, .10 | round 1.05 (63) | `slideAndHold` | handbrake |
| 6 | btn | `LB` / `RB` | .38/.62, .08 | round 0.90 (54) | `regular` | gear down / up |
| 7 | btn | `OSCY` | .74, .10 | round 0.90 (54) | `regular` | look back / camera |
| 8 | btn | `OSCSTART` | .26, .08 | round 0.80 (48) | `regular` | pause |

```
x 0    .2    .4    .6    .8   1.0
 +----------------------------------+
0|    [ST][G]   [LB][A][RB][Y]       |
 |                        +--+ +--+  |
 |  +------+              |BR| |TH|  |
 |  |LSPAD |              |AK| |R |  |
 |  +------+              +--+ +--+  |
 +----------------------------------+
```

**Rationale.** Tilt steering is the one motion mapping that is strictly better on a phone than a
stick: hold the phone like a small wheel and left-right tilt maps to left-stick X, the axis racing
games steer with [8]. VoidLink implements exactly that: with `mapGyroToControllerStick` +
`rollToLeftStick`, steering comes from the gravity angle relative to the angle at gyro-enable time
(`MH:217-219,525-535,568-590`), so it is a positional wheel — 30° of tilt is a fixed steering angle
and re-centring the phone re-centres the car. `LSPAD` remains and is *added* to the gyro value
(`MH:533`) as trim and as a gyro-off fallback. Throttle/brake are analog pads because racing needs
partial input; their travel is halved by the centre-origin maths (`W:3034`), hence the tall 1.45
height and `sensY 0.70` so full pull lands at ~75 % of the top half, not at the edge.

**In-game settings.** Enable gamepad; steering linearity/deadzone at 0, assists per taste, camera
shake off; calibrate by holding the phone at the resting angle and then tapping `GYRO` (that pose
becomes neutral, `MH:212`); tune `gyroSensitivityRoll` so ±30° ≈ full lock.

## 8. Profile 5 — Isometric CRPG / point-and-click (Esoteric Ebb, Disco Elysium, DOS2)

| # | Kind | cmdString | x, y | Size (pt) | buttonMode | Key properties |
|---|---|---|---|---|---|---|
| 1 | pad | `ABSMOUSEPAD` | .50, .50 | largeSquare 5.00/2.60 (**850×390**, full screen) | — | `mouseButtonAction=leftButtonDown`, `backgroundAlpha=0`, `borderAlpha=0` |
| 2 | btn | `TAB` | .86, .22 | round 1.00 (60) | `regular` | hold to highlight interactables |
| 3 | pad | `WHEEL` | .94, .50 | largeSquare 0.40/1.00 (68×150) | — | zoom, sensY 0.60 |
| 4 | btn | `MRIGHT` | .90, .84 | round 1.05 (63) | `regular` | context / move-here |
| 5 | func | `FOLDER` | .90, .10 | square 0.85/0.85 (60×55) | `regular` | `revealMode=exclusive` |
| 6 | btn | `I` `J` `K` `L` | .80/.72/.64/.56, .05 | round 0.80 (48) | `regular` | children: inventory/journal/quest/spellbook (Disco: K→`T` thought cabinet, L unused) |
| 7 | btn | `Q` `C` `M` | .78/.70/.62, .16 | round 0.80 (48) | `regular` | children: character/stat sheet/map |
| 8 | btn | `END` / `DEL` | .54/.46, .16 | round 0.80 (48) | `regular` | children: DOS2 camera rotate L/R |
| 9 | btn | `ESC` / `SPACE` | .06/.16, .10 | round 0.90 (54) | `regular` | menu / pause |

```
x 0    .2    .4    .6    .8   1.0
 +----------------------------------+
0| [ESC][SP]       [I][J][K][L]  [FLD]
 |                 [Q][C][M][E][D]   |
 |  +----------------------------+ [WHL]
 |  | ABSMOUSEPAD (full screen)  |  [TAB]
 |  | tap = click, drag = LMB    |  [RMB]
 |  +----------------------------+
 +----------------------------------+
```

**Rationale.** A point-and-click game is a mouse with a fixed camera, so the honest mapping is a
full-screen absolute pad: the cursor jumps to the touched pixel and LMB goes down on the way (position
is sent before the press, `W:3196-3201`), making "tap the thing" and "drag an item" one gesture. Pads
render *below* buttons (`HL:311-317`), so the pad never steals the hotkey buttons. `leftButtonDown`
(not `hovering`) drops the 200 ms click heuristic for instant hold-and-drag clicks; two fingers
suppress the click entirely (`W:2553,3474-3480`) as the escape hatch. Highlighting is a held `TAB` —
Disco and Esoteric Ebb use Tab/RMB, DOS2 uses Alt [9][10][11] — under the right index, holdable while
the left thumb taps. All menus are one folder; DOS2's camera keys live there because Disco Elysium has
no camera rotation at all [9].

**In-game settings.** Keep mouse mode (no controller); disable edge-scroll if present; DOS2: enable
"Alt highlights objects", keep middle-drag rotate on the keyboard keys instead; Disco: nothing to
configure beyond text size; Esoteric Ebb: leave defaults (Tab also hides UI there — the button is
hold-to-highlight, so a tap flashes it).

## 9. Profile 6 — Strategy / RTS-lite

| # | Kind | cmdString | x, y | Size (pt) | buttonMode | Key properties |
|---|---|---|---|---|---|---|
| 1 | pad | `ABSMOUSEPAD` | .50, .50 | largeSquare 5.00/2.60 (**850×390**) | — | `leftButtonDown`, alpha 0 → drag-select + edge pan |
| 2 | pad | `ARROWPAD` | .08, .78 | largeSquare 0.75/0.75 (128×113) | — | camera keys, 8-way |
| 3 | pad | `WHEEL` | .94, .45 | largeSquare 0.40/1.00 (68×150) | — | zoom, sensY 0.70 |
| 4 | btn | `MRIGHT` | .90, .82 | round 1.05 (63) | `regular` | move/attack order |
| 5 | func | `FOLDER` | .90, .12 | square 0.85/0.85 (60×55) | `regular` | `revealMode=exclusive` |
| 6 | btn | `1`…`5` | .78/.70/.62/.54/.46, .05 | round 0.80 (48) | `regular` | children: control groups |
| 7 | btn | `B` `H` `G` | .78/.70/.62, .16 | round 0.80 (48) | `regular` | children: build/hold/garrison |
| 8 | btn | `SHIFT` | .72, .90 | round 0.95 (57) | `tapToToggle` | queue orders |
| 9 | btn | `PAUSE` / `ESC` | .06/.16, .12 | round 0.90 (54) | `regular` | pause / menu |

```
x 0    .2    .4    .6    .8   1.0
 +----------------------------------+
0| [P][ESC]         [1][2][3][4][5][FLD]
 |                 [B][H][G]         |
 |  +----------------------------+ [WHL]
 |  | ABSMOUSEPAD (full screen)  |   [RMB]
 |  | drag = box, edge = edge pan|
 |  +----------------------------+
 |  +------+              [SHIFT]    |
 |  |ARROWS|                       |
 +----------------------------------+
```

**Rationale.** RTS input is three gestures and a keyboard: box-select, pan, zoom, hotkeys. A
full-screen absolute pad with LMB held from touch-down reproduces the mobile-RTS convention exactly —
drag on empty ground draws a box, tap selects, and holding at the screen edge engages the game's own
edge pan (the pad reaches every pixel because it *is* the screen) [7]. `ARROWPAD` covers games without
edge pan, `WHEEL` zooms, `MRIGHT` orders, so select→order never moves the thumb. Hotkeys are a
two-row folder (groups 1-5, then build/hold/garrison), opened by one tap and closed by the next
(`regular`, `W:3317-3319`). `SHIFT` is sticky, not held: queueing is a mode, and a toggle never fights
the pad for the same finger.

**In-game settings.** Enable edge pan and wheel zoom; bind control groups 1-5 and build/hold to the
keys used above; disable "click-and-drag always selects" if the game has a drag-pan mode; set
scroll speed low so a 1 s edge hold does not fling the camera.

## 10. Prerequisites and port limits (read before building)

| # | Issue | Evidence | Action |
|---|---|---|---|
| P1 | **Profile-level gyro mode has no UI.** `mapGyroTo`, `yawPitchToRightStick`, `rollToLeftStick`, `gyroSensitivity*` exist only as profile fields | `PRh:46-56`, defaults `PR:110-120` (**every new profile = gyro→mouse**) | Author them when the profile is created (preset `.bin` or a 4-control "Gyro" section in the editor). Without this, `GYRO` in profiles 2 and 6 drives the Windows cursor instead of the right stick. Blocks profiles 2 and 6 |
| P2 | Gyro config is read once, at widget build | `MH:66-79`, `HL:196` | Changing gyro mode needs the stream/profile to rebuild, not just a widget edit |
| P3 | Motion widgets are always `tapToToggle` | `W:567-570` | Design gyro as a switch. A "hold LT to enable gyro" is not expressible as one widget; use `MRIGHT-GYRO`/`LT-GYRO` as a toggle instead |
| P4 | Paddles, `MISC`, `DS4TOUCH`, `DS4TCHBTN`, controller-motion passthrough are no-ops in the fork | `docs/fork/TOUCH-PORT.md` sink table | Never place those widgets; gyro must be the phone's own (`useBuiltinGyro`, default true, `MH:68,215-222`) |
| P5 | `slideAndHold` is not "hold to press": it presses on direct touch *and* stays down when the finger slides off | `W:2809-2848` | Use it for chord anchors (fire, A/X, triggers); use `regular` for anything that must release when the thumb wanders |
| P6 | `LT`/`RT` are digital | `W:2286-2299` | Use `LTPAD`/`RTPAD` whenever partial input matters (racing, throttle) |
| P7 | Token typos are silent | `CM:584-590` | Tap every new widget once in-game before saving the profile |
| P8 | Fire hybrid needs picker order **button then pad** | `WP:1679-1696` | Add `MLEFT`, then `MOUSEPAD`; the reverse order produces a pad whose combo is never pressed |

## 11. Build order in the in-app editor

Rationale: each step only introduces widget types the previous step already proved, and the two
gyro-mode-dependent profiles come after P1 is done.

| Order | Profile | Why here | Profile name |
|---|---|---|---|
| 1 | Platformer | Fewest moving parts: pad + 6 buttons, no mouse, no gyro. Proves the sink end-to-end (buttons, triggers, d-pad) | `Pad · Platformer` |
| 2 | Third-person action | Adds analog sticks and gyro→right stick; needs P1. Duplicate #1 and add sticks instead of starting empty | `Pad · ThirdPerson` |
| 3 | PC FPS | Adds relative mouse, the button+pad hybrid, sprint threshold, first folder. Needs P8 | `Mouse · FPS` |
| 4 | CRPG | Adds absolute mouse, `leftButtonDown`, wheel, 9-child folder; no new sink path | `Mouse · CRPG` |
| 5 | RTS | Reuses #4's pad plus arrow pad and a two-row folder | `Mouse · RTS` |
| 6 | Racing | Highest tuning risk (tilt→stick, analog trigger pads, gravity reference); needs P1 | `Pad · Racing` |

Editor mechanics that matter: new widgets spawn at (90,130) and must be dragged into place
(`EP:1409`); size/height are the sliders, and `round` buttons ignore Height; nest a child by
dragging it onto the unfolded folder until it highlights, then release (`W:3689-3699`); duplicate a
profile from the profile picker and rename it before editing, because per-game binding is by name
(`Library.swift:205`, `VLTouchSwitch.swift:49`).

## 12. Test checklists

**Shared (run once per profile, in a live stream).** ① every widget flashes on touch; ② no widget
produces a dead tap (P7); ③ home-button/background the app while holding move+fire → nothing stuck
(`VLSink.releaseAll`); ④ switch profile mid-session → layout rebuilds, no ghost widget; ⑤ rotate
device and back → widgets keep their relative positions.

| Profile | Checks |
|---|---|
| Platformer | DPAD gives 8 distinct directions; diagonals register both axes; A jump fires once per tap; X attack repeats on rapid taps; RT dash and LT super-dash reach the game; LB opens the map; Back opens inventory; A held + X slid onto = both flags held, both released on lift |
| Third-person | full LSPAD deflection = run, release = stop (no residual stick); RSPAD turns the camera, self-centres on lift; gyro on → camera drifts with tilt and *stops* when toggled off; gyro + RSPAD turn together without fighting; A/B/X/Y match the in-game prompts; LT/RT hit the game's threshold; no drift at rest with `minStickOffset=1200` |
| PC FPS | W/A/S/D arrive as keys; sprint starts past the threshold and stops when returning inside it; look pad: tap = one shot, drag = aim with no shot; 2-finger tap = RMB; 2-finger drag = weapon switch; fire pad: tap = one shot, hold+drag = continuous fire while turning; crouch toggles and stays; folder opens on tap, closes on tap, `3` selects weapon 3; gyro moves the view and stops on the second tap |
| CRPG | tap anywhere = click at that pixel; drag = LMB held for the whole drag; two-finger touch = no click; `TAB` held highlights while held, releases on lift; wheel drag zooms in both directions; `MRIGHT` opens the context action; each folder child opens the right panel (I/J/K/L/Q/C/M); `END`/`DEL` rotate the DOS2 camera |
| RTS | drag on empty ground draws a selection box; tap selects a unit; drag to the screen edge and hold → camera pans; arrow pad pans without moving the cursor; wheel zooms; `MRIGHT` issues the order at the cursor; `1`-`5` select groups; `SHIFT` sticky-queues then untoggles |
| Racing | with gyro on, ±30° tilt ≈ full lock and returning to the start angle straightens the car; LSPAD adds trim on top of tilt; throttle pad is proportional (half travel ≈ half throttle) and returns to 0 on lift; brake pad same; handbrake holds while the thumb slides; gear up/down register once per tap |

## Sources

[1] Steamworks, Input Source Modes (trackpad as mouse, click action, touch binding) — https://partner.steamgames.com/doc/features/steam_controller/input_source_modes
[2] Steamworks, Mouse Regions (position only unless bindings added) — https://partner.steamgames.com/doc/features/steam_controller/mouse_regions
[3] reWASD, gyro aiming (bind gyro to a button, not always-on) — https://www.rewasd.com/blog/post/how-to-use-gyro-controls-on-pc
[4] MyGamepadTester, gyro guide (stick does the turn, gyro the correction; low sensitivity is the common error) — https://mygamepadtester.com/blogs/gyro-aiming-guide-1
[5] Steam Controller grip-sense / ratcheting — https://steamgamer.com/articles/controller/steam-controller-gyro-grip-sense-setup-guide/
[6] Mobile FPS drag-fire and left-fire layouts — https://killarnation.com/guides/one-tap-headshot-settings/ , https://www.revibyte.blog/pubgmobile/best-4-finger-hud-layout-pubgmobile-2026/
[7] Mobile RTS touch conventions (drag box = LMB held, tap select, two-finger pan) — https://gamedev.net/blogs/entry/2274389-rts-devlog-5-input-and-gestures , https://github.com/Producdevity/gamehub-lite/releases/tag/v5.1.4
[8] Tilt steering maps left-right tilt to left-stick X — https://www.gamepad.space/guides/gyro-steering-racing ; GRID Autosport tilt FAQ — https://www.feralinteractive.com/en/faqs/gridautosport/1.6/android/?access=tycfukaw3c
[9] Disco Elysium controls (Tab highlight, wheel zoom, no camera rotation, I/J/M/C) — https://defkey.com/disco-elysium-shortcuts
[10] Divinity: Original Sin 2 controls (Alt highlight, middle-drag camera, wheel zoom) — https://defkey.com/divinity-original-sin-2-shortcuts
[11] Esoteric Ebb keyboard controls (Tab/RMB highlight, E interact, I/J/K/L/Q/C) — https://steamcommunity.com/sharedfiles/filedetails/?id=3679583571
[12] Portal 2 controls (A jump, B crouch, RT/LT portals, X use, RB zoom) — https://strategywiki.org/wiki/Portal_2/Controls
[13] Hollow Knight controls (A jump, X attack, B focus, Y dream nail, RT dash, LT super dash, LB map) — https://hollowknight.wiki/w/Controls_(Hollow_Knight)

[INFERENCE] All layouts are hand-geometry estimates for a 852×393 pt view and were not yet tested on
a device; the widget mechanics cited above are read from code, not measured. Profile 2/6 gyro
behaviour depends on P1 being implemented.
