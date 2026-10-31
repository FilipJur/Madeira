# Touch-control design principles for action games on a 6.1" iPhone

Scope: rules a VoidLink profile designer should follow for the Madeira fork (Wine game, landscape, ~1424×656 game window on 2556×1179). Sources: Xbox Touch Adaptation Kit (TAK) documentation, platform HIGs, published mobile-game settings, HCI papers, and the ported VoidLink code. VoidLink citations use short prefixes defined in §0. Every number not directly quoted is marked `[INFERENCE]` and derived in the table that contains it.

## 0. Citation keys

| Key | File (Madeira fork) |
|---|---|
| `OSWV:n` | `app/Madeira/VLTouch/Widgets/OnScreenWidgetView.swift` |
| `CM:n` | `app/Madeira/VLTouch/Commands/CommandManager.swift` |
| `MH:n` | `app/Madeira/VLTouch/Widgets/MotionHandler.swift` |
| `OSB.h:n` | `app/Madeira/VLTouch/Model/OnScreenButtonState.h` |
| `PROF.h:n` | `app/Madeira/VLTouch/Model/OSCProfile.h` |
| `XC:n` | `app/Madeira/VLTouch/Support/VLTouch.xcstrings` |
| `PRESET:n` | `app/Madeira/TouchControlPresets.swift` |
| `PORT.md` | `docs/fork/TOUCH-PORT.md` |

External sources are numbered `[S1]`…`[S28]` and listed in §15.

## 1. The target screen, in numbers

iPhone 15 Pro: 2556×1179 px at 460 ppi = 852×393 pt landscape, 141×65 mm. `[INFERENCE]` derived from px/ppi; the repo uses the same landscape geometry for its built-in layout: `PRESET:107-108` (`referencePhone` 874×402, insets left/right 59, bottom 21).

| Quantity | pt | mm | Note |
|---|---|---|---|
| Screen (landscape) | 852 × 393 | 141 × 65 | 2.17:1 |
| Game window 1424×656 | — | — | 2.171:1 → fills the screen, no letterbox; 1 pt ≈ 1.67 game px `[INFERENCE]` |
| Side safe inset (notch/Dynamic Island side) | 59 each | 9.8 | `PRESET:107-108`, [S6] |
| Bottom safe inset (home indicator) | 21 | 3.5 | `PRESET:102,108` |
| Usable width inside side insets | 734 | 121 | 86% of width |
| Apple minimum target | 44 | 7.3 | [S27] "44x44 pt"; `PRESET:115` uses 64 pt as its base |
| Xbox minimum target, phones | 90.6 | 15 | [S5] "15 mm × 15 mm (or 15 mm diameter)" |
| VoidLink default round button | 60 | 10 | `OSWV:1167` (`baselineDiameter = 60` when `sizeReference = longSide`) |
| VoidLink default stick pad | ~173 | 28.6 | `OSWV:147` `componentSizeFactor 2.88` × 60 `[INFERENCE]` |
| Comfortable thumb radius from corner grip | ~150–190 | 25–31 | `[INFERENCE]` from [S1] "thumbs can only reach so far into the center" |
| Xbox 8 mm / 10 mm spacing | 48 / 60 | 8 / 10 | [S21] |

Consequence: VoidLink's 60 pt default is **10 mm — below the 15 mm phone minimum** in [S5]. A profile whose primary fire button is left at default is one third too small for a competitive shooter.

## 2. Where hands actually are

| Finding | Source |
|---|---|
| Touch gameplay realistically allows **two simultaneous inputs**, one per thumb; a gamepad scheme uses up to four. | [S1] "Usually only two inputs at a time are possible…"; [S25] |
| Comfortable zones are **radial from the grip**, not a grid; thumbs cannot reach far into the centre. | [S1] (tak-arcs figure text) |
| Left thumb owns locomotion and "actions that must be done while moving"; right thumb owns camera + attack. | [S1] left/right wheel sections |
| Centre of a landscape phone is reachable only by stretching, or by an index finger in a claw grip. | [S1]; claw practice in [S8][S12][S13] |
| People hold phones in three grips (49% one-handed, 36% cradled, 15% two-thumb); 75% of interactions are thumb-driven, and grip shifts constantly. | [S20] |
| Thumb occlusion is a first-class gaming problem; physical buttons beat virtual ones (150% more deaths, 42% slower completion on touch). | [S22] |

