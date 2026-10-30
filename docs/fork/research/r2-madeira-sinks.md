<!-- Scout report R2MadeiraSinks captured 2026-10-30 by the lead. Sources: Madeira fork/main 67bd667, VoidLink fa42805, BCD 05e9f6f. [INFERENCE] marks unverified claims. -->

# Madeira input sinks vs VoidLink `LiSend*` — capability report

## Summary

| Question | Answer |
|---|---|
| Can every VoidLink `LiSend*` call be served by an existing Madeira API? | **Yes for gamepad, relative/absolute mouse, buttons, wheel (V+H), keyboard, DS4 touch, motion.** No new Wine code is needed. |
| Gaps (all Swift-side) | (1) paddles / MISC / touchpad-click have no sink in XInput mode (touchpad-click exists only in DualSense HID mode; paddles + MISC exist in neither); (2) analog trigger 0–255 and raw stick values need a whole-state path, not `touch(owner:control:value:)`; (3) `winios_hidpad`'s `touch*`/`motion`/`gyro`/`accel` fields are **never populated** by the app (`hidpad_reports.h` already renders them) — populating them is pure Swift work. |
| Wine-driver changes needed | **No.** Optional only: extra HID button bits for paddles/MISC if native semantics are wanted. |

---

## 1. Per-call mapping

