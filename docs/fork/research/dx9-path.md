# How Madeira runs Direct3D 9 games (32-bit and 64-bit)

Scope: the D3D9 end-to-end path in this fork (`willfaust/Madeira` c2c1b03 + fork fixes), the four
D3D9 routes, what each needs, which to use, DX9-era compatibility (owned library first), the cfg
recipe, and the systematic blockers. Evidence is file:line, a device log under `/tmp/g2/dev`, or a
link. `[INFERENCE]` marks a claim I could not confirm from code or a report.

## 1. The pipeline at a glance

1. **Launch.** `app/Madeira/WineProcessBridge.m` reads the target's `IMAGE_FILE_HEADER.Machine` off
   disk; i386 ⇒ `ios_main_image_i386 = 1`, `syswow64` → `app/Madeira/i386-windows`, and the session
   is *armed* for a guest window (`docs/WOW64.md:114-140`).
2. **Guest window.** A 32-bit process gets a 4 GB-aligned reservation `[B, B+4G)` in the one Mach
   task; guest address `a` lives at host `B + a` (`docs/WOW64.md:25-52`). A 64-bit session reserves
   nothing.
3. **CPU.** Only guest code is translated: FEX's WOW64 module (`libwow64fex.dll` installed as
   `xtajit.dll`, `build/fex-wow64/build.sh:1-20`, `FEX_IOS_HOST_BUILD` turns on
   `ENABLE_GUEST_WINDOW`). Wine's `wow64.dll`/`wow64win.dll` run native aarch64.
4. **Unix calls.** Every statically linked unix library has a `*_unix_call_wow64_funcs` table that
   converts the guest pointers inside the 32-bit argument block (`docs/WOW64.md:141-153`,
   `build/ntdll-unix/virtual_ios.c` `load_builtin_unixlib`).
5. **D3D9 module choice.** `syswow64\d3d9.dll` is DXMT's i386 **shim**; `system32`/`sysx64` hold
   DXMT's ARM64EC frontend. `d3d9 = emulated|native|wined3d` (madeira.cfg, or a game's own lines)
   decides which code answers `Direct3DCreate9` (`docs/WOW64.md:155-191`;
   `app/Madeira/ContentView.swift:2974-2992` exports it as `MADEIRA_D3D9`).
6. **Renderer.** DXMT draws D3D9 with Metal directly; `wined3d` draws through opengl32 → the winios
   WGL driver → Zink on MoltenVK.
7. **Presents.** DXMT's D3D9Ex/swapchain path hands frames to winios (the same compositor D3D11/12
   use), so a DX9 game looks like any other Madeira game.
8. **Memory.** Guest memory, the JIT pool, the swap tier and the iOS kill line are the same for DX9
   as for D3D11 (see the memory report); DX9 adds one extra cost: the *emulated* frontend crosses
   from guest to host on every D3D9 call (measured 5,540 calls/frame, `dxmt/src/d3d9/d3d9_census.hpp:44-48`).

### 1a. The i386 farm: built by CI, not tracked by git

The premise "the i386-windows farm which CI does not build" is **half true**. It is not *tracked*
(`.gitignore:204-205` keeps only `.gitkeep`; `docs/BUILDING.md:107` "The i386 farm is not tracked"),
but this repo's CI **does build it**: job `i386` in `.github/workflows/build.yml:161-206`
(`build/wine-i386/build.sh`), the `app` job `needs: [.., i386, ..]` (line 257) and restores it from
cache/artifact (lines 288-315). The local tree has 726 files in `app/Madeira/i386-windows`
(`d3d9.dll`, `d3d9shim.dll` 114,688 B; `d3d9-emulated.dll` 2,318,336 B; `d3d9-wined3d.dll`
282,624 B; `opengl32.dll` 1,703,936 B; 420 ARM64EC and 146 aarch64 files beside them).
`build/wine-i386/build.sh:161-166` installs exactly the four d3d9 names.

## 2. The four D3D9 routes