Design consequence: treat the screen as **four zones** — left wheel (movement), right wheel (camera + primary action), upper (menus/rare), lower (rarely used) — exactly as TAK does [S1]. Anything in the middle band requires either a claw finger or a compound gesture.

## 3. Action → zone → widget map

| Action class | Frequency | Zone | VoidLink widget | Why |
|---|---|---|---|---|
| Move | continuous | left wheel, inner | `LSPAD` (displacement, fixed) or `LSVPAD` (velocity) | `CM:153,155`; [S1] inner left = one locomotion control |
| Camera | continuous | right wheel, inner, **inboard** | `MOUSEPAD` (relative mouse) or `RSVPAD` (velocity stick) | `CM:155`; [S1] gyro/touchpad preferred over stick |
| Fire | continuous | right wheel | `MOUSEPAD` w/ button action, or a `RT`/`M_LEFT` button | `CM:149`; [S3] `renderAsButton` |
| Aim/ADS | held during fights | adjacent to fire | button `M_RIGHT`/`LT`, or fold into fire | [S1] `pullAction`; [S8] 1-tap ADS |
| Reload / interact | periodic | right wheel, outer | button | [S1] outer right = quick actions |
| Jump / dash / crouch | periodic | outer right, below primary | button, `tapToToggle` for crouch | [S1] slots 4/5; `OSB.h:98-104` |
| Weapon/item switch | periodic | left wheel outer or lower | `WHEEL`, `DPAD`, folder | `CM:148`; [S1] |
| Map / inventory / pause | rare | upper band | folder / functional button | [S1] upper zone; `OSWV:693` folders |
| Sprint | continuous modifier | inside move stick | stick threshold + `actionThreshold` | [S2] example 2; `OSWV:377-380` |
| Gear / vehicle / rare keys | rare | folder or radial | `FOLDER`, `LABELEDFOLDER` | `OSWV:578,693`; [S15] |

## 3.5 What existing overlays converge on

| Overlay | Model | Lesson for this fork |
|---|---|---|
| Xbox Cloud Gaming (TAK) | Declarative JSON layouts; zone/slot system; per-game bundle; layout or state switched by game code | Reference implementation of everything in this document [S1][S25] |
| Fortnite mobile | HUD Layout Tool; three presets (default, Combat Pro, Builder Pro); fire modes Auto Fire / Tap Anywhere / Dedicated Button | Ship named presets and let players branch from them [S9][S10] |
| GeForce NOW | Touch only for a curated list (Fortnite, Genshin, Into the Breach…); on-screen controls also expose keyboard, zoom, right-stick-as-mouse | Curate: do not promise touch for every title; keep utility actions in the overlay, not the game [S28] |
| Steam Link / Steam Input | Full virtual Steam Controller; per-game binding layouts; touch/radial menus with size + opacity sliders; overlay fades after 10 s idle; falls back to the nearest template | Ship a template fallback and make menus first-class widgets [S15][S16] |
| Moonlight iOS | No / Simple (6 buttons) / Full overlay; "Auto" shows only the buttons a paired controller lacks | Progressive disclosure; never show what the player already has [S17] |
| Winlator | Separate RTS (mouse) and Virtual Gamepad modes; drag-and-drop editor; importable touch profiles | Mouse-centric and pad-centric are different profiles, not one [S18] |
| GameHub | Reposition / resize / transparency on the touch overlay; controller mapping separate | Transparency is a first-class user control [S19] |
| VoidLink (ported) | Full widget editor, folders, auto-dock, per-profile files, gyro widgets, import/export | The fork can express all of the above except game-state switching `[INFERENCE]`: `PORT.md` file map |

## 4. Size, spacing, opacity

