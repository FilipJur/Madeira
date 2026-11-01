# Alan Wake (108710) on Madeira G8 — where the time goes, and what is achievable

Slice: performance only (no edits, no builds, phone offline). Evidence is `/tmp/aw4.txt`
(gameplay, windowed 1424x656), `/tmp/aw2.txt`+`/tmp/aw3.txt` (menu, exclusive fullscreen),
`/tmp/bm11.txt`+`/tmp/bm14.txt` (Batman AA, same build) and the repo.

**Verdict: worth pursuing, but as a settings/toggle problem, not an engine project.**
The one measured lever (reduced-precision x87) is a per-game toggle that already exists and
is verified to be worth 4–5x here; the app *forces it off* by default. After that the ceiling on a
cool phone is ~35–45 fps falling to ~20–25 sustained, i.e. a 30 fps-capped playable game, not 60.

---

## 1. Measured performance (aw4, the only in-game run)

| phase | wall | presents (detach-wait) | fps | [xp] cpu (cores) | P clock |
|---|---|---|---|---|---|
| load / Bink intro | +0–30 s | 1353 | ~45 avg (census: **900 frames / 15 045 ms = 60.0 fps**) | 0.3–1.3 | 3.3→1.9 |
| early scene | +30–60 s | 2524 (1171 in 30 s) | 39 | 2.3–3.2 | 2.0–2.1 |
| gameplay | +60–90 s | 2667 (143 in 30 s) | **4.8** | 3.3–3.7 | **1.72–1.91** |

* fps source: `[INFO] detach-wait: presents=1353/2524/2667 … elapsed=30/60/90s` (aw4:14363,16051,17827)
  and `[d3d9-census] ---- summary 3: present=1000 frames=900 window=15045ms` (aw4:13603).
* `cpu=` is **ms of process CPU per window** (`build/ntdll-unix/server_ios.c:2731`, `cpu = XP_MS(ru_user+ru_sys)`
  over `dt`), so cores = cpu/dt: `cpu=1117, dt=325` → 3.4 cores. It is *not* "10 cores".
* Clocks: `GHz P=1.72 E=2.11` (aw4:16914) — the P cores were capped **below** the E cores.
  The same build on a cool phone reads `P=3.67–3.75` (bm11/bm14) and median `P=3.41`, max 3.69 (aw3).
  **aw4 is a hot-phone measurement: 1.8x–2.0x clock deficit, and `thermal=serious` was already
  logged at launch** (aw4:15, aw4:58) — inherited from hours of earlier runs, not caused by the game.
* Energy: aw4 total 194.0 J over 107.9 s of sampler windows = **1.80 W mean process CPU power**
  (peaks 2.2–2.4 W in play). The SoC clamps after ~250–330 J (`server_ios.c:2105-2113`), so this title
  re-clamps itself within ~2–3 minutes of play no matter how it started. aw3 (menu, 120 fps) = 1.57 W,
  bm14 (GPU-bound Batman) = 0.74 W.
* Runnable time `run=1066…1260 ms` per ~300 ms window in play = ~3.5–4 cores of demand on ~3.3
  available: the process is CPU-saturated, not idling.
* **Per-frame CPU: early scene 2.9 cores ÷ 39 fps = 0.074 core-s; gameplay 3.3 cores ÷ 4.8 fps = 0.69 core-s.**
  That is 9x more CPU per frame for 8x fewer frames — and 0.69 core-s ÷ 3.3 cores = 209 ms = exactly the frame
  time. Nothing is stalled waiting: the *scene's own emulated work* became the frame. The extra work is
  the three worker threads waking up (tessellator/physics/job, §2), i.e. the maths-heavy part of the frame.

## 2. Where the CPU goes in gameplay

Per-thread (`[xp-t]`, aw4:18738, unit is ms of P/E time and M instructions per window):

| host tid | share of 3.3 cores | identity |
|---|---|---|
| 00a8 | 1.0–1.23 | `RMD - Game Thread` (window owner, `winios-tree … tid=00a8`) |
| 00e4 | 0.75–0.97 | **unnamed guest thread, teb=0x7900210000** (`[thread-sample] ml876 b1 "" … cpu=96% RUN`) |
| 00c8 | 0.55–0.67 | `RMD - Tessellator Thread` (teb 0x7900280000) |
| 00cc | 0.4 | `RMD - Physics Thread` (teb 0x7900270000) |
| 00d0 | 0.2 | `RMD - Game Job Thread` (teb 0x7900260000) |