| VoidLink call | Madeira equivalent (exact args) | Support | Evidence | Missing |
|---|---|---|---|---|
| `LiSendMultiControllerEvent(idx, mask, buttons, lt, rt, lx, ly, rx, ry)` via `ControllerSupport` → `setButtonFlag/clearButtonFlag/updateLeftTrigger/updateRightTrigger/updateFinished` | `GamepadInput.shared.touch(owner: UUID, control: UUID, value: GamepadSample?)` then internal `winios_gamepad_set_state(Int32(slot), &winios_gamepad)`; `GamepadSample{buttons: UInt16, lt/rt: UInt8, lx/ly/rx/ry: Int16}` | **Partial** | `GamepadInput.swift:153-160`, `:349-483` (esp. `:480-482`), `TouchGamepad.swift:2-9`, `WiniosGamepad.h:11-19`, `driver_ios.c:3039+` (`ios_gamepad_query` op 0) | `activeGamepadMask` (no analogue — slots connect individually); paddle/MISC/touchpad bits; per-control analog values; whole-state push |
| `LiSendMouseMoveEvent(dx,dy)` | `winios_pointer(dx, dy, 0x0001, 0)` — equals `HardwareInput.shared.postRelative(Int32,Int32)` (`HardwareInput.swift:1454-1464`) | **Yes** | `Winios.h:63-66`, `Winios.m:2636-2651`, `driver_ios.c:130-158` (flags forwarded verbatim to `INPUT_MOUSE`), `queue_ios.c:2314-2328` (`cursor.x + dx` when `MOVE` set and `ABSOLUTE` clear), `:2343` (RawInput gets `x - cursor.x`, i.e. pre-clip delta) | nothing (dx/dy already Int16-sized in VoidLink; `ContentView.swift:743-744` clamps to ±30000) |
| `LiSendMousePositionEvent(x,y,w,h)` | `winios_pointer(X, Y, 0x0001\|0x8000, 0)` with X,Y in **guest desktop pixels** — convert `x/w*W`, `y/h*H` using `winios_screen_size(&w,&h)` (`IOSDisplayShim.h:29`) or `winios_desktop_point_from_window` | **Partial (needs unit conversion)** | `queue_ios.c:2314-2321` (absolute = raw screen pixels, *not* 0–65535), `driver_ios.c:140-143`, `ContentView.swift:340-357` mapping helpers | VoidLink's normalized stream coords are not the same space; also desktop vs game-window mapping differs (`ContentView.swift:346-357`) |
| `LiSendMouseButtonEvent(action, BUTTON_LEFT/MIDDLE/RIGHT/X1/X2)` | `winios_pointer(0,0,flags,data)`: L 0x0002/0x0004, R 0x0008/0x0010, M 0x0020/0x0040, X1/X2 0x0080/0x0100 with `data` 1/2 | **Yes** | `HardwareInput.swift:304-316` (exact canonical table), `queue_ios.c:2286-2302` (message table incl. XBUTTON), `:2121-2128` (raw X1/X2), `Winios.m:836-842` | nothing |
| `LiSendScrollEvent` / `LiSendHighResScrollEvent` / `…HScrollEvent` | `winios_pointer(0, 0, 0x0800, UInt32(bitPattern: delta))`; horizontal `0x1000`, same `data` | **Yes** | `HardwareInput.swift:451-471` (notch = 120, `WHEEL`/`HWHEEL` constants, sign convention), `:1613-1618`, `Winios.m:841`, `queue_ios.c:2300-2301`, `:2116-2120` (raw `RI_MOUSE_HORIZONTAL_WHEEL`) | nothing; `data` is the signed wheel delta in the **high word** (`wparam = data << 16`, `queue_ios.c:2285`), so pass ±120·n (Madeira's own high-res path quantizes to 120s) |
| `LiSendKeyboardEvent(vk, action, modifiers)` | `winios_post_key(Int32 vk, Int32 down)` (down 1/0) | **Yes, after expanding modifiers** | `Winios.h:42-44`, `Winios.m:961-963`, drain `:997-998`, `driver_ios.c:189-255` | no modifier argument: post `VK_SHIFT`/`VK_CONTROL`/`VK_MENU` (0x10/0x11/0x12) or L/R variants as separate keys, as Madeira already does (`ContentView.swift:1167-1170`, `Library.swift:5498-5499`) |
| `LiSendKeyboardEvent2(vk, act, mods, SS_KBE_FLAG_NON_NORMALIZED)` | none | **No** | only used from `StreamView.m:2028-2030` (dropped in the port) | no scancode-only entry point; `winios_post_key` is VK-based and derives the scan code (`driver_ios.c:217-225`) |
| `LiSendControllerTouchEvent(idx, DOWN/MOVE/UP, pointerId, x, y, pressure)` | `winios_hidpad_set_state(&hid)` with `hid.touch[i]=1`, `hid.touch_x[i]=x*1919`, `hid.touch_y[i]=y*1079`; UP = `touch[i]=0` | **Partial — plumbing exists, app never fills it** | `WiniosGamepad.h:39-53`, `hidpad_reports.h:347-358` (clamped 0–1919/0–1079, finger id + down bit), `tests/host/check-hidpad.py:206-217`, docs `CONTROLLERS.md:240-247` ("the touchpad reports no finger") | app-side population; requires `MADEIRA_PAD_MODE = hid\|dualsense` (player 1 only, read once at session start: `GamepadInput.swift:43-57`, `:100-135`); `pressure` has no field |
| `LiSendControllerMotionEvent(idx, ACCEL/GYRO, x,y,z)` | `winios_hidpad_set_state` with `hid.motion=1`, `hid.gyro[3]` (16/deg·s), `hid.accel[3]` (8192/g) | **Partial — HID only, unimplemented** | `WiniosGamepad.h:26-53`, `hidpad_reports.h:337-342`, feature 0x05 calibration `:423-428`; XInput path has no motion (`driver_ios.c:2819-2831` = `XINPUT_GAMEPAD` only); no `CMMotionManager`/`GCMotion` use anywhere in `app/Madeira` | sensor source (VoidLink reads `GCController.motion`), app-side publish; XInput mode can never carry motion |
| Rumble back to the phone | `UIImpactFeedbackGenerator(...).impactOccurred()` (widget-local) or CoreHaptics; game-driven rumble already exists via `PadOutput.m` (`winios_gamepad_set_vibration` → `winios_pad_output_set_notify`) | **Yes for widget feedback**; game rumble is read-only input, not a widget API | `ContentView.swift:4658-4661` (`hapticsEnabled` gate), `TouchControlsModel.hapticsEnabled` `:3999`; game→phone: `PadOutput.m:320-500`, `WiniosGamepad.h:81-95,124-129` | VoidLink's `HapticContext.m` (CoreHaptics continuous/transient players, `:22-25,65-81,141-179`) ports verbatim; no Madeira coupling needed |

---

## 2. Gamepad details (`touch(owner:control:value:)`)

**Accepted control names** (`TouchPadAction.buttons`, `TouchGamepad.swift:35-41`; `supported` at `:42-44`):

| Name | Bits/effect | Notes |
|---|---|---|
| `A B X Y` | 0x1000 / 0x2000 / 0x4000 / 0x8000 | XInput A/B/X/Y |
| `D↑ D↓ D← D→` | 0x0001 / 0x0002 / 0x0004 / 0x0008 | |
| `LB RB` | 0x0100 / 0x0200 | |
| `L3 R3` | 0x0040 / 0x0080 | |
| `Menu` / `View` | 0x0010 / 0x0020 | Start / Back |
| `Guide` | 0x0400 | **not in `XINPUT_CAPABILITIES` mask `0xf3ff`** (`driver_ios.c:3095`), and bits 10–11 excluded → game-dependent (`CONTROLLERS.md:29-30`) |
| `LT` / `RT` | `lt`/`rt` = **255 always** | no analog value via this API (`TouchGamepad.swift:52-53`) |
| `LS` / `RS` | `lx/ly`, `rx/ry` | direction = `(x,y)/max(1,hypot)` then `Int16(v*32768 or 32767)` (`:45-47`, `TouchGamepad.swift:11-15`); x right, y up |

**Value ranges**: `GamepadSample.axis` → full signed range −32768…32767 (`TouchGamepad.swift:11-15`); triggers 0…255 (`GamepadInput.swift:341-344`); buttons bitmask is only 16 bits (`WiniosGamepad.h:13`, `C_ASSERT sizeof == 20` at `driver_ios.c:2838`).

**Merging (two levels)**
1. Per-owner holds inside `TouchGamepadState`: OR buttons, `max` triggers, "strongest" stick vector with lexical tie-break (`TouchGamepad.swift:89-108`). One hold per **owner UUID**; `value:nil` releases that owner (`:84-87`).
2. Physical vs touch: `GamepadSample.merge` OR buttons, `max` triggers, touch stick only when the physical stick is inside its XInput dead zone (7849 left / 8689 right) (`TouchGamepad.swift:20-32`, applied at `GamepadInput.swift:446-456`).

**Whole-state set?** Not through Swift. `winios_gamepad_set_state(slot, &state)` *is* a full state write (buttons/triggers/sticks/`connected`, NULL = disconnect, packet incremented on change — `WiniosGamepad.c:12-28`, header contract `:21-23`), and it is Swift-visible via the bridging header. But `GamepadInput.sample()` re-publishes complete snapshots on every `touch()`, `configureTouch`, activity change and (if a physical pad is present) a 4 ms timer (`GamepadInput.swift:378-483`, `:371-376`), so a raw C write is clobbered whenever the producer runs. Robust integration = feed widget state through `touch()` (or add one control-UUID-per-value convention), not a side-channel C write.

**Gating**: `touch` is `@MainActor` and drops input unless `MADEIRA_TOUCH_XINPUT != 0` (`:19-23,153-154`); it also drops non-nil values while the app is inactive (`:156`) and requires each `control` UUID to be in the allowed set installed by `configureTouch(controls:)` (`TouchGamepad.swift:84-85`, `:66-82`); slot 0 connects only when `touchState.connected` (`GamepadInput.swift:379,383-390`).

**Not representable at all**: `PADDLE1..4_FLAG`, `MISC_FLAG`, and (in XInput mode) `TOUCHPAD_FLAG`. Names exist in VoidLink (`CommandManager.swift:110-130`; low-bit values cross-checked in `ControllerUtil.swift:56-59`; paddle/MISC numeric values are moonlight-common-c constants not checked out here → `[INFERENCE]`). In DualSense HID mode touchpad click is the only one with a sink: `WINIOS_HIDPAD_TOUCHPAD 0x00010000` (`WiniosGamepad.h:33`), set today only from a physical DualSense (`GamepadInput.swift:533-536`).

---

## 3. Mouse / pointer specifics

- **Relative motion is fully supported**: `winios_pointer` forwards `flags`/`data` unchanged into `INPUT_MOUSE` (`driver_ios.c:130-145`); the wineserver treats `MOUSEEVENTF_MOVE` without `MOUSEEVENTF_ABSOLUTE` as a delta from its own cursor (`queue_ios.c:2314-2328`) and feeds RawInput `x - cursor.x` **before** clip clamping (`:2343`), so `WM_INPUT`/DirectInput mouse-look never stalls at a screen edge (documented at `HardwareInput.swift:58-67`, and in-tree at `ContentView.swift:715-751` with the same reasoning, `ml641`).
- **Pointer lock** is an iOS/GameController concept (`HardwareInput.pointerLockAvailable`, `.pointerLocked`, `HardwareInput.swift:704,730`); it only decides whether the app posts **absolute** (pointer follows the finger) or **relative** (lock / program hides its cursor) — `HardwareInput.swift:1628-1637`, `PointerPolicy`. For widgets, simply post relative; no interaction with that machinery is required.
- **Absolute moves**: `MOUSEEVENTF_MOVE|MOUSEEVENTF_ABSOLUTE`, coordinates are **screen pixels** (`queue_ios.c:2316-2320`), and only then does the app also move the drawn arrow (`Winios.m:2650`).
- **Wheel**: `data` becomes `wparam = data << 16` → the signed high word of `WM_MOUSEWHEEL`/`WM_MOUSEHWHEEL` and `RAWMOUSE.usButtonData` (`queue_ios.c:2285`, `:2116-2120`). One notch = 120; sign: `+` = away from user / to the right (`HardwareInput.swift:448-471`).
- **Buttons** work with the canonical `MOUSEEVENTF_*` table already written in the app (`HardwareInput.swift:304-316`), including X1/X2 via `mouseData` 1/2.

---

## 4. Keyboard specifics

| Aspect | Behaviour | Evidence |
|---|---|---|
| VK range | any `int` truncated to `unsigned short` (0–0xFFFF); **no allow-list / filtering table** | `Winios.m:997-998` → `driver_ios.c:189` |
| Scan code | derived per event: `NtUserMapVirtualKeyEx(vk, MAPVK_VK_TO_VSC_EX, layout)` | `driver_ios.c:217` |
| Extended bit | automatic: `scan & 0xe000` or nav keys (arrows/Prior/Next/End/Home/Insert/Delete) get `KEYEVENTF_EXTENDEDKEY`; `MADEIRA_NAV_KEYS_E0=0` disables the heuristic | `driver_ios.c:160-181`, `:226-232` |
| Modifiers | not a parameter — post modifier VKs as their own down/up; Wine synthesises generic SHIFT/CONTROL/MENU from L/R | `Winios.h:42-44`, `HardwareInput.swift:26-31`, `ContentView.swift:1166-1171` |
| Delivery | queued, drained FIFO in `pProcessEvents`, serialized by one drain lock | `Winios.m:966-1004` |
| Scan-code-only / `LiSendKeyboardEvent2` | impossible (VK-only API) | `Winios.m:961`, `driver_ios.c:189-192` |
| Unicode text | separate path `winios_try_post_text` (not needed for widgets) | `Winios.h:46-52` |

---

## 5. HID / DualSense (touchpad, gyro, mode switch)

- Mode: `env.MADEIRA_PAD_MODE` = `hid` / `dualsense` / `generic`; read **once** at `beginPadSession()` before the wineserver starts; exports `MADEIRA_HIDPAD`; player 1 leaves XInput unless `MADEIRA_HIDPAD_XINPUT=1` (`GamepadInput.swift:43-57,100-135`, `docs/CONTROLLERS.md:189-215`).
- ABI: `struct winios_hidpad` (48 B) already carries `buttons` (low 16 bits = XINPUT bits, plus `TOUCHPAD/MUTE/L2/R2`), `touch[2]`, `touch_x/y[2]`, `gyro[3]`, `accel[3]`, `motion`, battery (`WiniosGamepad.h:31-55`, size assert text `:54`).
- Report builder already implements both: motion at `hidpad_reports.h:337-342` (`motion==0` ⇒ flat, 1 g on Y), touch at `:347-358` with DualSense finger-id/down semantics and clamping; verified by `tests/host/check-hidpad.py:206-217`. Generic HID identity drops touch/mute/L2 bits (`check-hidpad.py:333-335`).
- App currently sets only: connected, buttons, sticks, triggers, L2/R2/Touchpad bits from a **physical** pad, battery (`GamepadInput.swift:521-548`). `motion`, `touch*`, `gyro`, `accel` are never written ⇒ "sensors report the pad lying flat, the touchpad reports no finger" (`docs/CONTROLLERS.md:247-248`).
- Consequences for the port: `DS4TOUCH` widget works **only** in a `dualsense` session and only after the widget layer writes those fields; `LiSendControllerMotionEvent` likewise needs the widget/MotionHandler layer to supply sensor data.

---

## 6. Threading and pre-session safety

| Entry point | Thread requirement | Safe before a Wine session? |
|---|---|---|
| `winios_post_key` | **any** thread; mutex ring, never blocks (`Winios.m:920-930`) | Yes (no crash); events **stay queued** and are delivered when the first Wine thread pumps. `winios_session_reset` does **not** flush the queue (`Winios.m:1369-1372`) ⇒ post-session-start stale input is a real hazard |
| `winios_pointer` | any thread (called from `HardwareInput`'s own `mouseQueue`, `HardwareInput.swift:806-807`); one `dispatch_async` to main when the game-dialog cursor was showing (`Winios.m:2639-2643`) | Yes, same queue caveat; nothing requires a window |
| `winios_gamepad_set_state` / `winios_hidpad_set_state` | any thread, mutex, no callbacks under lock (`WiniosGamepad.h:21-23,74-79`; `WiniosGamepad.c:12-28,53-70`) | Yes; stored state simply persists until a reader exists |
| `GamepadInput.touch(owner:control:value:)` | **main actor** (`GamepadInput.swift:153`) — it hops to the `madeira.gamepad` serial queue itself | Yes, but `sample()` only publishes when a producer runs; no Wine needed |
| `winios_gamepad_set_vibration` / pad-output notify | any thread; notify handler must hop to main (`WiniosGamepad.h:124-129`) | Yes |

Ring capacity is 256 events with silent drop when full (`Winios.m:865,920-929`; the comment claims "drop the oldest" but the code drops the **newest** — cosmetic, but widget mouse pads at 120 Hz while a game is not pumping messages will lose input).

---

## 7. Swift-visible declarations (bridging header)

`app/Madeira/Madeira-Bridging-Header.h:5-9` imports `IOSDisplayShim.h` (`winios_screen_size`, `:29`), `Winios/Winios.h` (which itself `#include "WiniosGamepad.h"`, `Winios.h:24`), `Winios/WiniosCursor.h`, `PadOutput.h`. Therefore these are directly callable from Swift today:

```c
void winios_post_key(int vk, int down);                                   // Winios.h:44
void winios_pointer(int x, int y, unsigned int flags, unsigned int data);  // Winios.h:66
void winios_cursor_move(int x, int y);                                    // Winios.h:70
void winios_post_touch_down/move/up(int x, int y);                        // Winios.h:38-40
void winios_gamepad_set_state(int index, const struct winios_gamepad *);   // WiniosGamepad.h:22
int  winios_gamepad_get_state(int index, struct winios_gamepad *out);      // :23
void winios_hidpad_set_state(const struct winios_hidpad *state);          // :74
void winios_gamepad_set_vibration(int index, uint16_t left, uint16_t right);// :90
void winios_screen_size(int *w, int *h);                                  // IOSDisplayShim.h:29
void madeira_pad_output_configure(int xinput, int hid);                   // PadOutput.h
```
Constants already visible: `WINIOS_HIDPAD_TOUCHPAD/MUTE/L2/R2` (`WiniosGamepad.h:33-36`), battery enums (`:97-117`).

---

## 8. Verdict

**Wine-driver changes: NO** for every `LiSend*` call the widget port needs. The driver already forwards raw `MOUSEEVENTF_*` flags + `mouseData` (so relative move, absolute move, all five buttons, V/H wheel all work untouched), takes arbitrary VKs and derives scan codes/extended bits, and the DualSense HID report builder already encodes touch and motion from the existing 48-byte snapshot.

Minimal work list (all in `app/Madeira/VLTouch/…`, no C/Wine edits):

| # | Work | Blocked call |
|---|---|---|
| 1 | `LiSendMultiControllerEvent` → map `ControllerSupport` flags to `GamepadInput.shared.touch(owner:control:value:)`; owner = per-`ControllerSupport` UUID, control = one embedded control UUID per logical pad, `configureTouch(controls:)` at layout load; ignore `activeGamepadMask` (or map to `value:nil` per slot) | 1 |
| 2 | Analog path for triggers/sticks that `touch()` cannot express: add a Madeira-side control vocabulary (e.g. `LT` with value) or one `VLSink.setPad(slot:GamepadSample)` inside `GamepadInput` that merges through `TouchGamepadState` | 1 |
| 3 | Decide paddles/MISC/touchpad-click: map `TOUCHPAD_FLAG` to `WINIOS_HIDPAD_TOUCHPAD` (DualSense mode only); paddles/MISC → keyboard fallback or no-op (needs new HID button bits in the descriptor **only if** native semantics are required) | 1 |
| 4 | `LiSendMouseMove/Position/Button/Scroll` → `winios_pointer` with the tables in §3; `Position` converts stream-normals through `winios_screen_size` | 4–8 |
| 5 | `LiSendKeyboardEvent` → `winios_post_key`, expand `modifiers` into VK down/up pairs; `LiSendKeyboardEvent2` → not needed (only `StreamView` uses it) | 9 |
| 6 | `LiSendControllerTouchEvent` → new `GamepadInput` HID publish path filling `hid.touch/touch_x/touch_y` (scale ×1919/×1079); requires `dualsense` session, player 1 | 10 |
| 7 | `LiSendControllerMotionEvent` → fill `hid.motion/gyro/accel` from `GCController.motion`; XInput mode has no lane, so gate on HID mode | 2 |
| 8 | Widget haptics: keep `HapticContext.m` and gate on `TouchControlsModel.hapticsEnabled`-style flag | — |

Optional, only if native paddle/MISC support is ever required: extend `struct winios_hidpad.buttons` beyond the current 4 high bits and add usages to `build/hidpad/hidpad_reports.h` descriptors (both generic and DualSense) — that is the sole would-be cartesian product between this port and the Wine side, and the widget layer can avoid it entirely.