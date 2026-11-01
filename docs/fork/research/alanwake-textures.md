# Alan Wake (108710) — missing textures + glitches after enabling FEX reduced-precision x87

Slice: renderer-side (DXMT D3D9) and FEX-semantics attribution of the run-4 symptom
("20–25 fps, many textures missing, slight glitches"). Research only; no repo edits.
Evidence base: `/tmp/aw2.txt` (fullscreen, black), `/tmp/aw3.txt`, `/tmp/aw4.txt` (windowed,
2–5 fps, textures visible), repo `FEX/`, `dxmt/` at HEAD 205808c. **No run-4 log exists** —
every statement about run 4 is inference and is marked as such.

---

## 1. What the logs prove (confirmed)

### 1.1 Capability queries: only two misses, and they are not run-4-specific
`grep 'd3d9-caps'` gives 23 queries in aw4 and the same answers in aw2/aw3. Complete miss list
(`0x8876086a` = `D3DERR_NOTAVAILABLE`):

| query | log line |
|---|---|
| `CheckDeviceFormat usage=0 rtype=SURFACE fmt='ATOC'` | aw4:10662, aw2 (same) |
| `CheckDeviceMultiSampleType fmt=A16B16G16R16F samples=8` | aw4:10675, aw2 (same) |

Everything else Alan Wake asks for is **available**: `DXT5` texture, `A8R8G8B8`, `X8R8G8B8`,
`A4R4G4B4`, `R16F`, `A16B16G16R16F` (texture + volume + render-target + filter),
`G16R16` as `RENDERTARGET|Q_FILTER|Q_POSTPSBLEND`, `D24X8` depth-stencil, MSAA 2x/4x on both
`D24X8` and `A16B16G16R16F`, `CheckDepthStencilMatch(A16B16G16R16F, D24X8)` OK.
Caps block (aw4:10446-10447) is a full SM3.0 HAL with `MaxTexture=16384`, 8 samplers,
`Caps2=0x60020000`, `-POW2 -NONPOW2COND`.

Alan Wake queries **no** `INTZ`, `DF24`, `DF16`, `FETCH4`, `R2VB`, `NVDB` (grep over all four
logs: zero hits), so those D3D9 extensions — the usual suspects for a DXMT D3D9 frontend gap —
are simply unused by this title.

**Conclusion:** the missing textures are not a "feature the frontend says no to" problem. The two
misses are identical in the run where the picture was fine (aw4), so they cannot explain a
run-4-only regression. ATOC absence only changes foliage-from-`alpha test` to `alpha test`;
8x MSAA absence just makes the game pick 4x (it probes 8/4/2, aw4:10673-10675).

### 1.2 Alan Wake uses D3DPOOL_MANAGED textures
Every lock-policy line is MANAGED (`D3DPOOL_MANAGED = 1`, `wine/include/d3d9types.h:930`;
`d3d9_surface.cpp:120` prints `desc.Pool`):

```
72 log lines across aw2/aw3/aw4:  "pool=1" ... usage=0   (no pool=0 line anywhere)
aw4:10686  [d9-lock] pool=1 usage=0 fmt=28  256x128
aw4:10862  [d9-lock] pool=1 usage=0 fmt=894720068 (='DXT5') 256x256
```
(The ml1110 log is capped at 24 lines/run, so this is a sample, not a census.)

That matters because it puts DXMT's *managed* machinery on the hot path — mirror allocation,
eager unlock upload, GPU→CPU re-materialisation readback, pre-draw dirty sweep
(`d3d9_common_texture.hpp:70-90`, `d3d9_texture.cpp:400-520`). Per-frame: 2.9
`MTLD3D9Texture::LockRect` + 2.9 `Surface::LockRect` (aw4:13613-13616), i.e. ~6 locks/frame.

### 1.3 The fork's BC mip clamp is **not** the cause — ruled out twice over
- Gate: clamp is `D3DPOOL_DEFAULT`-only (`d3d9_device.cpp:3259`,
  `IsCompressedFormat||Is3DcFormat) && Pool == D3DPOOL_DEFAULT && !RT && !DS && !AUTOGEN && !DYNAMIC`);
  Alan Wake's textures are MANAGED (§1.2).