Remedy's engine has no separate render thread: rendering happens on `RMD - Game Thread`, and the
whole frame waits on it — matches the engine description below (§6). P/E split over the run:
game thread **25% of its CPU time on E cores** (40% in the last windows), thread 00e4 17% — on a
*cool* phone (P=3.7 vs E=2.1) that migration is worth ~1.3x on the critical path.

Host-pc attribution (`[cpu-split]` gen=3, aw4:18016):
`running samples=535: x64 JIT 84%, ARM64EC images 14%, native 0%` → **no measurable time in Metal,
winemetal or other native code on guest threads**; this is emulated guest code.

The hottest on-core JIT region is one ~2 KB area, `0x166ff9840–0x166ffa0c0` = **68% of on-core
samples** (aw4:18017: 95+93+70+33+16+12+9+9+8+8 ≈ 363/535). Hand-decoding the dumps (aw4:18018–18020)
gives: `sub/csel/clz/mov #0x401e/lsl/ubfx/fmov` = an **integer→double conversion built by hand**,
followed by a full x0–x18 + SIMD spill, `blr x3`, restore, `msr NZCV` — i.e. FEX's **host-callback
thunks for FP helper routines**. `[INFERENCE]` (hand decode, not symbolised) but it matches the
independent result in §4 that x87 is ~78% of the frame.