| Rule | Value | Evidence |
|---|---|---|
| Primary action diameter | **90–120 pt (15–20 mm)** | floor [S5]; ceiling from thumb occlusion [S22] |
| Secondary | 64–80 pt (11–13 mm) | above the 44 pt HIG floor [S27], below 15 mm because it is not the main contact |
| Tertiary / menu | 56–64 pt (9–11 mm) | error rates rise sharply below ~10 mm [S21] (6.74 mm → up to 23% errors) |
| Absolute hit floor | 44 pt / 7.3 mm | [S27]; the hit area may exceed the artwork |
| Gap between targets | ≥ 8 mm centre-to-centre, 10 mm preferred; in pt ≥ 48, target 60 | [S21]; [S5] "buffer of inactive screen around each" |
| Stick pad diameter | 150–200 pt (25–33 mm) | `OSWV:1167`+147 gives 173 pt; [S2] `expand` for centre sockets |
| Fill opacity | 0.35–0.55 | VoidLink default `backgroundAlpha 0.5` `OSWV:184`; CoD HUD slider [S8]; community 60–80% [S7b] |
| Label/icon opacity | 0.8–0.9 | default `labelAlpha 0.82` `OSWV:197`; Steam keeps icons at 100% [S15] |
| Border/hairline | 0.08–0.15 | default `borderAlpha 0.1` `OSWV:199` |
| Pressed highlight | ≥ 0.7 | default `highlightAlpha 0.77` `OSWV:200`; TAK shrinks face 25% on press [S4] |
| Idle-fade secondary controls | after 5–10 s | Steam Link fades the whole overlay after 10 s [S16]; VoidLink auto-dock `OSWV:3858-3862` |

Never make a button invisible-but-active at 0 opacity: it becomes an invisible trap. If a control must disappear, disable or auto-dock it (`OSWV:3858-3862` exposes a 70×17 pt sliver with a custom "Docked opacity").

## 5. Sticks: floating (relative) vs fixed (absolute)

| Mode | Behaviour | Use when | Evidence |
|---|---|---|---|
| Relative / floating | value from where the finger landed; the ring may not be drawn until touched | large phones, thumbs landing imprecisely; no speed thresholds | [S2] `relative` default true; `expand` |
| Absolute / fixed | value from the control's own centre; base always visible | games with walk→run speed curves, fighters, RTS | [S2] `relative:false`; [S1] "use non-relative… if a game has a system to change speed" |
| Displacement pad | thumb position = stick vector, snapped back | gamepad-native movement | VoidLink `LSPAD`/`RSPAD` `CM:153` |
| Velocity pad | thumb delta = rate, with inertia | camera/swipe look, trackball | VoidLink `LSVPAD`/`RSVPAD` `CM:155`; `OSWV:3022-3030` |
| Anchored | stick base jumps to the touch point | thumb-anywhere movement | `OSWV:307` `touchPointAnchored` |

Deadzone: 0.05 radial is the TAK baseline [S2]; VoidLink exposes `minStickOffset` and sensitivity min/max `OSWV:289,250-257`.

**Mixed reality check:** if the Windows game reads mouse-look (most FPS on Wine), drive camera with `MOUSEPAD` (raw deltas, `OSWV:2950-2956`) and movement with `LSPAD`; if the game is gamepad-native, use `RSVPAD`/`RSPAD`. Mixing a relative-mouse look pad with a gamepad movement stick is normal and works through separate sinks (`PORT.md` sink table).

## 6. Compound controls (the core of the user's request)

### 6.1 Fire button that also aims — "drag-to-aim while firing"

| Implementation | Recipe | Source |
|---|---|---|
| TAK | `touchpad` with `renderAsButton: true`; axis → `relativeMouseX/Y`; `action: [rightTrigger, leftTrigger]` | [S1] Aim+Fire example, Gears 5 |
| TAK alt | `button` with `action: leftTrigger` and `pullAction: rightTrigger` — press to aim, pull outward to fire | [S4]; [S1] |
| VoidLink | `MOUSEPAD` (or `ABSMOUSE`) — in `mousePadWithButtonActions`: touch-down sends the mouse button after `mouseButtonActionDelay`, drag sends `LiSendMouseMoveEvent`, two-finger tap sends right click | `CM:149`; `OSWV:3174-3203`, `2950-2956`, `3475-3480`; delay `OSWV:209,713` |
| Community technique | Free Fire "drag headshot": press fire, drag the **fire button itself** upward; needs empty screen above the button | [S9b] |

