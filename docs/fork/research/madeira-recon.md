<!-- Scout report captured 2026-10-30 by the lead from MadeiraRecon. Facts as of that date; [INFERENCE] marks unverified claims. -->

# Madeira (willfaust/Madeira) — investigation report

Read-only web investigation at **`main` = `c2c1b03a9e36ef986c980b9eae3c14d05a372db1`** (2026-10-29T03:15:24Z), repo https://github.com/willfaust/Madeira (GPL-3.0, 2978★, 372 forks, 97 open issues, size 220,854 KB ≈ 216 MB pack).

---

## 1. Upstream state

**Default branch:** `main`. Submodule pins at that commit (`.gitmodules`):

| Path | Repo / branch | Pin |
|---|---|---|
| `FEX` | willfaust/FEX `ios-port-2607` | `6fb1b5071febda1fca17b9284a074ffcc8a9e334` |
| `wine` | willfaust/wine `madeira-lgpl` | `df1c5ea51e194937ac204bc3120922dc56a61bec` |
| `dxmt` | willfaust/dxmt `ios-port` | `05876bb6738b879f1da92a1f7f7e118ef2158d96` |
| `madeira-dock` | willfaust/madeira-dock `main` | `8c98616a68c45857c1b0fd1bc58268249b3aa3aa` |

**Last 30 commits** (`/commits?per_page=30`, newest first):