**Tooling caveat — guest RIP is not usable in this process** (worth fixing, it is mislabelling
32-bit logs): `server_ios.c:1266` classifies any RIP `< 0x140000000` as "native callee", so every
32-bit guest address lands in that bucket (`RUNNING in native callees=535 (100% of running)`), and
`0x3d0000` (59% of all samples in aw4 gen=2, 100%/`span=0x0` in aw2/aw3 gen=1) is a constant that is
in no module. The one guest bucket that does resolve, `0xfff8d700` (51% of RUNNING in aw4 gen=3),
is a **64-byte grain** (`ML979_GRAIN`) over four 16-byte i386 ntdll stubs —
`NtReadFileScatter/NtOpenThreadTokenEx/NtOpenProcessTokenEx/NtQueryPerformanceCounter`
(VA 0x7bc4d700..0x7bc4d73f in `app/Madeira/i386-windows/ntdll.dll`, each `mov eax,N; mov edx,0x7bc4e4a0;
call *edx; ret n`), i.e. **"last left the JIT at a syscall stub"**. It is *not* literal time inside a syscall:
the thread is sampled *on core with the host pc in JIT code* (`[cpu-split]` 84%), so what it means is "executing
emulated code whose last JIT exit was that stub" — the i386 `__wine_syscall_dispatcher` is itself **guest** code
(JIT'd), so the emulated part of the syscall path lands here. Blocking time would be `native` (0%). Which of the
four stubs it is cannot be resolved at a 64-byte grain.
`[xp-api-top]` is **absent** by design in a 32-bit process: it is only printed when `x64->EC > 0`, and `[xp-api]`
reads `x64->EC 0/s` (aw4:18735). The `[xp-api]` counters themselves *are* this process (aw4:12629
"counters follow the busiest Wine process (peb 0x7900310000 …)", which is AlanWake.exe's PEB).
Syscalls are **not** the cost: rates are *lower* in play than in the 120 fps menu
(`wait1 942/s vs 3263/s, yield 2577/s vs 1700/s, delay 2115/s vs 1012/s`, aw4:18735 vs aw3:23999).
The ~1800/s zero-timeout `Sleep(0)` and the `WaitOnAddress wakeAll 348–376/s` are the job-system
spin *around* the wait, a symptom of a slow frame, not its cause.

## 3. The D3D9 frontend is not the bottleneck (confirmed, quantitatively)

* Alan Wake per frame: **74.6 D3D9 calls** in the load phase (`census summary 3: calls window=67131 … per_frame=74.6`,
  aw4:13604) and 60.7–131 calls at 120 fps in the menu (aw3:12863,19929,22081). In-game it never
  reached `present=5000`, so there is no gameplay census — but the count cannot be what costs 200 ms.
* Batman AA: **2 215–2 314 calls/frame** (bm14:26830 `per_frame=2215.1`, bm11:19748 `2313.7`) — 30x Alan
  Wake — and bm14 runs those at `cpu=30–45 ms/300 ms` = **0.10–0.15 cores** at ~35 fps, i.e.
  **≈1.5 µs per D3D9 call** (0.12 cores ÷ 35 fps ÷ 2215 calls) end-to-end through the emulated i386
  frontend. Alan Wake's worst case (2 000 calls/frame) would cost ~3 ms/frame.
* The menu proves the whole present path: **120 fps for 200 s** at 1424x656 with the same DXMT swapchain,
  0.5–0.8 cores, 20 000 presents (aw3:22080). Nothing in the swapchain/present frontend limits us.
* Format support is fine: only 2 of 23 `[d3d9-caps]` probes fail (aw4:10671-10675) — `ATOC` and
  `A16B16G16R16F samples=8`; no slow shadow/format fallback.
* Not a readback stall: every `[d9-lock]` line in aw4 is "upload locked rect on unlock" (aw4:10679-10862).

## 4. x87 full precision is ~78% of the in-game frame

`FEX_X87REDUCEDPRECISION=0` in runs 1–3; run 4 (owner) turned it on: **4.8 → 20–25 fps**.
With ~3.3 cores busy in both cases, per-frame CPU drops 0.69 → ~0.15 core-s, so **~0.54 core-s/frame is
x87 softfloat ≈ 78% of all CPU in the scene**.
This is consistent with FEX's own device A/B note in this tree — `20–50 % of ALL CPU` in the softfloat
thunks, "frame rate roughly doubling" — `FEX/Source/Windows/WOW64/Module.cpp:1128-1149`.
Mechanism: without it every x87 op that cannot stay in a double goes through the x87 80-bit ABI thunks
(they are the hot JIT callback region of §2). Alan Wake is x87-heavy because it is a 2010 Remedy engine
with a 2012 Nitro Games port, and the scene cost is concentrated in maths the FPU does (Havok physics,
tessellation of the world mesh, shadow/light matrices) — `[INFERENCE]` from the two independent numbers
above, since `AlanWake.exe` is not on this machine.

**The app currently forces full precision**: `LibraryEntry.reducedX87 = false`
(`app/Madeira/Library.swift:195`) and `applyEnvironment()` always exports it
(`Library.swift:551 setenv("FEX_X87REDUCEDPRECISION", reducedX87 ? "1" : "0", 1)`), which overrides
FEX's own 32-bit default of 1 (`FEX/Source/Windows/WOW64/Module.cpp:1149-1151`: "if !Exists(…) Set(…, "1")").
So a new library entry for a 32-bit title starts 4–5x slower than the engine default. The UI toggle is
`"Reduced-precision x87" / "Faster, less accurate"` (Library.swift:3712).

## 5. GPU: unmeasured, and the next wall

No GPU timing exists in these logs (no `DXMT_D9_SUBMIT_STATS`, no frame-time markers; `[xp]`'s `pres/flush/lat/cmt`
fields are madeira-d3d12 only). What is known:
* The swapchain has **no MSAA** (`msaaType=0`, aw4:10640) but the game's AA is forced on and it probes it on
  an `A16B16G16R16F` target: `CheckDeviceMultiSampleType … fmt=A16B16G16R16F samples=2/4 -> hr 0x0`, `samples=8
  -> 0x8876086a` (aw4:10671-10675). `[INFERENCE]` (the log does not show the render targets the game then
  creates) it renders HDR at 4x and resolves every frame — `d3d9_swapchain.cpp:481,1107` show that path exists.
* Batman, GPU-bound at 0.12 cores and ~35 fps with 2 200 calls/frame, is the closest reference for
  "what the phone's DXMT/Metal path can do once the CPU stops being the limit" — same class of load.
* `[INFERENCE]`: at reduced x87 the GPU (MSAA + shadow/volumetric/SSAO passes at default settings) is
  the next limiter; `DXMT_D9_SUBMIT_STATS=1` on the next run would settle it in one launch.

## 6. Research: the game

* **Single-core bound by design.** "The game makes moderate use of multi-cores but still uses one core
  more than the others. When this core peaks/reaches max load the game will slow down… you'll need a
  quad core at least 4.7 GHz for a solid 60 fps" (Steam, *alan wake maxing out cpu*,
  steamcommunity.com/app/108710/discussions/0/882959903390526889/). Thread layout in our log matches:
  one `RMD - Game Thread` at ~100% of a core plus a small job pool (5 guest threads busy, §2).
* PCGamingWiki (API fetch, `?action=parse&page=Alan_Wake&prop=wikitext`): D3D9c only, 32-bit only,
  Havok physics, "antialiasing always on, up to 8x MSAA (2x minimum), low-to-high FXAA", cap 200 fps,
  mouse sensitivity tied to fps; config `%USERPROFILE%\Documents\Remedy\AlanWake\` (+`resolution.xml`),
  Steam settings under `steamapps/…/108710/`. Intro videos: `data\videos\startup_*.bik`.
* ProtonDB 108710 = Platinum, 266 reports; the settings list that yields a locked 60 fps on a Steam Deck
  is the useful calibration: AA 4x, FXAA high, aniso 4x, **shadow quality medium, SSAO low, godrays off,
  volumetric light low, draw distance 15/20, LOD 14/20, grass distance 10/20**. A Steam Deck (Zen2 ~3.5 GHz,
  4 cores) does 60 fps at those settings; we are single-thread emulated at 1.8–3.7 GHz.
* Steam thread "Low FPS no matter what setting?" (linked from PCGW) — the community answer is DXVK, i.e.
  the game is CPU/driver-side bound, consistent with our measurement.

## 7. Bottleneck breakdown (aw4, 4.8 fps = 208 ms/frame, 0.69 core-s/frame)

| component | share of the frame | basis |
|---|---|---|
| x87 80-bit softfloat under FEX | **~78%** | 4.8→20–25 fps from one toggle at constant core count |
| rest of FEX emulation of game + Wine + i386 D3D9 frontend | ~20% | 0.15 core-s/frame at reduced precision |
| D3D9 frontend calls | **<1%** (≈0.1–3 ms) | 1.5 µs/call measured on Batman, 75–2 000 calls/frame |
| Metal / winemetal / unix calls on guest threads | ~0% sampled | `[cpu-split] native 0%` |
| syscalls + Wine sync | small; spin is a symptom | rates lower than the 120 fps menu |
| thermal clock deficit (multiplier, not a share) | **1.8–2.0x** | P 1.72–2.11 GHz vs 3.4–3.75 GHz cool |
| GPU (MSAA/shadow/volumetric at defaults) | unmeasured; next wall after x87+clock | §5 |

## 8. Realistic estimate on a cool phone

Model: per-frame CPU at reduced x87 ≈ 0.15 core-s at ~1.85 GHz ≈ 0.075 core-s at 3.7 GHz over the
~3.3 usable cores → **~13 fps per core-that-the-frame-needs**, i.e. **35–45 fps at 1424x656** with
default-ish settings, **25–30 fps sustained** once the 1.8–2.3 W clamp returns (which it will, after
~2–3 min; 194 J in 108 s in aw4). With full-precision x87 the same arithmetic gives **9–11 fps cool**
(measured 4.8 hot).

Caveats: run 4's phone temperature is not recorded, so "20–25 fps" may already have been cool — in that
case read the numbers as 20–25 fps and the sustain ~18–20. `[INFERENCE]` either way; one cool-phone run
with `[xp]` +(a GPU stat) settles it.

## 9. Levers, ranked by expected gain per unit effort

### No code changes (per-game settings / madeira.cfg / launch args) — all available today
1. **`Reduced-precision x87` ON** (`Library.swift:3712`; or `env.FEX_X87REDUCEDPRECISION = 1` in the game's
   config text). **4–5x** (4.8 → 20–25 fps measured). Blocked only by the missing-texture bug (see AWTextures).
2. **In-game settings**, at 1280x720 or 1424x656: shadow quality low/medium, SSAO low/off, volumetric light
   low, godrays off, draw distance 15/20, LOD 14/20, grass 10/20, AA 2x/4x (8x is refused anyway).
   Steam-Deck-calibrated list in §6; expect **1.5–2.5x** if the GPU is the co-limiter, ~0 if not.
3. **fps cap 30–40 instead of 60**: `fpsMode` 3/4 (`Library.swift:192`) or `env.MADEIRA_FPS_CAP = 30/40`.
   Does not raise peak fps; it is what keeps the clock up: at 60-cap the frame loop keeps burning the
   energy budget. **Sustain 1.3–1.8x** (the difference between the 1.8 GHz clamp and 2.5–3.0 GHz).
4. **Power/fps governor**: `env.MADEIRA_FPS_GOV_MW = 1800` (+`_MAX/_MIN`, `server_ios.c:2105-2132`) — paces
   automatically between 60/40/30/24/20 fps to hold ~1.8 W. Same purpose as (3), hands-off.
5. **`env.MADEIRA_CPU_COUNT = 4`** (`Library.swift:556`): fewer visible CPUs → fewer engine job threads →
   less E-core migration and less oversubscription (`run≈1250 ms` per 300 ms window today).
   **~1.1–1.3x** `[INFERENCE]`.
6. **`env.FEX_TSOENABLED = 0`** as a *pure experiment* (FEX `Config.json.in:468`): every x86 integer store is
   an STLR under TSO; a single-thread-bound title may not miss it. **5–15%** `[INFERENCE]`, and unsafe for
   anything multithreaded — use the documented module-scoped form instead if it helps (see code item 4).
7. Skip: `d3d9 = native` (crashes 32-bit, #192), wined3d (no GL context, #424), `-window` is required
   anyway (fullscreen black = gamma path, AWGamma's slice).

### With code changes (ordered by value)
1. **Default `reducedX87 = true` for 32-bit library entries** — `Library.swift:195` + a one-line rule using
   the existing `LibraryEntry.bits`, or simply *not exporting* the variable when the toggle is untouched so
   FEX's own 32-bit default wins (`Module.cpp:1149`). Trivial, and it makes the engine default reachable;
   today every 32-bit game is 4–5x slower than it needs to be unless the user finds the toggle.
2. **Fix the reduced-x87 rendering bug** (missing textures/glitches, AWTextures' slice) so (1) ships safely.
   This is the whole gate on the biggest win — worth more than any other code work on this title.
3. **D3D9 MetalFX spatial upscale** — the D3D11 swapchain already has it (`dxmt/src/d3d11/d3d11_swapchain.cpp:1182`,
   `MTLD3D11SwapChain<true>` + `supportsFXSpatialScaler()`); the D3D9 swapchain has no equivalent
   (`dxmt/src/d3d9/d3d9_swapchain.cpp`). Rendering 960x540 and upscaling to 2556x1179 would cut the GPU
   side by ~3–4x for free quality-wise. **Big if §5 says GPU-bound**; moderate effort (port + present path).
4. **Expose `ExtendedVolatileMetadata` / module-scoped TSO disable** (`Config.json.in:577-604`, "only implemented
   for WoW64/arm64ec" — exactly our case): drop TSO for `AlanWake.exe` only, keep it for Wine/DXMT.
   Safer than the global experiment (no-code item 6) and documented upstream. **5–15%** `[INFERENCE]`.
5. **A "single-sample" override for the D3D9 frontend** (`d3d9_device.cpp:393-435 metalSampleCount`,
   `d3d9_swapchain.cpp:477-481`): ignore the game's MSAA request on the HDR target (Alan Wake cannot turn AA
   off). Quality loss, but it removes a 4x multisampled RGBA16F target + resolve. **Unknown, potentially 1.3–2x**
   if GPU-bound `[INFERENCE]`.
6. **Thread QoS/affinity for the frame thread(s)**: the game thread spends 25–40% of its time on E cores
   (`[xp-t]`), and `ios_bg_qos_check` (`server_ios.c:1974`) only moves threads between utility/user-interactive;
   a pin for the presenting/game thread would recover ~1.3x on a cool phone. Infrastructure exists
   (`ios_affinity_sets`), no per-game knob.
7. **Fix the profiler for 32-bit guests** (cheap, high diagnostic value): the `rip < 0x140000000` "native callee"
   test (`server_ios.c:1266`), the unresolved `0x3d0000` constant, and `ML979_GRAIN`=64 merging four ntdll
   stubs into one bucket. Without this, every future 32-bit report will chase 0xfff8d700.

## 10. Worth pursuing?

**Yes — but scoped.** Alan Wake renders correctly windowed, is a Platinum-class title on x86, and its whole
performance problem collapses to one toggle plus the in-game settings list; the measured cost of everything
this stack could plausibly be blamed for (frontend, present path, Metal, syscalls) is under 1% of the frame.
What it needs is (a) reduced x87 as the default and correct, (b) 30–40 fps cap + power governor so the phone
keeps its clocks, (c) in-game settings at Deck level — which buys a 30 fps-capped, thermals-stable game, not 60.
Do **not** chase the D3D9 frontend or the present path for this title. The one code investment that pays
across the whole 32-bit catalogue is item 1 (x87 default) plus AWTextures' correctness fix.

### Next run should capture
`MADEIRA_FPS_CAP=30`, `env.FEX_X87REDUCEDPRECISION=1`, `DXMT_D9_SUBMIT_STATS=1`, on a **cold** phone, and read
`[xp]` (clock, cores, `mJ`), `[xp-t]` (per-thread P/E), then `[d3d9-census]` past `present=5000` (needs ~3 min
at 30 fps) for the real gameplay call mix.