Design rules for it:
1. **Put it inboard, not at the edge.** TAK: "Always place Aim+Fire more toward the center… If it's placed at the edge, where the player can't turn the camera fully to the right, they'll run out of room to swipe." [S1]
2. **Leave 1.5–2 button diameters of empty game view above and to the right of the pad** — the drag is the aim. [S9b] "empty space above the fire button is the most influential".
3. Size it large (≥ 100 pt) but keep the *sensitive* part central; keep the visual ring translucent so the target under the thumb stays visible [S22].
4. Fire on touch-down, not touch-up, for weapons. XAG permits the down-event exception for "firing a weapon" [S5]; VoidLink `MOUSEPAD` presses immediately, while `ABSMOUSEPAD` delays 5 ms so the absolute position lands first (`OSWV:713`, default `OSWV:209`).
5. Two-finger tap = secondary (ADS/right-click) is a natural bonus of the same widget `OSWV:3478-3480`.

### 6.2 Look pad with tap-to-fire

| Piece | Recipe | Source |
|---|---|---|
| TAK | `touchpad` + `action`, `renderAsButton` | [S3] |
| VoidLink | `MOUSEPAD` (relative) or `ABSMOUSEPAD` (cursor jumps to finger; `OSWV:2989-2992`) | code |
| Steam Link | trackpad mode: 1-finger slide = move, 1-finger tap = left click, 2-finger tap = right click | [S16] |

Use it when the game wants a click for "attack" and has no gamepad path, or when the right thumb must both steer and shoot. Do **not** use `ABSMOUSEPAD` for camera: absolute positioning makes look feel like a cursor, not a view — reserve it for menus/RTS (`OSWV:2989`).

### 6.3 Auto-fire

| Product | Mechanism | Source |
|---|---|---|
| VoidLink | `autoTapInterval` ms (min 50), `autoTapRepeats`; button-only, and explicitly disabled when the button carries a functional or gyro command | `OSWV:212-213`, `87`, `679`, `731-737` |
| Fortnite mobile | "Auto Fire" — fires when the crosshair is over an enemy; recommended for new players | [S9] |
| CoD Mobile | simple-fire mode with a *limited* auto-hip-fire range | [S8] |
| XAG | recommends offering `auto-fire`, `auto-sprint`, `auto-jump` as accessibility options | [S5] |

Rules: auto-fire is a **toggle, off by default for precision weapons**, and its state must be visible on the button (VoidLink shows the pressed state; use `tapToToggle` `OSB.h:98-104`). Auto-fire + auto-aim compounds into "the game plays itself" and is a legitimate accessibility mode but a poor default skill profile.

### 6.4 Run stick with sprint lock past the edge

| Product | Behaviour | Source |
|---|---|---|
| TAK | joystick `action: rightTrigger`, `actionThreshold: 0.75` (guide says 2.5 in one snippet) — "a player can switch from walk to sprint by just using the left joystick" | [S2] example 2; [S1] |
| VoidLink | pad `comboButtonStrings[0]` fires when `dist > sprintKeyThreshold * ref * 0.5` (default 0.6), `[1]` when below walk threshold (0.08); each threshold is `hold` or `toggle` | `OSWV:377-380, 1760-1805` |
| CoD Mobile | "Joystick Sprint" — sprint by holding the stick forward; separate Auto-Run button | [S8] |
| Genshin | walk/run by *finger distance from the pad centre*, with an optional toggle button | [S14] |

Rules:
- Threshold at **60–75% of full deflection**, with a **haptic tick** on crossing (`OSWV:1789-1792` calls `performVibrationFeedback`), so the state is felt, not looked at.
- Show the state on the knob (VoidLink `sprintSign`/`walkSign`, `OSWV:386-387`; TAK `activated` style [S2]).
- Provide a **separate auto-run toggle** for thumb-off play (CoD Auto-Run [S8]; XAG auto-sprint [S5]).
- Never require the stick to be held *and* a second button for sustained sprint — see §11 (XAG: avoid required simultaneous presses [S5]).

### 6.5 ADS modes

| Mode | Behaviour | Where it comes from |
|---|---|---|
| Hold | finger stays down while aiming; release returns to hip fire | Apex's recommended "ADS Mode: Hold" [S12] |
| Tap-to-toggle | one tap enters sights, next tap leaves | TAK `toggle: true` [S4]; VoidLink `tapToToggle` `OSB.h:98-104` |
| Pull-to-aim, press-to-fire | one widget: touch = aim, pull outward = fire | TAK `pullAction` [S4]; Aim+Fire touchpad in Gears 5 [S1] |
| One-tap ADS+fire | a single touch aims *and* fires (sniper/shotgun friendly) | Apex "One-Tap ADS and Fire" [S12]; CoD per-weapon 1-tap ADS [S8] |
| Separate hip-fire button | keeps a hip-fire trigger while the main button is ADS | CoD Advanced Mode hip-fire button [S8] |
| Gyro only while ADS | tilt aiming armed by the ADS button | CoD "Gyroscope… turning this on While ADS" [S8]; Apex gyro modes [S12] |