- No `[mip-clamp]` line in **any** of the four logs, including the "auto on threshold=…" banner
  that `GetD3D9MipClampAutoConfig()` prints unconditionally the first time a candidate appears
  (`d3d9_device.cpp:115-118`). The feature never engaged.

Same for the other two fork commits named in the brief: no `[relief]` line and no mirror-eviction
line in aw4 (grep `relief|mirror|mip-clamp` → only the `[mirror-cache] ml1180 enabled=1
budget=8388608 max-resource=262144` banner, aw4:10682). So none of 3d404cc / 41fe66b / 8c9b571
had *observable* activity in the run that looked right. **That does not clear them** — it only
means their summaries were quiet; see §3.3.

### 1.4 aw4 ran with **full** x87 precision, and the game is x87-dense
`[cpu-split]`+`[rip-profile]` dump JIT machine code around the hot host PCs. Decoding
aw4:18018 (`0x166ffa080`, 95 samples) gives pushes/pops of **16-byte** slots
(`4cdf2fe4 4cdf2fe8 4cdf2fec 4cdf2ff8 4cdf2ffc` = `st1 {v4.2d}…`, `f84107ec` = `ldr x12,[sp],#16`,
`f801044c` = `str x12,[x2],#16`), plus `msr/mrs tpidr2_el0` (FEX thread-state) and `blr x3`.
The x87 stack slot is `OpSize::i128Bit` (16 B) in full precision and `OpSize::i64Bit` (8 B) in
reduced precision (`FEX/FEXCore/Source/Interface/IR/Passes/x87StackOptimizationPass.cpp:475,609`;
`X87F64.cpp` for the F64 leaves). 16-byte slots ⇒ **aw4 was `X87REDUCEDPRECISION=0`**, i.e. the
user's per-game file overrode the fork's ml950 default
(`FEX/Source/Windows/WOW64/Module.cpp:1132-1155`). Consequence: if the switch was the only thing
the owner changed between run 3 and run 4 (as reported), the A/B isolates x87 precision — and the
x87-stack-dominated hot block proves the guest spends its time in x87 code, so a precision change
lands squarely in the game's own math (geometry, culling, streaming/LOD), not in the renderer.

---

## 2. What reduced precision actually changes (confirmed, with sources)

- **Lossy by design.** Fork comment `FEX/Source/Windows/WOW64/Module.cpp:1132-1155`: full-precision
  x87 ops FEXCore cannot keep in a double go through softfloat thunks costing "20–50 % of ALL CPU"
  on a 32-bit D3D9 title; flipping it "roughly doubl[es]" frame rate. "x87 intermediates become
  53-bit instead of 64-bit … some geometry, collision and physics kernels, a few reduction loops
  can produce different results, and a guest that compares its own float output against a
  recorded value can disagree."