| Route | What runs | 32-bit | 64-bit | Needs | Verdict |
|---|---|---|---|---|---|
| **`emulated`** (default; `d3d9` unset) | i386 shim forwards 12 exports to `d3d9-emulated.dll`, DXMT's D3D9 frontend built for i386 and translated by FEX; reaches Metal through winemetal's 32-bit table | yes | – | `d3d9.dll`+`d3d9shim.dll`+`d3d9-emulated.dll` in the farm, i386 `winemetal.dll`, `libdxmt_combined.a` with winemetal's wow64 table | **the working route**: Portal 2 60 fps, Batman AA answers adapter caps |
| **`native`** | the shim binds its own unixlib (`d3d9shim`) and the frontend runs as native ARM64 code in `libdxmt_combined.a` (`dxmt_madeira_native` objects) | yes | – | shim + `dxmt_d3d9_unix_call_wow64_funcs` (`virtual_ios.c:12226-12238`) + `d3d9_native_window_teardown` hook | **not recommended**: Portal 2 dies right after `CreateDevice` at `RIP=0` (#192); Imperial Glory tried both (#383); no positive device report |
| **`wined3d`** | Wine's `d3d9.dll` (shipped as `d3d9-wined3d.dll`) on wined3d/OpenGL: opengl32 → winios WGL → Zink on MoltenVK | yes | yes | both farms' `d3d9-wined3d.dll`+`wined3d.dll`, `gl-backend = zink`, Mesa/MoltenVK in `gl/`, **and opengl32's wow64 thunks built from the patched tree** | **fallback only**; broken in builds made from this tree (§6.1). Upstream device test: menus and 32-bit D3D9 games render, heavy scenes stall on synchronous Metal shader compiles (#353) |
| **DXVK d3d9** | – | – | – | – | **does not exist**: DXVK is built with D3D8/D3D9 off (`docs/DXVK.md:23-24`: "Vulkan is x64-only here (no i386 winevulkan) and most D3D9 programs are 32-bit") |

Route plumbing: `WineProcessBridge.m:750-806` (`madeira_d3d9_wined3d_wanted`,
`madeira_link_d3d9_wined3d*`) re-points `system32`/`sysx64`/`syswow64` links for one session and sets
`MADEIRA_D3D9=wined3d`, called at `WineProcessBridge.m:2059-2060`. `MADEIRA_GL_EXTENSIONS_MAX` is
forced to 0 for that session (same block: the 3072-byte cut would hide extensions from wined3d).

### 2a. What each D3D9 route needs, concretely

- `emulated`: nothing beyond the shipped farm. `MADEIRA_D3D9_X64=0` opts *64-bit* programs out of
  DXMT's ARM64EC frontend (`dxmt/src/d3d9/d3d9.cpp:42-49`), i.e. back to "fails to create".
- `native`: opt-in only. The shim's own log text still names `Documents/madeira-d3d9.txt`; the
  actual knob is `d3d9` in madeira.cfg / the game's config (`dxmt/src/d3d9shim/d3d9shim_main.c:120-146`,
  `dxmt/src/d3d9shim/README.md:18-23`). `d3d9shim` is matched by export name, not by file name
  (`virtual_ios.c:12226-12238`).
- `wined3d`: `d3d9 = wined3d` (global or per game) **plus** `gl-backend = zink` and the patched
  opengl32 unix side. Without Zink, `Direct3DCreate9` returns NULL ("no usable context",
  `WineProcessBridge.m:799-803`); without the patched thunks, a 32-bit program dies at opengl32 init
  (§6.1). TF2's report is exactly the first failure ("Failed to get a GL context /
  Direct3DCreate9 called -> d3d9_init FAILED", #424).
- Export gaps (both DXMT routes): `Direct3DCreate9On12`, `PSGPError`, `PSGPSampleTexture` absent
  (`docs/WOW64.md:188-190`); an exe importing one of them fails to load d3d9.
- Capability ceiling of the DXMT frontend, from this device: vs/ps **3.0**, `MaxVertexShaderConst=256`,
  `MaxTexture=16384x16384`, `+HWTNL`, `-POW2` (`/tmp/g2/dev/main6.txt:12015-12017`). D3D9 games that
  need SM3+ or a "vs_4_0" D3D9 path do not exist (D3D9 tops out at 3.0), so this is the full API level.

### 2b. Which is recommended

1. **32-bit DX9: leave `d3d9` unset (emulated).** This is the only route with rendered frames on
   device in this corpus (Portal 2, Castle Crashers, Alan Wake in #446; Batman AA reaches adapter
   caps here).