Default a new profile to **hold ADS + ADS-only gyro**; offer tap-toggle and one-tap ADS+fire as switches, because they change how a fight feels, not just where a button sits.

## 7. Finger-count tiers

| Tier | Hands | Extra inputs | Typical layout | Source |
|---|---|---|---|---|
| 2-thumb | 2 | none | movement + look/fire pad; everything else tap or compound | default in [S8][S14] |
| 3-finger | 3 | one index at a top corner | index = fire or jump; thumb keeps camera | [S13] |
| 4-finger claw | 4 | both indexes at top corners | left index = ADS/peek, right index = fire; thumbs for move + camera; slide/jump opposite fire | [S8][S12][S13] |
| 5–6 finger | 5–6 | indexes + middle fingers | triggers on top edge, shoulders as bumpers | [S13] community |

A **claw profile is a different profile, not a setting**: the indices occupy the top corners (~top 15% of screen, within 25% of each edge), which must stay free of other controls. `[INFERENCE]` from claw geometry and [S8] "park slide and jump opposite your shoot button". Ship a 2-thumb default and a claw variant; do not try to satisfy both with one layout.

## 8. Contextual and progressive controls

| Technique | Product | Rule |
|---|---|---|
| Layout changes with game state | TAK: Yakuza switches to a battle layout; Scarlet Nexus shows only A in cutscenes; Minecraft Dungeons adds controls as abilities unlock [S25][S1] | If the fork can only bind one profile per game, use *folders* to approximate state groups and let the user switch profiles from the in-game menu |
| Contextual buttons | CoD shows knife/revive/open-door/weapon-swap only when relevant [S8] | Keep ≤ 1 contextual slot per thumb; never put a contextual action under a biomechanical thumb rest |
| Folders / radial for rare keys | VoidLink `FOLDER`, `LABELEDFOLDER`, slide-hold folder, double-tap to move `OSWV:578,693,2467,2770`; Steam radial menus with nesting [S15]; TAK joystick-as-radial [S1] | Any key pressed < 1 per 30 s belongs in a folder/radial, not on the canvas `[INFERENCE]` |
| Progressive disclosure | Apple HIG: "use progressive disclosure to make layouts cleaner" [S6] | First-run profile shows movement + fire only |
| Auto-dock | VoidLink docks idle widgets to a 70×17 pt edge sliver with its own opacity `OSWV:3858-3862`; Steam hides overlay after 10 s idle [S16] | Auto-dock only secondary controls; primary fire must never dock |

## 9. Hold vs toggle

| Use | Mode | Evidence |
|---|---|---|
| ADS while a fight lasts | hold (or one-tap ADS) | Apex "One-Tap ADS and Fire" setting [S12]; CoD "1-tap ADS" per weapon [S8] |
| Crouch, walk, gyro on/off, auto-fire | toggle | VoidLink `tapToToggle` `OSB.h:98-104`; gyro press-toggle `XC` "Press-toggle… You can have 2 buttons for both press-toggle & hold-down switch" |
| Sprint | threshold + optional latch | [S2]; `OSWV:379-380` |
| Rare menu keys | toggle with visible state | XAG: avoid prolonged holds [S5]; VoidLink button-mode docs [S26] |
| Actions with no visible in-game state | hold | `[INFERENCE]` — a toggle the player cannot see is a hidden failure |

XAG is explicit: "Avoid requiring key/button holds for extended periods" and provide toggles/auto-holds [S5]. VoidLink supports both per key: `walkKeyActionType`/`sprintKeyActionType` are `hold` or `toggle` `OSWV:371-374`.

## 10. Haptics