| SHA | Date | Subject |
|---|---|---|
| `c2c1b03` | 10-29 03:15 | Keep post-merge CI checks for TLS objects and Steam recovery (#483) |
| `d4bde29` | 10-29 01:23 | **Build missing runtime components and verify complete IPAs (#476)** |
| `e96065a` | 10-28 05:52 | **Record wave 5's pull requests as merged** (ours-merge of #461 #462 #443 #264) |
| `c66a84f` | 10-28 05:24 | Settings catalog: regenerate for wave 5 |
| `14eb290` | 10-28 05:23 | Added self refresh + SideInstaller compatibility (#264) |
| `da57c5d` | 10-28 05:22 | Epic: combine game downloads and cloud saves (#443) |
| `7ed32a9` | 10-28 05:19 | **Graphics backends, Direct3D and build packaging (#462)** (squash of #454 #455 #444 #456) |
| `a9ce1d4` | 10-28 05:18 | **Runtime, input, launch settings and diagnostics (#461)** (squash of #447 #452 #453 #445 #459 #465 #469 — includes “touch-editor controls, game presets, INI editor”) |
| `3ab3f9a` | 10-28 05:00 | Record wave 4's pull requests as merged |
| `9d95eb5` | 10-28 04:57 | Add external drive support (#464) |
| `fed7f6a` | 10-28 04:54 | docs: Detroit iPad menu/scene (#458) |
| `16b3382` | 10-28 04:54 | ntdll: reserve enough startup storage for long working directories (#471) |
| `0b4eee5` | 10-28 04:54 | steam: avoid automatic cloud transfers for unreadable local saves (#472) |
| `7fe5284` | 10-28 03:00 | Merge runtime launch and game fixes into the graphics review stack |
| `54fc65a` | 10-28 02:58 | Merge PR #469: game handoff, suspension, Black Ops II settings |
| `a8957d7` | 10-28 02:52 | Merge PR #465: preserve UTF-8 launch working directories |
| `c89fc32` | 10-28 01:51 | Dock: steam://run request starts that game in the next app run |
| `de1725d`, `2d385a6`, `e4a0607`, `246517a`, `7ebcc2a`, `66f84a7` | 10-28 01:40 | Recover missing CI caches and finish clean IPA bootstrap (6×) |
| `28ce806` | 10-28 00:57 | ntdll: decode UTF-8 initial working directory |
| `d25fead`, `d7ad811`, `90b133b`, `ccdb471`, `7118714` | 10-28 00:26 | Use the shared Madeira IPA CI and build checks (5×) |
| `586582d` | 10-28 00:25 | Include the inner FEX recipe in its cache key |

**Releases / tags** (`/releases`, `/tags`) — all four are on the same commit as the tag:

| Tag | Commit | Published | Assets |
|---|---|---|---|
| v0.1.3 | `4e9d45a74294cd820120791c4b3f2b79adf4fc70` | 2026-10-03T16:49Z | `Madeira-0.1.3.ipa` 145,554,426 B, sha256 `71e900cb…`, 25,975 downloads |
| v0.1.2 | `3d5796bf86892c8d90f849123fc2310303ecc4b6` | 2026-10-03T05:43Z | IPA 142,471,753 B |
| v0.1.1 | `ca3183ea3dfb0fd706aff1bea2abb871b5d27aec` | 2026-10-02T08:54Z | IPA 142,473,173 B |
| v0.1.0 | `3ccbf9b8bc97f7a59727d10bb9e98717d2c91d64` | 2026-10-01 (asset 09:22Z) | IPA 142,433,883 B |

**Newest stable IPA = v0.1.3 (`4e9d45a`)** — and it is 26 days and ~all of waves 3–5 behind `main`. `MARKETING_VERSION = 0.1.3`, `CURRENT_PROJECT_VERSION = 4` in the project even at HEAD.

**Big refactors / build-breaking changes**
- Waves 3/4/5 are “ours”-merges that land *squashed* mega-PRs (`a9ce1d4` #461, `7ed32a9` #462, `da57c5d` #443) — thousands of lines in one commit, no per-change history. Rebasing a fork across them is effectively a re-port.
- `d4bde29` (#476) reworks the build to *build and verify missing runtime components* (`tools/build/runtime-components.py verify all|ipa`, `runtime-build.json` in the bundle) and pins FEX deps in cross builds. This is the single biggest build-system change; it also adds `dockhost.exe` and DLL-farm items that are otherwise git-ignored.
- Ten CI-only commits (cache keys, shared CI workflow, TLS-object/Steam-recovery checks) — noise for a forker, but they mean **CI is green at HEAD**: all 13 check runs on `c2c1b03` concluded `success` (`app`, `llvm`, `fex`, `i386`, `runtime (windows|dock|zink|mesa-d3d12|kosmickrisp|vulkan-pe|moltenvk)`, `plan`; `reuse` skipped). The run’s only surviving artifact is `Madeira-ipa` (206,395,460 B, expires 2027-01-27).

**iOS 27 specifics**
- `.github/workflows/build.yml:18`: “xcode-27: the ntdll unix side uses iOS 27 SDK fields (`rusage_info_v6.ri_page_wait_time_mach`)” — builds need the iOS 27 SDK.
- v0.1.3 notes: in-app JIT pairing on iOS 27 (“Pair with Madeira”, PIN), keeps `MADEIRA ... JITHelper` appex; `MADEIRA_PAD_*`, LocalDevVPN shortcut caveat on cellular.
- v0.1.2 notes: shipped-shader library was Metal 4.1-only and broke iOS 26; now targets Metal 3.1.
- README: “iPhone on **iOS 26 or later**, the only version Madeira currently runs on reliably.”

---

## 2. Build

**One command** (`BUILDING.md`): `git clone --recurse-submodules … && cd Madeira && ./tools/build-ipa.sh` → `dist/Madeira.ipa`. `JOBS=` overrides parallelism; `VC_REDIST_X64=<path>` avoids the Microsoft runtime download.

**Script chain** (`tools/build-ipa.sh`, 74 lines): `brew install cmake ninja meson pkg-config autoconf automake libtool bison flex sevenzip llvm` + PATH to brew bison/llvm → `git submodule update --init --recursive` → `tools/check-prefix-template.sh` → `tools/build/setup-llvm-mingw.sh` → `build-wine.sh` → `build-fex-ios.sh` → `build/rppairing-ios/build.sh` (Rust + `aarch64-apple-ios`) → `build-freetype-ios` → `build/gnutls-ios` → `build/ffmpeg` → `build/wineserver` → `build/ntdll-unix` → `build/win32u-unix` → `build-llvm-ios.sh` → Metal toolchain download → `build-shader-headers.sh` → `build-dxmt-ios.sh` → `prepare-vcruntime.sh` → `stage-licenses.sh` → `runtime-components.py build all` → `build/wine-i386/build.sh` (skipped on CI) → `package-ipa.sh`.

**Prereqs:** macOS + Xcode + CLT, Homebrew, Git, Rust via rustup (`BUILDING.md`). Toolchains downloaded/pinned: llvm-mingw **20260421** ucrt macos-universal (sha256 `bd85a397…3cb3f7`, `tools/build/setup-llvm-mingw.sh`), LLVM **llvmorg-15.0.7** cloned shallow by `tools/build/build-llvm-ios.sh` and built **twice** (host `llvm-tblgen`, then iOS `LLVMPasses LLVMBitWriter`). Not in repo: Metal Shader Converter 4.0b2 pkg (hash pinned), `app/Madeira/x86_64-vcruntime/`, optional Wine Mono 11.0.0 (`build/wine-mono/fetch.sh`, 41.6 MB DL / 228 MB unpacked).

**Time:** “several hours on a typical Mac” first run (LLVM twice + FEX); later runs “finish in minutes”/incremental. CI `timeout-minutes: 360`.

**Disk:** **not documented anywhere** (grep of BUILDING.md/README/build scripts/workflows: no figure). [INFERENCE] Budget ≥25–30 GB for a first build: llvm-project shallow clone + two LLVM build trees, `FEX/build-ios`, `wine/build-macos` + `wine/build-arm64ec`, `toolchains/*`, `build/*/obj`, `dist/` + Xcode DerivedData; CI completes the full build on GitHub-hosted `xcode-27` runners (~14 GB free on hosted macOS images), so the build itself likely peaks under ~20 GB. **22 GB free is marginal at best.** Caches are the ignored directories themselves (`toolchains/`, `FEX/build-ios`, `wine/build-*`, `dxmt/build-*`, `build/*/obj`, `.runtime-cache/` in CI); `.gitignore` shows which link inputs are *not* in git (`app/Madeira/lib{ntdll_unix,wineserver,win32u_unix,dxmt_combined,rppairing}.a`, `libav*.a`).

**Can prebuilt toolchain/artifacts skip the LLVM build?** Not by a supported download: CI uses `actions/cache` + same-run artifacts (native stages keep artifacts for **1 day**), and `build-llvm-ios.sh` only trusts `<repo>/toolchains/llvm-ios-build/.madeira-cache.sha256`. llvm-mingw is the only freely downloadable prebuilt toolchain. The Xcode target itself links no LLVM archives (`project.pbxproj` frameworks: `libFEXCore/libFEXCore_Base/libJemallocLibs`, `libfmt`, `libcephes_128bit`, `libxxhash`, `libwineserver`, `libntdll_unix`, `libwin32u_unix`, `libdxmt_combined`, `libgnutls/hogweed/nettle`), so LLVM is only needed to build **DXMT’s combined archive + shader headers**. Practical trims for a 22 GB disk: skip `wine-i386`, the `mesa-d3d12`/`vulkan-pe`/`moltenvk` runtime components and OpenGL backends, and consider replacing `build/dxmt-ios` with a cached `libdxmt_combined.a` if you can obtain one — otherwise the LLVM build is unavoidable and it is the long pole.

**Bundle ID / team / entitlements (free account)**
- `app/Madeira.xcodeproj/project.pbxproj`: `MADEIRA_BUNDLE_IDENTIFIER = com.willfaust.madeora`, `PRODUCT_BUNDLE_IDENTIFIER = $(MADEIRA_BUNDLE_IDENTIFIER)`, `DEVELOPMENT_TEAM = V8NU3FX3TL`, `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = "Apple Development"`, app `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, JITHelper appex target `26.0` with bundle id `$(MADEIRA_BUNDLE_IDENTIFIER).JITHelper`. Both values are overridable at build time (`xcodebuild … MADEIRA_BUNDLE_IDENTIFIER=… DEVELOPMENT_TEAM=…`).
- `app/Madeira/Madeira.entitlements` (424 B): `com.apple.developer.kernel.extended-virtual-addressing`, `com.apple.developer.kernel.increased-memory-limit`, `com.apple.security.cs.allow-jit`, `get-task-allow` — all `true`. `docs/BUILDING.md` warns that a wildcard profile without the two kernel capabilities “can sign an app which installs but cannot reserve the WoW64 guest window”, and that on an M1 iPad the entitlements changed the task map **17 GB → 63 GB**. v0.1.1’s notes instead describe free-Apple-ID installs as having “a smaller (63 GB) address map” — the two statements conflict; [INFERENCE] a free profile cannot carry those two kernel entitlements, so a free-ID build behaves like the un-entitled 17 GB case unless you use something like GetMoreRam (BCD documents exactly that trick).
- IPA is ad-hoc signed with the entitlements so SideStore/AltStore/Sideloadly re-sign it; the JITHelper appex must be kept (“If your sideloader asks whether to keep app extensions, keep them”).

---

## 3. Touch controls and the input sink into Wine (focus item)

**Verdict: two completely different sinks.** Pad buttons go to a *virtual XInput pad* published by the app and polled by Wine’s `xinput`; everything else (keys, mouse) is *injected as hardware input events* into Wine’s message queue. Touch controls can drive either (or both), per control.

### 3a. Gamepad sink (the one a VoidLink-style layer must drive)

```
TouchPadView (UIKit, multi-touch)         app/Madeira/TouchGamepad.swift
  └─ GamepadInput.shared.touch(owner:control:value:)      app/Madeira/GamepadInput.swift
      └─ TouchGamepadState.update/sample  → GamepadSample{buttons,lt,rt,lx,ly,rx,ry}
          └─ GamepadInput.sample()  (merges physical GCController pads, 250 Hz timer, 4 ms)
              └─ winios_gamepad_set_state(slot, &winios_gamepad)   app/Madeira/Winios/WiniosGamepad.c
                  └─ win32u: ios_gamepad_query(index, op, buffer)   build/win32u-unix/driver_ios.c:3039
                      (NtUserCallTwoParam_GetGamepadState / NtUserGamepadOp_*)
                          └─ Wine xinput.dll XInputGetState/Capabilities → game
```

Key names/lines:
- `app/Madeira/GamepadInput.swift` (31,589 B, **576 lines**): `GamepadInput.shared`, `touch(owner:control:value:)`, `configureTouch(controls:acceptingInput:)`, `reserveSessionSlot(touchControls:)` (`MADEIRA_PAD_EARLY_SLOT`), `beginPadSession()` (`MADEIRA_PAD_MODE = xinput|hid|dualsense|generic`), `sample()`, `axis(_:)`, `trigger(_:)`, 4 slots, 250 Hz `DispatchSourceTimer`, `GamepadSample.merge(physical:touch:)` with XInput dead zones 7849/8689.
- `app/Madeira/TouchGamepad.swift` (8,678 B, ≈250 lines): `GamepadSample`, `TouchPadAction.buttons` (name→XINPUT bit mask: A `0x1000` … D↑ `1`, LB `0x0100`, Menu `0x0010`, View `0x0020`, Guide `0x0400`), `TouchPadAction.sample(_:x:y:)`, `TouchGamepadState` (per-finger owner UUID holds, merge, `reserved`, `acceptingInput`), `TouchPadSurface`/`TouchPadView` (UIKit, multi-touch, cancellation, `releaseAll`).
- `app/Madeira/Winios/WiniosGamepad.h` (6,596 B): `struct winios_gamepad` (20 B, `C_ASSERT` in driver), `winios_gamepad_set_state/get_state`, vibration (`winios_gamepad_set_vibration`, `_set_rumble_caps`), battery (`winios_gamepad_set_battery`), plus `struct winios_hidpad` (48 B, DualSense/generic HID served by `build/wineserver/hidpad_ios.c`) and `winios_hidpad_output` for lightbar/triggers.
- `build/win32u-unix/driver_ios.c:2819-3160`: `ios_gamepad_query`, `ios_gamepad_foreground`, caps masked `0xf3ff`, `NtUserGamepadOp_{State,Caps,SetVibration,Foreground,Battery}`. `WiniosGamepad.c` = 6,864 B (≈230 lines) snapshot + mutex + packet numbers.

### 3b. Key/mouse sink (touch buttons, key sticks, key-and-mouse pad mode)

`winios_post_key(vk, down)` and `winios_pointer(x, y, flags, data)` (`app/Madeira/Winios/Winios.m:959` and `:2634`) push `WINIOS_EV_KEY`/`WINIOS_EV_MOUSE` onto a queue drained in `pProcessEvents`, i.e. Wine `send_hardware_message` → `WM_KEYDOWN`/`WM_CHAR`/mouse messages (`ContentView.swift:127` documents the chain). Direct helpers also exist: `winios_post_touch_*` (left-button only, `ContentView.swift:408`), `winios_direct_cursor_*`, `winios_cancel_text`.

Touch dispatch in one place — `app/Madeira/ContentView.swift`, `TouchControlButton.press(_:)` (~line 4655):
```swift
case .key(let vk):   winios_post_key(vk, down ? 1 : 0)
case .mouseLeft:     winios_pointer(0, 0, down ? 0x0002 : 0x0004, 0)
case .mouseRight:    winios_pointer(0, 0, down ? 0x0008 : 0x0010, 0)
case .keyboardToggle: if down { MetalBackedView.toggleKeyboard() }
case .pad: break      // TouchPadSurface owns pad presses
```
Key sticks (`.joystickWASD` / `.joystickArrows`) are 8-way with edge-triggered `winios_post_key` (`applyStick`, ~4647). `PadKeyboardMouse.swift` (12,589 B) turns a physical pad into keys/mouse through the same calls.

### 3c. Where the touch UI lives, and its size

| File | Bytes | Role |
|---|---|---|
| `app/Madeira/ContentView.swift` **3854–4908** | 264,542 (≈4,900 lines total) | `ControlAction` (`.none/.key/.mouseLeft/.mouseRight/.joystickWASD/.joystickArrows/.keyboardToggle/.pad(String)`), `TouchControl{id,nx,ny,scale,action,padBinding?,locked?}`, `TouchControlsModel` (working copy `madeira-controls.json`), `TouchControlsHost` (separate window-level `ControlsWindow` above SwiftUI — z-order lives outside SwiftUI), `TouchControlsOverlay`, `TouchControlButton`, `MappingPanel` (keyboard / controller tabs) |
| `app/Madeira/TouchControlPresets.swift` | 29,538 (≈800) | `ControlPreset{id,name,controls,zones?}`, `ControlPresetStore` (file `madeira-control-presets.json`), built-in `builtin.xbox` layout, `ControlPresetsModel`, `ControlLayoutMenu`, save/delete semantics |
| `app/Madeira/GestureZones.swift` | 22,088 (≈600) | `GestureZone{x,y,w,h,kind∈{stick,swipe,look},stick,swipe,tap,sensitivity,locked}`, `GestureZonesModel`, `GestureZoneView` (floating stick / swipe→pulse / look=mouse), `GestureZonesLayer` + 8 resize handles, `GestureZonePanel`, `LayerMove`/`LayerButtons` |
| `app/Madeira/TouchGamepad.swift` | 8,678 (≈250) | pad sample + UIKit touch surface (above) |
| `app/Madeira/GamepadInput.swift` | 31,589 (576) | the publisher/sink (above) |
| `app/Madeira/Winios/WiniosGamepad.c/.h` | 6,864 / 6,596 | C snapshot ABI with win32u and the wineserver |

≈5,000 lines of Swift in the touch stack, and **~1,050 of them are inside the 4,900-line `ContentView.swift` monolith** — the single worst thing to extend for a VoidLink-style widget layer.

**Layout editor:** yes. Landscape overlay → layout button (or Session menu → *Controller layout* / *Touch controls*) → built-in Xbox layout, `Custom Layout N`, create/delete; edit mode gives drag/pinch/grid snap/`locked`, `MappingPanel` (controller tab assigns A/B/X/Y, dpad, LB/RB, L3/R3, Menu/View/Guide, LT/RT, LS/RS; keyboard tab assigns VK/mouse), `padBinding` (control↔physical pad), zone boxes with handles and a settings panel. Docs: `docs/CONTROLLERS.md` (575 lines) is the authoritative description of semantics (merge, reservation, menu suspension, `MADEIRA_TOUCH_MOUSE`, `MADEIRA_CONTROLS_XBOX_DEFAULT`, HID mode, DualSense output).

**Per-game config**
- Global: `Documents/madeira.cfg`, `key = value`, `env.NAME = value` (`build/madeira_cfg.h` is the native reader; `MadeiraConfig.swift`).
- Per game: `app/Madeira/GameProfiles.swift` — `Application Support/GameConfigs/<%016llx of lowercased windowsPath>.cfg`, same syntax, exported as `MADEIRA_CFG_GAME`; its keys win over `madeira.cfg`. Any runtime switch (FEX/DXMT/D3D12/env) can be set per game with no rebuild.
- Per-game UI state lives in the library entry JSON: `controlLayout`, `controllerBinds`, `padMouseVertical` (`docs/CONTROLLERS.md`), plus `GameIniFiles.swift` (25,164 B, INI editor), `GameRecommendations.swift` (38,742 B) + `GameRecommendationsApply.swift` (11,624 B) recommended settings, and `ConfigCatalog.generated.swift` (250,386 B) — the generated catalog of every switch.
- LuaJIT/DXVK/vkd3d selection is also cfg keys (`d3d9 = wined3d`, `d3d11 = dxvk`, `d3d12 = vkd3d`, `vulkan = …`).

---

## 4. Notable forks / siblings

| Project | Relation | State | What it changes |
|---|---|---|---|
| **thebcd69/bcd-games** (BCD) https://github.com/thebcd69/bcd-games — 429★, GPL-3.0, created 10-19, pushed 10-29 | re-upload (not a GH fork) of Madeira + private tree | HEAD `05e9f6f` “BCD 0.1.623”, **upstream base `279fd0f83170` (2026-10-14)**; i.e. ~2 weeks behind `main`, before waves 4/5 | Biggest divergence: own launcher (Steam QR/Guard, **GOG**, **Epic**, DLC, background downloads), **auto-tune** after crashes, remote `recommended` settings lists (v16/v18), `MadeiraMemoryHost` target, and a **factorized touch system: `BCDTouchCore` (18,224 B), `BCDTouchControls` (23,144), `BCDTouchEditor` (23,528), `BCDTouchLayouts` (22,549), `BCDTouchLive` (15,958), `BCDTouchLook` (6,977), `BCDTouchLookViews` (6,375), `BCDTouchFeelModel` (3,986), `BCDTouchExtrasLive` (11,487), `BCDPadModel` (15,738) ≈ 132 KB / ~3.4k lines** replacing the ContentView monolith. Build: own workflow `build-ipa.yml` + `BCD-source.tar.xz` per release. **Licence caveat:** its own files are **GPL-3.0 only** with GPL §7 additional terms (`LICENSE-BCD.md`) requiring a visible “Includes work from BCD by thebcd69 …” credit on About/Credits/Licences, kept copyright lines and “modified” markers — so borrowing `BCDTouch*` is possible but drags an attribution obligation into your fork. |
| **kuscholar/iDeck** https://github.com/kuscholar/iDeck — 252★, GPL-3.0-or-later, created 10-24, pushed 10-30 | separate app “powered by Madeira” (topics: madeira, fex, wine) | alpha v0.1.3-alpha.4 (build 99); tracks Madeira closely | Steam Big Picture/Deck UI, six-green-check launcher, own docs; runtime = Madeira. `Mi-Yomi/iDeck-BCD` is an iDeck variant on BCD. |
| **tylerkaska112/Porthole** https://github.com/tylerkaska112/Porthole (1.0.0) | app around Madeira runtime | iOS 18+ (tested 18–27); MileStone-style storefronts Steam/Epic/GOG/itch; touch + controller | Own library/storefront code; no indication of deeper runtime divergence. |
| **Aettarrass-sys/madeira-bcd** https://github.com/Aettarrass-sys/madeira-bcd — 29 forks, created 09-27, last push 09-30 | the original “bcd my fork of madeira” code drop (predecessor of bcd-games) | stale (Sept 30) | Same lineage; superseded by `bcd-games`. |
| **QuarkyUp/madeira** https://github.com/QuarkyUp/madeira | plain fork, 0★, pushed 10-14 | identical tree to upstream at fork time | Nothing. |
| **byeCl0ud/Madeira-build** https://github.com/byeCl0ud/Madeira-build | plain fork, pushed 09-26 | ~1 month behind | Nothing beyond upstream. |
| **playportdev/playport** https://github.com/playportdev/playport — 698★, GPL-3.0, created 10-01 | independent Windows-on-iOS app, not a Madeira fork | active (pushed 10-29) | Own Swift app + 32/64-bit support; not a source of Madeira patches. |
| **PennixRv/VoidLink-moonlight-ios** https://github.com/PennixRv/VoidLink-moonlight-ios — GPL-3.0, branch `Integration`, pushed 2026-03-27 | the Moonlight-iOS fork whose touch widget system you want to port | 0★ mirror-style repo; verify against the canonical VoidLink source | [INFERENCE] its widgets ultimately emit Moonlight controller/keyboard/mouse packets (LiSend*), so a port means keeping VoidLink's widget model/editor and *re-targeting the sink* to `winios_gamepad_set_state` + `winios_post_key`/`winios_pointer` — the two sinks in §3a/§3b. |

---

## 5. Licences (for borrowing)

| Component | Licence | Source |
|---|---|---|
| Madeira app/tooling | **GPL-3.0-or-later** + **Madeira Converter Exception v1** (GPL §7; adopted 2026-09-24, permits linking Apple Metal Shader Converter/system frameworks) | `LICENSE` = `COPYING` (35,150 B), `LICENSE-EXCEPTION.md` |
| `madeira-d3d12` (in-repo) | same GPL-3.0-or-later + exception | README licensing table |
| willfaust/wine (`madeira-lgpl`) | **LGPL-2.1-or-later**, upstream `wine-11.4` baseline with Madeira patches reapplied; an older GPL-3.0-relicensed Wine tree is explicitly *not* used | `LICENSE-EXCEPTION.md` "Scope and authority", `docs/wine-lgpl-provenance.md` |
| willfaust/FEX, willfaust/dxmt | upstream MIT for upstream code; **Madeira's changes GPL-3.0-or-later + exception** (`LICENSE-MADEIRA.md` in each) | README + exception doc |
| willfaust/rpmalloc (nested in FEX) | upstream 0BSD; Madeira changes GPL-3.0-or-later + exception | same |
| willfaust/madeira-dock | GPL-3.0-or-later + exception | README |
| Bundled (GnuTLS/Nettle/GMP/FFmpeg LGPL config, StikJIT/StikDebug/idevice) | own licences; MS VC++ runtime and Wine Mono **not** redistributed | `THIRD-PARTY-NOTICES.md`, `LICENSES/` |

Bottom line for you: Madeira's Swift touch code is GPL-3.0-or-later — free to reuse in a GPL fork. BCD's `BCDTouch*` is GPL-3.0-**only** + §7 attribution, so if you copy it you must show “Includes work from BCD by thebcd69 …”, keep its headers and mark files modified.

---

## 6. Recommendation: which base to fork from

**Fork from `main` at `c2c1b03a9e36ef986c980b9eae3c14d05a372db1` (or pin `d4bde29` if you want to exclude the last CI-only commit).** Use the v0.1.3 IPA (`4e9d45a`) as the behavioural A/B baseline, not as the code base.

Why, in order of weight:
1. **Build reproducibility is equal-or-better at HEAD, not worse.** Nothing anywhere in the repo publishes linkable artifacts (`.a`) — the native libs are all git-ignored — so a tag buys you no shortcut. Meanwhile `d4bde29` (#476) *added* the only end-to-end check that a build is complete (`runtime-components.py verify all` / `ipa`, `runtime-build.json`), and HEAD’s CI is green on all 13 checks including that verifier, plus a downloadable IPA artifact (expires 2027-01-27).
2. **Your actual work sits on the newest input layer.** The sink you must drive (`winios_gamepad_set_state` + `winios_post_key`/`winios_pointer`, `GamepadInput.swift`) is what waves 4/5 just reworked (`a9ce1d4`: “runtime, input, launch settings”, touch-editor controls, game presets, INI editor, phone experiments). Forking a month-old tree forces you to re-merge giant squashes later; forking HEAD lets you *add* files beside the touch stack instead.
3. **iOS 27.** v0.1.3 already has in-app pairing, but HEAD is the only tree built and CI-verified with the iOS 27 SDK (ntdll `rusage_info_v6` probe) — which is your device.
4. **Deterministic pins.** Record the four submodule SHAs above in your fork's README; that, not the app tag, is what makes builds reproducible.

Caveats to plan for:
- **Nothing between v0.1.3 (Oct 3) and HEAD has shipped to users** — four weeks of unreviewed squash-merges. First task after forking: build + smoke-test (Steam sign-in, one D3D11 game, one D3D12 game, touch pad) before writing touch code.
- **22 GB free disk is the real constraint.** Trim `tools/build-ipa.sh` to LLVM(iOS) + FEX + wine unix libs + FFmpeg + FreeType + rppairing + DXMT + dock + `xcodebuild`, i.e. drop `wine-i386`, `mesa-d3d12`, `vulkan-pe`, `moltenvk`, OpenGL backends; keep `JOBS=3–4` on 16 GB RAM.
- **Free Apple ID:** set `DEVELOPMENT_TEAM`/`MADEIRA_BUNDLE_IDENTIFIER`, keep the JITHelper appex, and expect the two kernel entitlements in `Madeira.entitlements` to be unsupported by a free profile (17 GB-style address map) unless you use GetMoreRam-style entitlement injection; JIT continues via StikDebug or the iOS 27 in-app pairing.
- **Structure:** don't extend `ContentView.swift`. Mirror BCD's factorization (`TouchCore` / `Controls` / `Layouts` / `Editor` / `Live` / `Look`) for your VoidLink-style layer, and drive it through the two existing sinks — `GamepadInput.touch(owner:control:value:)` for pad state and `winios_post_key`/`winios_pointer` for keys/mouse — so no Wine-side change is needed. If you do borrow BCD's files, honour its §7 attribution or re-implement from Madeira's GPL-3.0-or-later code instead.