2. **64-bit DX9: nothing to choose** — the ARM64EC DXMT `d3d9.dll` is the default and the only one
   that creates (`docs/WOW64.md:184-190`, PR #242: "a 64-bit launcher that draws its UI with
   Direct3D 9 now shows its text and buttons").
3. `wined3d` only for a fixed-function/pipeline quirk that DXMT gets wrong, and only once the GL
   thunks are built patched. `native` only as an experiment.

## 3. Compatibility table — owned games first

API/bitness: PCGamingWiki `direct3d versions` and `windows 32/64-bit exe`; gamepad: Steam store
category (Full/Partial). Status: device log or upstream report; `untested` means no report found in
willfaust/Madeira, thebcd69/bcd-games or kuscholar/iDeck (searches listed in §8).

| # | Game (AppID) | API | Bits | Pad | Status | Required settings | Evidence |
|---|---|---|---|---|---|---|---|
| 1 | **L.A. Noire** (110800) | D3D9c **and** D3D11; `-dx11` forces D3D11, D3D9 is the default (renderer also selectable in-game) | 32 game; the launcher path needs the **64-bit Rockstar Games Launcher** since v2663 | Full in game, **not** in the launcher | **untested upstream**; highest-risk of the owned set: every digital copy requires Rockstar Games Launcher/Social Club | Start `L.A.Noire\final\pc\LANoire.exe` directly (bypass `LANLauncher.exe`/RG Launcher) with `-dx11` (PCGW: better compatibility/performance) and `-windowed`; args also go in `commandline.txt` next to the exe; `-joysticktype 1` for the mixed pad/keyboard bug. If the RG Launcher cannot be bypassed, use the RDR2 launcher list (§4) — but GTA IV's report shows that path failing today (#151) | PCGW L.A. Noire; no issue in willfaust/Madeira or thebcd69/bcd-games |
| 2 | **Batman: Arkham Asylum GOTY** (35140) | D3D9c only | 32 | Partial | **fails today**: D3D9 loads, adapter caps/modes answered, then dies on the game's own `ReadProcessMemory` of a reserved page (`Exception frame is not in stack limits`) **before `CreateDevice`** — no game frame | `env.MADEIRA_NO_GL=1` (else opengl32 kills it first), standard list; try `env.MADEIRA_LAA=0` | `/tmp/g2/dev/main6.txt:9424,12014-12042,12664-12793`; `/tmp/g2/dev/bat.txt:6160` |
| 3 | **Batman: Arkham City GOTY** (200260) | D3D9c + D3D11 (`AllowD3D11=False`) | 32 | Partial | **fails**: UE3 early-init deadlock, 0 presents, 7/7 runs (#446); BCD's later runs die in a 64-bit x87 conversion instead | `env.FEX_X87REDUCEDPRECISION=0` (attempt), `env.MADEIRA_TLS_CLEAR_OWN_PROCESS=1` (BCD, absent here) | #446; BCD `tests/fixtures/autotune/batman-arkham-city-2026-10-21.expect` |
| 4 | **Batman: Arkham Origins** (209000) | D3D9c + D3D11 | 32 | Full | untested; same UE3 generation as #3 ⇒ expect #3's blockers | as #3 | [INFERENCE] |
| 5 | **Alan Wake** (108710) | D3D9c | 32 | Full | **works**: playable, exclusive fullscreen with `windowed=0` (#446 "working reference") | standard list; `windowed=0` for exclusive fullscreen | #446 |
| 6 | **Alan Wake's American Nightmare** (202750) | D3D9c | 32 | Full | untested; same Remedy engine as #5 | as #5 | [INFERENCE] |
| 7 | **Dark Souls II** (236430) | D3D9c | 32 | Full | untested for the vanilla exe; the 64-bit SOTFS has a black title screen/crash (#492), and BCD measured 379 s of play with the self-modifying-image line | standard; if the exe is 64-bit add `env.MADEIRA_X64_IMAGE_NOCOPY=1` | #492; BCD `AutoTuneRules.generated.swift` rule `x64-image-smc-nocopy` |
| 8 | **Dead Space (2008)** (17470) | D3D9c | 32 | Full | untested end-to-end; its class (32-bit exe before first instruction) was fixed in BCD build 576 | standard list | BCD rule `wow64-thread-map-uninitialised` (Dead Space in evidence) |
| 9 | **Ori and the Blind Forest** (261570) | **D3D11** (not DX9) | 32 (Unity) | Full | untested; 32-bit D3D11 = DXMT's i386 d3d11 through winemetal's 32-bit table. The 64-bit D3D11 path is proven (SIGNALIS, 20 min at 3.3 GB); the i386 one is the same DXMT code, untested here `[INFERENCE]` | standard list | PCGW; `/tmp/g2/dev/sig.txt` |
| 10 | **Ori … Definitive Edition** (387290) | D3D11 | 32 | Full | as #9 | as #9 | PCGW |
| 11 | **Celeste** (504230) | D3D9c + D3D11 (FNA) | 32 | Full | untested; FNA/DX9 is the same stack as Castle Crashers, which is playable (#446) | standard + `env.MADEIRA_PAD_EARLY_SLOT=1` | #446, PCGW |
| 12 | **Hitman: Blood Money** (6860) | D3D9c | 32 | none (store) | untested | standard + a mouse/kb touch layout | PCGW |
| 13 | **GTA: San Andreas** (12120) | D3D9 | 32 | none | untested | standard | PCGW |
| 14 | **GTA: Vice City** (12110) | **D3D8** | 32 | Partial | untested; needs d3d8→wined3d or a d3d8→d3d9 wrapper. wined3d is blocked (§6.1); BCD's `env.MADEIRA_D3D8 = d3d9` does not exist in this tree | none today | `grep MADEIRA_D3D8` empty; BCD rule `grand-theft-auto-iii` |
| 15 | **The Witcher EE** (20900) | D3D9c | 32 | none | untested | standard | [INFERENCE] |
| 16 | **MGSV: Ground Zeroes** (311340) | **D3D11** | 64 | Full | untested; BCD ships a Metal Gear preset (`EC_HOOK_TRACE=0`, exe window 176 MB) | standard | BCD rule `metal-gear-solid-v` |
| 17 | **Fallout 3** (22300) | D3D9c | 32 | Partial | preset shipped, **not tested on a device** (`GameRecommendations.swift:583-596`) | older-NVIDIA card switch + `env.MADEIRA_D3D9_LAST=1` | PR #439 |
| 18 | **Fallout: New Vegas** (22380) | D3D9c | 32 | Partial | **works** with the older-NVIDIA switch: a save that crashed on load now loads | older-NVIDIA switch (sets `d3d9.customVendorId=10de`, `customDeviceId=0292`, `customDriver=nv4_disp.dll`) | #439; `LibraryBCD.swift:117-133` |
| 19 | **Oblivion GOTY** (22330) | D3D9c | 32 | none | untested; the sibling DX9 Bethesda title Skyrim does not launch (#425) | standard | #425 |

Supporting (not owned) reports that pin the routes:

| Game | API/bits | Result | Link |
|---|---|---|---|
| Portal 2 (620) | D3D9, 32 | **60 fps**, emulated frontend; `d3d9 = native` crashes at `RIP=0` after `CreateDevice` | #192; `/tmp/g2/dev/portal2.txt:13374,14252-14413,28416` |
| Castle Crashers (204360) | FNA/XNA, 32 | playable, 110,000+ presents | #446 |
| Crysis 2 (108800) | CryEngine 3, 32 | deadlock before any renderer; d3d9 never loaded | #446 |
| Imperial Glory (277450) | fixed-function D3D9, 32 | menus render, buttons/text invisible; both frontends tried | #383 |
| TF2 (440) | D3D9, 32 | `d3d9_init FAILED` (wined3d, no GL context) | #424 |
| BeamNG 0.4.0.6 | D3D9, 32 | launch stalls, returns to library | #432 |
| Outlast | UE3 D3D9, 32 | `c000001D` illegal instruction in FEX | #132 |
| Battlefield: Bad Company 2 | D3D9, 32 | hangs on the campaign text screen | #474 |
| FF VII 1998 | 32 | no guest window on a 454 GB map | #390 |

## 4. General recipe (cfg keys)

**Global — `Documents/madeira.cfg`** (keys are re-read per session; per-game lines in the game's own
config file win, `build/madeira_cfg.h:1-18`):

```
d3d9 = emulated            # explicit default; NEVER native (crash) — omit or write "emulated"
env.MADEIRA_NO_GL = 1      # 32-bit games, TODAY: keeps the broken 32-bit GL thunks out of the process
env.MADEIRA_EC_HOOK_TRACE = 0   # the standard list every tested game runs with
pool = 512                 # Portal 2's tested value; default 640
# memory, for the ~6.1 GB kill line (values from the tested recipes):
swap-mb = 3072             # swap tier on (>=64); broad coverage is the device-verified mode
vram-mb = 1536
```

**Per game** (Game details → this game's config, or `GameRecommendations`):

- Any game that polls the pad at start-up (Dark Souls, Celeste-like native-XInput games):
  `env.MADEIRA_PAD_EARLY_SLOT = 1` and `env.MADEIRA_CONTROLS_XBOX_DEFAULT = 1`
  (`GamepadInput.swift:37,51`; `TouchControlPresets.swift:378`).
- Fallout 3/NV, Oblivion-likes that pick a render path from the GPU string: Game details →
  **Older NVIDIA card (Direct3D 9)** = on (`GameRecommendations.swift:570-596`).
- Batman AC: `env.FEX_X87REDUCEDPRECISION = 0` (per-game "Reduced-precision x87" switch,
  `Library.swift:551`) — BCD's tested *attempt*, not a proven fix.
- 64-bit titles that rewrite their own code: `env.MADEIRA_X64_IMAGE_NOCOPY = 1` (Dark Souls II
  SOTFS evidence, 379 s vs 34 s).
- Diagnosing a DX9 crash: `env.MADEIRA_D3D9_LAST = 1` records the last 64 calls; add
  `env.MADEIRA_D3D9_TRACE = 1` for one line per guest↔host crossing
  (`dxmt/src/d3d9/d3d9_census.cpp:478-490`, `dxmt/src/d3d9/unix/d3d9_native_glue.cpp:1685-1693`).
- Do **not** put `d3d9 = wined3d` in a global config: it also replaces the x64 `d3d9.dll`.

Process tip from #446: the first launch of a Steam DX9 game runs `vcredist`/`DXSETUP`; DXSETUP fails
with `0xC0000018` and the session ends. Restart Madeira and launch again ("One-time installs
skipped") before judging the game.

**Rockstar launcher path (L.A. Noire if it cannot be bypassed).** The RG Launcher is the same
`Launcher.exe` + `SocialClubHelper.exe` pair RDR2's list already handles: copy
`env.MADEIRA_DOCK_KEEP_ALIVE = Launcher.exe;LANoire.exe`, `env.DXMT_SMALL_RINGS =
Launcher.exe;SocialClubHelper.exe`, `env.MADEIRA_SC_PA_POOLS = 2`, `env.MADEIRA_SPAWN_BLOCK`,
`env.MADEIRA_PIN_GRAPHICS_DLLS = 1`, `env.WINEDLLOVERRIDES = video64=` from
`GameRecommendations.swift:124-185`; Social Club's Chromium is single-process by default
(`env.MADEIRA_SC_CEF = 1`), and `avail-phys`/`avail-phys-cef-mb` control what it thinks is free.
Risk: GTA IV's launcher report (#151) shows this path failing at the installer/`launch-client-error=17`.

The `d3d9` key's UI is wrong: `ConfigCatalog.generated.swift:14` offers only
"Default (emulated)" and "Native ARM64 frontend" — `wined3d` is accepted by the code but not
selectable from the picker (write it in the game's config).

## 5. Systematic blockers, ranked

### 5.1 opengl32's 32-bit thunks are unpatched in every build made from this tree (blocker #1)
Any 32-bit program that loads `opengl32.dll` — directly, or through `ddraw`/`d3d8`, which always draw
through wined3d — dies in `opengl32.dll`'s DllMain before the game starts. Log:
`/tmp/g2/dev/bm.txt:12874` (opengl32 load) → `12989`/`13016`
`pc=…wow64_thread_attach+0x4 lr=__wine_unix_call_dispatcher`, read of `x8+0x3fdc` with `x8=0x302000`
(a *guest* TEB address treated as a host pointer) → `13047` `loader_init "opengl32.dll" failed`,
`c0000142`.
Cause: `wine/dlls/opengl32/unix_private.h:88-93` still does
`TEB32 *teb32_ptr = ULongToPtr( teb32 );` — the tree has **zero** `ios_wow_host_ptr` occurrences
(`wine/dlls/opengl32/{unix_private.h,unix_thunks.c,make_opengl,unix_wgl.c}`), while
`patches/wine-opengl-winios.patch:317-327` defines `get_teb64_from()` with
`ios_wow_host_ptr( teb32 )` and `build/ntdll-unix/build.sh:170-177` compiles
`unix_wgl.c`/`unix_thunks.c` from that unpatched tree. `docs/BUILDING.md:93,96,100` tells the builder
to apply the patch; before the fork's `225517a` no script or CI step did. Since then
`tools/fork/apply-wine-patches.sh` applies it from `build/ntdll-unix/build.sh`,
`build/wine-i386/build.sh` and `build/wine-pe/build-modules.sh` (G4 onward).
This is also what makes `d3d9 = wined3d` unusable for 32-bit today, and why TF2 (#424) and Vice City
(D3D8) cannot work.
Workaround: `env.MADEIRA_NO_GL = 1` (documented switch, `virtual_ios.c:12327-12342`) — but it also
disables wined3d/d3d8/ddraw.
Fix: see §6.2(a).

### 5.2 A host-side fault cannot be turned into a guest exception (blocker #2)
`NtReadVirtualMemory`'s current-process branch does `memmove()` under `__TRY`
(`build/ntdll-unix/virtual_ios.c:34977-35000`). When the *source* is a reserved page (`prot=0`), the
host faults in `_platform_memmove`, and the Mach handler cannot build a frame: the faulting host `sp`
is 0x30 bytes below the TEB's `DeallocationStack` (`sp=0x12637fbd0`, stack base `0x126380000`), so
`[mach-deliver] no TEB owns sp → BEST-EFFORT`, then `call_seh_handlers invalid frame` and
`NtRaiseException Exception frame is not in stack limits` → `NtTerminateProcess(0x1f)`
(`/tmp/g2/dev/main6.txt:12664-12793`; same signature in `/tmp/g2/dev/bat.txt:6160`).
The guest asked to read its own `0x8468ff6e` (host `0x798468ff6e`, window `B=0x7900000000`); on
Windows it would get `STATUS_PARTIAL_COPY`. This single bug is what kills Batman AA today, and it is
the class the repo already documents and avoids elsewhere (`virtual_ios.c:32397-32415`: "an address
in a reserved region … raised a SIGBUS that bus_handler hands to the guest without honouring the
__TRY … The kernel copy returns an error instead" → `ios_ec_hook_peek` uses `mach_vm_read_overwrite`;
the wineserver does the same for other processes, `build/wineserver/mach_ios.c:1088-1136`).
Fix: §6.2(b). Test knob in the meantime: `env.MADEIRA_LAA = 0` (2 GB ceiling instead of the
synthesised 4 GB one, `virtual_ios.c:10399-10417`) — the offending guest address is >2 GB, so the
game may never reserve there. `[INFERENCE]`, untested.

### 5.3 UE3 / CryEngine 3 deadlock before the first device (#446)
Batman AC and Crysis 2 hang with `presents=0`, all guest threads parked on events nobody sets;
`d3d9.dll` loads but `CreateDevice` is never called. Confirmed on iDeck build 56 (Madeira-based)
and by BCD's x87 fixture on builds 574-578. Workarounds: none proven; `FEX_X87REDUCEDPRECISION=0`
captures a *different* BCD crash, not the deadlock. Re-check (2026-11-01): the Dock's
`running=1` is the whole Wine session, so "0 `CreateDevice`, `running=1`" also fits a game that
died early; Batman AA shows exactly that (`prev7.txt:12794` exit `0x1f`, then `running=1` to 158 s).
See dx9-batman-fix.md's corrections; #446 is unproven as a deadlock.

### 5.4 Fixed-function D3D9 pipeline gaps (#383)
Imperial Glory: ~447 `SetTextureStageState` per draw, vs_1_1 only; menu artwork renders, button/text
quads do not. Both frontends tried; `d9_scene_batch`, `d9_binding_prune`, `d9_canonical_blend` did not
help. Anything pre-SM2 with heavy texture-stage state is at risk.

### 5.5 32-bit addressing (guest window, LAA, thread registry, x18)
- No window on a small/crowded map (#390: 454 GB map, `main-process reserve FAILED 0xc0000017`)
  → `MADEIRA_WOW_MIN_FREE_GB` (docs/WOW64.md:246-258).
- A non-LAA image still gets a 4 GB ceiling by default (`virtual_ios.c:10410-10504`, log line `[laa]
  32-bit image is not large-address-aware; user space raised to 4 GB`); `MADEIRA_LAA=0` restores
  2 GB, `MADEIRA_LAA_LOWFIRST=0` restores high-first placement.
- The WoW64 thread registry has 512 slots; after they are used, new threads resolve to the wrong TEB
  and the same fatal `Exception frame is not in stack limits` follows (#397).
- v0.1.3's x18-derived TEB crash (#423) is fixed by #267, which the madeira-bcd build carries.

### 5.6 Controller, not rendering
Full-controller-support games that read XInput directly are fine; Source games route input through
Steam Input and fail without `SDL3.dll` (`c000007b`, #192), and L.A. Noire's launcher ignores pads
(PCGW). Prefer native-XInput titles for a touch layout (§7).

## 6. Concrete actions

### (a) Config-only (no reinstall)

| Where | Key | Value | Why |
|---|---|---|---|
| global | `d3d9` | *(omit)* or `emulated` | default is the only route with frames |
| global | `env.MADEIRA_NO_GL` | `1` | D3D9 titles: `d3d9-emulated` needs no GL; GL only reaches ddraw/wined3d, whose failure UE3 survives. Remove only to test the patched 32-bit GL thunks on their own |
| global | `env.MADEIRA_EC_HOOK_TRACE` | `0` | standard list |
| global | `pool` | `512` | Portal 2's tested value |
| global | `swap-mb` / `vram-mb` | `3072` / `1536` | keep DX9 texture churn under the kill line |
| Batman AA | `env.MADEIRA_LAA` | `0` | try to keep the game below 2 GB and dodge the §5.2 probe |
| Batman AC | `env.FEX_X87REDUCEDPRECISION` | `0` | BCD's tested attempt at the x87 fault |
| Fallout 3/NV | older-NVIDIA switch (on) | – | proven for NV (#439) |
| any pad-at-start game | `env.MADEIRA_PAD_EARLY_SLOT`, `env.MADEIRA_CONTROLS_XBOX_DEFAULT` | `1` | player 1 present from frame 0 |
| 64-bit self-modifying | `env.MADEIRA_X64_IMAGE_NOCOPY` | `1` | DS2 SOTFS evidence |
| diagnosing | `env.MADEIRA_D3D9_LAST` (+`env.MADEIRA_D3D9_TRACE`) | `1` | last 64 calls / per-crossing lines |

### (b) Code changes

**(1) Build the GL unix side from the patched tree** — `build/ntdll-unix/build.sh` (before the
`opengl32`/`unix_thunks` compiles at lines 170-177) and the i386/canonical build bootstrap should
`git -C wine apply --check ../patches/wine-opengl-winios.patch && git -C wine apply
../patches/wine-opengl-winios.patch`, and regenerate `wine/dlls/opengl32/unix_thunks.c` with
`perl make_opengl` (`docs/BUILDING.md:96`). Same for CI's `i386` job
(`.github/workflows/build.yml:186-198`) and the `runtime` job that builds `ntdll`. Expected log
evidence: no `pc=…wow64_thread_attach` fault; instead
`[unixlib] opengl32 (winios WGL) … -> wow64 table` followed by the game's first GL call. (Also fixes
`d3d9 = wined3d` for 32-bit and D3D8/DirectDraw.)

**(2) Never fault the host while serving `NtReadVirtualMemory`** — `build/ntdll-unix/virtual_ios.c:34987-35000`:
replace the `memmove` under `__TRY` with a kernel copy of the source, page by page (or one call),
e.g. `mach_vm_read_overwrite( mach_task_self(), (mach_vm_address_t)addr, chunk,
(mach_vm_address_t)buffer + done, &got )`, accumulating `done`; map `KERN_PROTECTION_FAILURE`/
`KERN_INVALID_ADDRESS` to `STATUS_PARTIAL_COPY` and set `*bytes_read = done`. Alternative (already
in-tree): `virtual_uninterrupted_read_memory()` (`virtual_ios.c:27425-27452`) checks each page's
`get_host_page_vprot` before `memcpy`; it returns 0 for a `prot=0` reservation, so
`status = done ? STATUS_SUCCESS : STATUS_PARTIAL_COPY`. Expected log evidence: no
`[mach_exc] UNHANDLED` / `Exception frame is not in stack limits` from `NtReadVirtualMemory`;
Batman reaches `CreateDevice`.

**(3) Same class, one level up** — `virtual_check_buffer_for_read/write`
(`virtual_ios.c:27356-27417`) still touch the memory under `__TRY`; the comment at 32397 records the
identical failure ("the next __TRY then asserted (0x80000101)"). Convert them to a
`mach_vm_read_overwrite`/`mach_vm_write` probe (write-watch pages still need the touch path, so keep
`__TRY` only when `get_page_vprot` says the page is committed and writable).

**(4) Make the `d3d9` picker offer `wined3d`** — `ConfigCatalog.generated.swift:14` choices should be
`("", "Default (emulated)")`, `("emulated", …)`, `("native", …)`, `("wined3d", …)`, and the title/note
should stop saying "32-bit" for native's scope (the shim is 32-bit only, but `wined3d` is both).

**(5) Optional hygiene** — `dxmt/src/d3d9shim/d3d9shim_main.c:120-122` still tells the user to create
`Documents/madeira-d3d9.txt`; that file no longer exists (the knob is `d3d9` in madeira.cfg). Fix the
string so the log matches the catalog.

## 7. Try first (owned list, ranked)

1. **Alan Wake (108710)** — 32-bit DX9, full controller, upstream "working reference"; only needs the
   standard list and `windowed=0` for exclusive fullscreen. Touch layout: stock Xbox layout, left
   stick + A/B/X/Y, triggers.
2. **Fallout: New Vegas (22380)** — 32-bit DX9, partial controller (fine for pad play), proven fix for
   its save crash (older-NVIDIA switch). Layout: Xbox + d-pad shortcuts.
3. **Celeste (504230)** — 32-bit FNA/DX9 (same stack as the playable Castle Crashers), full
   controller, tiny memory footprint; add `MADEIRA_PAD_EARLY_SLOT=1`. Layout: d-pad + jump/dash.
4. **Ori and the Blind Forest (261570)** — 32-bit *D3D11* Unity: same DXMT renderer as the proven
   64-bit D3D11 titles, through the i386 d3d11; full controller. Layout: left stick + A/B.
5. **Dark Souls II (236430)** — 32-bit DX9, full controller; the vanilla exe is untested but its
   64-bit sibling's failure mode has a known line (`MADEIRA_X64_IMAGE_NOCOPY=1` shows 379 s of play
   vs 34 s). Layout: Xbox with the right stick for camera.

Avoid until §5.1/§5.2 are fixed: Batman AA/AC/AO, Dead Space, GTA VC (D3D8), L.A. Noire (launcher
risk), Oblivion/Witcher EE (no controller).

## 8. Sources

Code and docs: `docs/WOW64.md:25-52,114-153,155-191,246-283`; `docs/BUILDING.md:93-109`;
`docs/DXVK.md:23-24`; `build/wine-i386/build.sh:1-30,161-166`; `build/fex-wow64/build.sh:1-20`;
`.github/workflows/build.yml:161-206,257,288-315`; `.gitignore:204-205`;
`dxmt/src/d3d9shim/{README.md:18-23,145-149,d3d9.def:22-35,d3d9shim_main.c:94-146}`;
`dxmt/src/d3d9/{d3d9.cpp:42-49,d3d9_census.hpp:44-48,d3d9_census.cpp:478-490}`;
`app/Madeira/{ContentView.swift:2974-2992,WineProcessBridge.m:736-806,2059-2060,ConfigCatalog.generated.swift:14,270-282,LibraryBCD.swift:117-133,Library.swift:551,GamepadInput.swift:37-51,TouchControlPresets.swift:378,GameRecommendations.swift:124-185,533-596}`;
`build/ntdll-unix/{virtual_ios.c,build.sh:170-177}`; `wine/dlls/opengl32/{unix_private.h:88-93,unix_wgl.c:2829-2832}`; `patches/wine-opengl-winios.patch:317-327`; `build/wineserver/mach_ios.c:1088-1136`; `tests/x86/build-d3d9-cube.sh` (the 32-bit D3D9 acceptance test).

Device logs: `/tmp/g2/dev/{portal2.txt,main5.txt,main6.txt,bm.txt,bat.txt,sig.txt}`.

Upstream: [PR #27](https://github.com/willfaust/Madeira/pull/27) (32-bit D3D9 wiring),
[#242](https://github.com/willfaust/Madeira/pull/242) (x64 DXMT d3d9),
[#353](https://github.com/willfaust/Madeira/pull/353) (wined3d/DXVK routes, device status),
[#439](https://github.com/willfaust/Madeira/pull/439) (older-NVIDIA switch),
[#446](https://github.com/willfaust/Madeira/issues/446) (UE3/CryEngine deadlock, Alan Wake working),
[#192](https://github.com/willfaust/Madeira/issues/192) (Portal 2 60 fps; native crashes),
[#383](https://github.com/willfaust/Madeira/issues/383) (fixed-function gaps),
[#424](https://github.com/willfaust/Madeira/issues/424) (TF2/GL context),
[#432](https://github.com/willfaust/Madeira/issues/432), [#492](https://github.com/willfaust/Madeira/issues/492),
[#474](https://github.com/willfaust/Madeira/issues/474), [#132](https://github.com/willfaust/Madeira/issues/132),
[#390](https://github.com/willfaust/Madeira/issues/390), [#397](https://github.com/willfaust/Madeira/issues/397),
[#423](https://github.com/willfaust/Madeira/issues/423), [#425](https://github.com/willfaust/Madeira/issues/425),
[#151](https://github.com/willfaust/Madeira/issues/151), [#384](https://github.com/willfaust/Madeira/issues/384).
BCD: [`recommended/recommendations.json`](https://github.com/thebcd69/bcd-games/blob/main/recommended/recommendations.json),
[`AutoTuneRules.generated.swift`](https://github.com/thebcd69/bcd-games/blob/main/app/Madeira/AutoTuneRules.generated.swift),
`tests/fixtures/autotune/batman-arkham-*`. iDeck: [#1](https://github.com/kuscholar/iDeck/issues/1).
PCGamingWiki `direct3d versions` / `windows 32-bit exe` for each table row; Steam store API
`categories` for gamepad support.