| Rule | Evidence |
|---|---|
| Haptic on **state transitions only** (sprint threshold, toggle on/off, folder open), not on every touch | Apple HIG: "Avoid overusing haptics"; "use haptics consistently… clear causal relationship" [S7] |
| Use impact style matched to meaning; light for threshold ticks, rigid/heavy for destructive or blocking actions | HIG impact families [S7]; VoidLink maps style index to `vibrationOn` `OSWV:764-775` |
| Haptics improve control accuracy: on-screen tactile feedback improved joystick centre and direction accuracy; tactile virtual buttons cut task time 22% | [S23][S24] |
| Make it optional and never mask a missing visual state | HIG "Make haptics optional" [S7] |
| VoidLink only fires haptics for combo pads and direction pads by default | `OSWV:688` sets `hasHapticFeedback` from combo strings / `DPAD` |

Note: haptics are generated on the iPhone (`UIImpactFeedbackGenerator`, `OSWV:220`); `HapticContext` was dropped in the port (`PORT.md` "Dropped"), so nothing is forwarded to the PC.

## 11. Avoid requiring simultaneous presses

XAG: avoid multi-finger simultaneous presses; where unavoidable provide a less demanding alternative; allow "Short Press and Drag" to cancel [S5]. In practice:

- Replace "LB+RB to crouch" with one button carrying both actions (TAK `action: ["leftBumper","rightBumper"]` [S4]; CoD contextual knife [S8]; Scarlet Nexus "dedicated button for simultaneous actions" [S25]).
- Replace "hold stick + press B to sprint" with a stick threshold (§6.4).
- Keep 4-finger layouts *optional*; the 2-thumb layout must not contain a mandatory chord.

## 12. iOS edges: notch, Dynamic Island, home indicator

| Hazard | Rule | Evidence |
|---|---|---|
| Side inset 59 pt (notch / Dynamic Island side) | Keep all interactive controls out of it; background art may extend under | [S6] "Respecting the safe area is essential…"; `PRESET:107-108,118-120` |
| Bottom 21 pt home-indicator strip | Nothing tappable in the bottom 21 pt; a swipe-up dismisses the app | `PRESET:102`; [S6] |
| System edge swipes vs edge controls | VoidLink's own edge-slide gestures reserve an "untouchable screen edge area" that widens with sensitivity | `XC:3654` |
| Widget canvas does **not** clamp to safe area | VoidLink widgets are positioned by stored centre; only pickers use safe-area guides (grep of `safeAreaInsets` in `VLTouch/Widgets` = none) | code |
| Varying devices | Re-layout on rotation/resize; TAK requires testing multiple screen sizes | [S6]; [S1] "Compatibility with various device types" |