- **One rounding mode + one FTZ for x87 and SSE.** `FPCR.RMode`/`FPCR.FZ` are shared; `LDMXCSR`
  changes x87 results and `FLDCW/FLDENV/FRSTOR/FNINIT` change SSE rounding. Upstream
  FEX-Emu/FEX#1665 ("F64: MXCSR and FCW round modes mixed", open since 2022); measured table in
  athei/mach9#28. That issue states "no game is known to be affected", and FEX already landed
  "Keep the x87 control word out of FPCR.FZ" — check whether this tree has it before blaming FTZ.
  The x87-precision loss also applies to **integer** round-trips: FEX-Emu/FEX#5827
  (`FILD m64int` → `FISTP m64int`, no arithmetic in between, corrupts the value; maintainer:
  "Yep, this is expected because it's a hack"), which is how 2012-era code does 8-byte memcpy
  through the FPU. Same class is why *Batman: Arkham City* needs full precision
  (FEX#5827 comment, Droid-Deck/DroidDeck#792) — and Arkham *Asylum* runs on this build.
- **Coverage is not the problem**: `X87F64OpTable` and `X87F80OpTable` have the same 60 opcodes
  (`FEX/FEXCore/Source/Interface/Core/X86Tables/X87Tables.cpp:20,835`), so nothing falls off the
  table in reduced mode; what differs is numeric semantics, not decoding.
- **Granularity is per process, nowhere finer.** The decoder picks the table once per thread from
  the resolved config (`Frontend.cpp:75`), so there is no per-module and no per-thread switch.
  FEX's config *layers* do offer per-application files keyed by Steam app and executable —
  `Steam_<AppID>_<ProgramName>` app layers plus `FEX_APP_CONFIG` (a user-override JSON), all in
  `FEX/Source/Common/Config.cpp:495-514` — but they still resolve process-wide. Madeira's
  `Documents/madeira-fex.txt` → `FEX_X87REDUCEDPRECISION` is therefore already the narrowest lever
  that exists; anything narrower has to be a code fix in the opcode/IR layer (§6.3), not a knob.

**Why this can look like "textures missing", not just "numbers slightly off":** a 53-bit-mantissa
or wrong-rounding result inside texture-page selection / streaming priority / LOD choice selects a
different page than the loader filled, so the surface samples an unloaded (black/white) page;
the same wrongness at ~1e-3 scale is exactly what "slight glitches" describes. This is a
mechanism-compatible hypothesis, not a measurement — see §4.

---

## 3. DXMT-side candidates that remain (with code evidence)

### 3.1 ATOC / 8x MSAA — cosmetic, and identical across runs
See §1.1. Keep only as a footnote; nothing to fix for "missing textures".

### 3.2 VRAM budget / `GetAvailableTextureMem`
Budget is real and quiet in aw4: `[wmt] ml1042 video memory budget = 1536 MB` (aw4:3647),
`ml1075 … base 1536, footprint 791 of 6144 MB` (aw4:3657), trim line `ml1103 … 1536 MB below the
kill line` (aw4:3656). Game cfg asks for `DXMT_MAX_VRAM_MB=768` but `madeira.cfg vram-mb=1536`
wins (aw4:56-59, 199). Alan Wake logs no `EvictManagedResources`/`SetPriority` call
(`[d9-lock]`, `[d3d9-census]` and `[relief]` are all silent on them), and `GetAvailableTextureMem`
has **no log marker at all** in this frontend (0 hits in all four logs), so from the logs we
cannot say whether the game ever asks — a D3D9 title of this era usually does at startup.
That leaves "game sees 768 MB and silently drops texture quality" *untested* rather than excluded;
a fork-side budget story (§3.3) is better supported. Footprint at gameplay was ~1.7 GB
(`[xp] … fpMB=1769`, aw4:13601).

### 3.3 The managed-mirror / relief machinery is fps-amplified (highest-value renderer suspect)
Three facts, all from code:

1. **Eager mirror drop, then per-lock re-materialisation.** `noteLevelUploaded()` frees a MANAGED
   texture's CPU mirror the moment the last level is uploaded, unless the whole chain is ≤ 256 KiB
   (8 MB shared cache) or the app has read it back > 4 times: `d3d9_texture.cpp:438` + `:309`
   (`kMirrorReadEvictThreshold = 4`) + `:323` (`kMirrorRetentionBudget = 8 MB`). Alan Wake's
   streamed textures are far larger than the 256 KiB cap, so a texture that is written again after
   its chain completes has no mirror; the next Lock pays `ensureMirror()` (blank) +
   `materializeLevelForLock()` → `readbackSurfaceMirror[s]()` = flush + commit + CPU fence + GPU
   wait (`d3d9_texture.cpp:400-404, 474-520`), and `dropMirror()` resets `m_uploaded_mask = 0`, so
   the whole cycle repeats each time all levels are re-uploaded. The ml1980 batching knob
   (`MADEIRA_D3D9_MIRROR_BATCH=0`) exists precisely because this path was costing "~45 drains/s
   … serialising CPU and GPU".
2. **Every allocation can run the relief pass.** `Buffer::allocate` starts with
   `MadeiraRelieveTransientPools("Buffer::allocate")` (`dxmt/dxmt_buffer.cpp:152`), and relief
   fires whenever process headroom is under 1024 MB (`dxmt/dxmt_staging.hpp:162`), evicting
   staging spares **and live managed mirrors** (`d3d9_texture.cpp:672`, `[relief] mlP4 managed
   mirror evicted under pressure`).
3. Both are *per-operation* costs, so they scale with work per second. At 20–25 fps the game
   streams/locks ~5× more often per second than at 2–5 fps, the footprint climbs, headroom crosses
   1024 MB, and the drain/readback path starts firing continuously. [INFERENCE] for the
   fpMB/headroom numbers in run 4 — aw4 only gives the 2–5 fps snapshot (`fpMB=1769`, aw4:13601).

[INFERENCE] A texture whose mirror is dropped, then re-materialised from a GPU copy that a racing
Unlock has not yet published, uploads stale/blank bytes → the "missing textures" and the
"glitches". aw4 shows no `[d3d9-drain]`/`[relief]`/readback activity only because it ran at 2–5 fps
with a warm footprint; run 4 (fast) is exactly the regime where these fire, and its log is the one
thing missing.

**Latent bug found while reading this path (independent of x87):** the eager drop at
`d3d9_texture.cpp:438` checks only `m_uploaded_mask`, while the pressure eviction at
`d3d9_texture.cpp:672` correctly requires `m_uploaded_mask == m_all_levels_mask &&
m_needs_upload_mask == 0`. So a `NO_DIRTY_UPDATE` (or AddDirtyRect-deferred) write that set
`m_needs_upload_mask` can have its only copy (the mirror) freed by a later Unlock of *another*
level, after which the pre-draw sweep re-arms from a **blank** mirror. Alan Wake shows no
`NO_DIRTY_UPDATE` lock in the 24 logged lines (all read "upload locked rect on unlock"), so this
is probably not *this* bug — but it is a one-line fix and it is the same failure signature.

### 3.4 Bink / video
The Bink background drew while the screen was black in fullscreen (aw2/aw3) and the game presented
at 120/s, so the video path's *textures* and its MANAGED/plain surfaces work. Nothing in the logs
ties video to run 4.

---

## 4. Ranked likely causes

| # | cause | confidence | evidence |
|---|---|---|---|
| 1 | **FEX reduced-precision numeric divergence inside the engine** (53-bit mantissa, shared FPCR rounding/FTZ) changing texture-page/LOD/streaming decisions → sampling pages the loader never filled, plus geometry glitches | most likely [INFERENCE] | only changed variable; x87-dense guest (§1.4); mode documented as lossy (`Module.cpp:1132-1155`, FEX#1665, mach9#28, FEX#5827) |
| 2 | **Managed-mirror churn + relief-pass drains**, amplified by the 5× frame rate (§3.3) — renderer-side, not x87 | plausible [INFERENCE] | `d3d9_texture.cpp:438/309/323/672`, `dxmt_buffer.cpp:152`, `dxmt_staging.hpp:162` |
| 3 | FEX `FILD/FISTP m64int` data corruption inside a decompress/copy path (FEX#5827) | possible, unproven [INFERENCE] | upstream issue + maintainer confirmation |
| 4 | VRAM budget/reclaim (`vram-mb=1536`, 1024 MB relief floor) dropping large textures | possible [INFERENCE] | aw4:3647/3656/3657, fpMB=1769 |
| 5 | DXMT capability gap (ATOC, 8x MSAA) | **ruled out** | identical in the good run (§1.1) |
| 6 | BC mip clamp / fork clamp seams | **ruled out** for this title | DEFAULT-only gate (`d3d9_device.cpp:3259`), MANAGED textures, zero `[mip-clamp]` lines |
| 7 | Cube/volume mirror handling | **not applicable** | only the 2D leaf implements sweep/evict (`d3d9_common_texture.hpp:70-90`) |

---

## 5. Experiments — one variable each, in this order

0. **Re-run run 4 exactly as it was, but capture the log** (`/tmp/aw5.txt`). Without it every
   choice below is guesswork; with it, `[relief]`, `[mip-clamp]`, `[d9-drain]`,
   `[wmt] ml1075`, `[xp] fpMB` and any `OUTOFVIDEOMEMORY` immediately sort rows 1/2/4.
   Keep defaults on: `MADEIRA_D3D9_CENSUS`, `DXMT_D9_LOCKLOG`, `[splitlock]`, `[cpu-split]`.
1. **Does it depend on frame rate or on x87?** Keep reduced precision ON, add
   `env.MADEIRA_FPS_CAP=10` (per-game; `ConfigCatalog.generated.swift:500`; needs the `[xp]`
   sampler, i.e. `MADEIRA_PROBES` nonzero). Textures come back ⇒ cause 2/4 (timing/queue), not
   the x87 semantics. Stay bad ⇒ cause 1/3.
2. **Mirror/readback volume.** Reduced precision ON + `env.DXMT_D9_READBACK_STATS=1`
   (`d3d9_device.cpp:1750`). Compare against a full-precision run; also try
   `env.MADEIRA_D3D9_MIRROR_BATCH=0` (per-level readback) and `env.DXMT_D9_SMALL_MIRROR_CACHE=0`
   — a *change* in the symptom (better or worse) convicts §3.3.
3. **Budget.** Reduced precision ON, per-game cfg `vram-mb=3072` and `vram-trim-mb=0`
   (aw4:3656 documents the key; keep `DXMT_MAX_VRAM_MB` unset so one knob moves).
   Textures come back ⇒ cause 4.
4. **Engine-side load.** Reduced precision ON + in-game texture quality → Low
   (`%USERPROFILE%\Documents\Remedy\AlanWake\`, per PCGamingWiki). Fewer larger-page binds ⇒ a
   visible improvement points at streaming/page selection (cause 1).
5. **Control for cause 1 on a cool phone.** Full precision at ≥10 fps (lower resolution/settings,
   phone cooled) — if textures are also missing there, x87 reduced precision is innocent and the
   campaign is entirely renderer-side.

---

## 6. Code fixes

**Recommended first (diagnostic, tiny, no behaviour change under normal pressure)**
1. `dxmt/src/d3d9/d3d9_texture.cpp:438` — add the missing guard so the eager drop cannot free a
   mirror that is still the only copy of an app write:
   `if (m_uploaded_mask == m_all_levels_mask && m_needs_upload_mask == 0 && m_mirror_download_count <= kMirrorReadEvictThreshold)`
   (matches `:672`). One line, closes the §3.3 latent hole for every MANAGED title.
2. Make the mirror policy observable/testable instead of hard-coded: env knobs for
   `kMirrorRetentionBudget` (8 MB), the 256 KiB admission cap, and a
   `DXMT_D9_MIRROR_KEEP=1` "never drop a mirror" diagnostic. That turns experiment 2 into a
   two-run A/B and would confirm/refute §3.3 without a rebuild of the policy.

**Only if experiment 1 shows the symptom survives at 5–10 fps (i.e. it is really x87)**
3. `FEX/.../IR/Passes/x87StackOptimizationPass.cpp:994-1040` — extend the existing
   `FLD→FST` memory-copy elision to `FILD→FIST` (`FLOAT_FROMGPR_S` source + matching integer
   `StoreSize`): forward the GPR directly instead of round-tripping through the (now 53-bit)
   double. This is precisely what FEX#5827 asks for, it is valid in both precision modes, and it
   would kill the "8-byte memcpy through x87" corruption class while keeping the ~2× speed-up.
   Note the pass already tracks `Value->Source`, so this is a local change, not a new mechanism.
4. Not worth pursuing: a per-module/per-thread precision switch (FEX has none, and per-process
   per-game is already available); a per-opcode "F80 in F64 mode" mix (the 16 B vs 8 B stack slot
   is decided once per mode, `x87StackOptimizationPass.cpp:475,609`).

---

## Verdict for this slice

**Worth pursuing — but the next step is one diagnostic session, not code.**

- The renderer is *not* missing a feature Alan Wake needs: every capability it queried is
  answered, the two `D3DERR_NOTAVAILABLE` replies (ATOC, A16B16G16R16F 8x MSAA) are present in the
  run that rendered correctly, and the fork's BC mip clamp provably never engaged on this title.
  So "DXMT can't draw Alan Wake's textures" is off the table.
- The one variable that changed between a picture and no picture is FEX's x87 mode, which is
  documented as lossy *by its own authors* and is known to break 2012-era D3D9 titles of this
  genre. That makes cause 1 the leading explanation, with the fork's managed-mirror/relief path
  (cause 2) the credible renderer-side alternative — and both are separable with a single
  `MADEIRA_FPS_CAP` A/B plus a captured log.
- Do not ship `X87REDUCEDPRECISION=1` for this game until either the fps-capped run shows the
  textures return (renderer fixable) or fix 3 lands (precision cost removed). At 20–25 fps with
  holes in the world the game is not playable; at 2–5 fps it is not playable either, so the
  decision hinges on that A/B.