Practical margin: **≥ 59 pt from each side, ≥ 21 pt from the bottom, ≥ 8 pt from the top** (top has no inset in landscape but the overlay's own top bar lives there — `PRESET:124-126` reserves a 200×76 pt band).

## 13. Anti-patterns

| Anti-pattern | Why it fails | Fix |
|---|---|---|
| One giant layout for every game | TAK: each game needs different controls; "Eliminate all unnecessary buttons" [S1] | Template + per-game delta (`PORT.md` per-game binding) |
| Primary button at the screen edge | no room to drag-aim [S1] | move inboard by ≥ 1 button |
| Full-opacity opaque buttons | occludes targets; thumbs already occlude [S22] | 0.35–0.55 fill |
| Buttons < 10 mm | error rate climbs steeply [S21] | 90 pt for primary |
| Two adjacent buttons < 8 mm apart | mis-taps during fast play [S21][S5] | 60 pt gap |
| Gyro always-on for a new player | highest skill ceiling but fails in vehicles; pros only [S1] | ADS-only default, always-on as an option |
| Look pad covering the right third of the screen | blocks the target area and the game's own HUD | pad ≤ 30% of screen width `[INFERENCE]` |
| Required simultaneous presses | excludes many players [S5] | compound buttons / thresholds |
| Toggle with no visible state | player cannot tell if auto-fire is on | state on the button (`tapToToggle`) |
| Widgets under the notch/home indicator | unreachable or triggers system gesture | respect insets (§12) |

## 14. Rules for a profile designer

1. **Rank every action by frequency before placing anything; delete everything not needed.** Primary on the wheels, secondary outer, rare in folders, menus in the upper band. [S1]
2. **Design the 2-thumb layout first; claw is a separate variant.** Two simultaneous touch inputs are the baseline; four fingers are an upgrade, never a requirement. [S1][S5][S25]
3. **Primary actions ≥ 90 pt (15 mm); secondary 64–80 pt; nothing tappable under 44 pt.** [S5][S21][S27]
4. **Leave ≥ 60 pt (10 mm) between targets and ≥ 12 pt of empty gap.** [S5][S21]
5. **Keep the middle third of the screen free of controls** — nobody's thumb reaches there without a claw. [S1][S20]
6. **Respect insets: 59 pt sides, 21 pt bottom, and never place a control where VoidLink's edge-swipe gesture lives.** [S6][PRESET:118-120][XC:3654]
7. **Fill opacity 0.35–0.55, labels 0.8–0.9, pressed state ≥ 0.7, and never 0-opacity active buttons.** [S8][OSWV:184,197,199,200]
8. **Move + camera get the two inner wheel slots; one control per thumb, no exceptions.** [S1]
9. **Prefer compound controls to extra buttons**: fire-that-aims, stick-that-sprints, tap-to-fire look pad. [S1][S2][S3]
10. **Place aim+fire inboard with empty screen above it, so the drag has room.** [S1][S9b]
11. **Fire on touch-down for weapons, on touch-up for menus.** [S5]
12. **Sprint/run thresholds at 60–75% deflection, with a haptic tick and a visual state on the knob.** [S2][S8][OSWV:377-380,1789-1792]
13. **Hold for transient states (ADS), toggle for latched states (crouch, walk, gyro, auto-fire), and always show the state.** [S12][S8][OSB.h:98-104][S5]
14. **Auto-fire/auto-aim are opt-in accessibility options, not defaults.** [S5][S9][OSWV:212-213]
15. **Use gyro as the fine-aim channel and the pad for coarse turns**; default to ADS-only, offer always-on. [S1][S8][S11][PROF.h:44-58]
16. **Anything pressed less than once per 30 s goes into a folder or radial, not on the canvas.** [S15][OSWV:693]
17. **Keep contextual buttons to one per thumb and never under a rest position.** [S8][S25]
18. **Haptics: transitions only, optional, matched in intensity to the action.** [S7][S23]
19. **Auto-dock/fade only secondary controls; keep the primary cluster always visible.** [S16][OSWV:3858-3862]
20. **Match the output to the game's input API**: mouse-relative look for mouse-look games, right stick for gamepad-native ones. [PORT.md sink table][CM:148-155]
21. **Avoid mandatory simultaneous presses; provide a chord-free alternative for every one.** [S5][S25]
22. **Ship a template plus a per-game delta; never copy another player's exact layout** — device, grip and hand size change the answer. [S1][S8][S13]
23. **Test the profile with 2, 3 and 4 fingers, and on the smallest supported screen** before shipping it. [S1] "Compatibility with various device types"; [S6]
24. **Keep a southpaw/mirror variant cheap** — CoD exposes left/right swapping explicitly; mirrored layouts double the addressable audience. [S8]

## 15. Sources

- [S1] Microsoft, *A designer's guide to building touch controls* — https://learn.microsoft.com/en-us/gaming/gdk/_content/gc/system/overviews/game-streaming/building-touch-layouts/game-streaming-tak-designers-guide
- [S2] Microsoft, *Joystick* (TAK reference) — https://learn.microsoft.com/en-us/gaming/gdk/docs/reference/system/touchadaptationkit/controls/game-streaming-touch-joystick
- [S3] Microsoft, *Touchpad* (TAK reference) — https://learn.microsoft.com/en-us/gaming/gdk/docs/reference/system/touchadaptationkit/controls/game-streaming-touch-touchpad
- [S4] Microsoft, *Button* (TAK reference) — https://learn.microsoft.com/en-us/gaming/gdk/docs/reference/system/touchadaptationkit/controls/game-streaming-touch-button
- [S5] Microsoft, *Xbox Accessibility Guideline 107: Input* — https://devdocs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-107-input
- [S6] Apple, *Human Interface Guidelines — Layout* — https://developer.apple.com/design/human-interface-guidelines/layout
- [S7] Apple, *Human Interface Guidelines — Playing haptics* — https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- [S8] Activision, *Getting a Grip on the Call of Duty: Mobile Controls* — https://blog.activision.com/call-of-duty/2019-10/Getting-a-Grip-on-the-Call-of-Duty-Mobile-Controls
- [S9] Epic, *Getting Started — Fortnite for Mobile* — https://www.epicgames.com/fortnite/en-US/news/getting-started---fortnite-for-mobile (HUD presets, Auto Fire / Tap Anywhere / Dedicated Button; page returns 403 to fetchers, quoted from search index)
- [S9b] Community Free Fire drag-headshot guides — https://killarnation.com/guides/one-tap-headshot-settings/ , https://ff-kipas.org/en/how-to-drag-headshot-ff/
- [S10] Epic Support, *How do I customize my HUD in Fortnite on Mobile?* — https://www.epicgames.com/help/en-US/c-Category_Fortnite/c-Fortnite_Gameplay/how-do-i-customize-my-hud-in-fortnite-on-mobile-a000090860
- [S11] Epic, *Gyro Aiming and Flick Stick come to Fortnite* — https://www.fortnite.com/news/gyro-aiming-and-flick-stick-come-to-fortnite-in-v19-30-more-controller-options
- [S12] Apex Legends Mobile settings coverage — https://www.digitaltrends.com/gaming/apex-legends-mobile-best-settings/ , https://beebom.com/how-enable-disable-gyroscope-apex-legends-mobile/
- [S13] PUBG Mobile patch notes and claw-layout guides — https://www.pubgmobile.com/webplat/info/news_version3/35372/60662/60663/60724/60725/m22521/202209/922032.shtml (recommended-layout + share codes) , https://bittopup.com/article/PUBG-Mobile-45-Finger-Claw-Setup-Guide-2025-Gyro
- [S14] Genshin Impact Wiki, *Controls* — https://genshin-impact.fandom.com/wiki/Controls
- [S15] Valve, *Radial Menus* (Steamworks) — https://partner.steamgames.com/doc/features/steam_controller/radial_menus
- [S16] Steam Community, *Steam Link Touch Controller Guide* — https://steamcommunity.com/sharedfiles/filedetails/?id=1888830141
- [S17] Moonlight docs, *Setup Guide* — https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide
- [S18] Winlator input-controls documentation — https://winlator.dev/connect-controller/ , https://androidpctv.com/winlator-android-windows-emulator/
- [S19] GameHub (GameSir) — https://gamehub.xiaoji.com/en/ , https://gamehubemulator.onl/blog/guide-to-customization-of-gamehub-emulator/
- [S20] Steven Hoober / A List Apart, *How We Hold Our Gadgets* — https://alistapart.com/article/how-we-hold-our-gadgets/
- [S21] UXmatters, *Common Misconceptions About Touch* — https://www.uxmatters.com/mt/archives/2013/03/common-misconceptions-about-touch.php
- [S22] Zaman & Teather, *Touchscreens vs. Traditional Controllers in Handheld Gaming* — https://www.csit.carleton.ca/~rteather/pdfs/fp2010.pdf
- [S23] *Preliminary Study on the Effects of On-Screen Tactile Feedback on Virtual Joystick Interaction* — https://dl.acm.org/doi/10.1145/3764687.3769934
- [S24] *Tactile virtual buttons for mobile devices* (22% faster with tactile feedback) — https://www.researchgate.net/publication/221517061_Tactile_virtual_buttons_for_mobile_devices
- [S25] Microsoft, *Putting Your Game at the Center with Xbox Touch Controls* — https://developer.microsoft.com/en-us/games/articles/2021/12/putting-your-game-at-the-center-with-xbox-touch-controls/
- [S26] VoidLink feature docs (button modes, folders) — https://voidlink.yuque.com/org-wiki-voidlink-znirha/fa3tgr/tvlizqfgoidrn20o , https://voidlink.yuque.com/org-wiki-voidlink-znirha/fa3tgr/it0qruyul6be8gr1
- [S27] Apple, *Human Interface Guidelines — Accessibility* (44x44 pt minimum target) — https://developer.apple.com/design/human-interface-guidelines/accessibility
- [S28] NVIDIA, *GeForce NOW touch controls* — https://blogs.nvidia.com/blog/geforce-now-thursday-oct-20 , https://support-shield.nvidia.com/geforce-now-user-guide/On-Screen_Controls.htm
- [S7b] Community CoD HUD opacity guidance — https://item4gamer.com/blog/hud-settings-call-of-duty-mobile/
