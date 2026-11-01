# Where Esoteric Ebb's 6.1 GB goes: iOS footprint accounting, the swap tier, and the levers

Read-only investigation. Evidence: `/tmp/g2/dev/{ebbgame,ebb3,ebb4,ebb6,sig}.txt`, the fork's
`build/ntdll-unix/virtual_ios.c`, `dxmt/`, `app/Madeira/`, XNU (main branch, apple-oss-distributions),
Apple docs, upstream `willfaust/Madeira` PRs. Everything not marked **[INFERENCE]** is a line in a log
or a source line.

> **Review corrections (2026-11-01).** The footprint formula and the `external`
> exclusion hold (XNU `task.c:1224-1248`, `pmap.c:6509-6516`). Not as stated: the
> residual tracks Metal `currentAllocatedSize` only loosely (gaps up to 457 MB, ebb4
> c138; 198 MB, ebb6 c4), not "±150 MB in every run"; ebb4's JIT pool is 864 MB, not
> 880; death timestamps are ebb3 21:33:19.9 and ebb4 22:48:35.6; the 64 MB block burst
> is ebb6 23:04:01-02, the 128 MB one 23:05:00.8. §4's 4 B/texel BC census bug was fixed
> in dxmt `40bbd04`, after these logs; their census figures are pre-fix.

## 0. Ranked findings

1. **jetsam charges the XNU ledger `phys_footprint`, whose only terms are** `internal + internal_compressed
   + iokit_mapped + purgeable_nonvolatile(+compressed) + page_table − alternate_accounting`. File-backed
   pages are charged to a *different* ledger (`external`) and never enter the footprint; page tables are
   charged in proportion to mapped VA (≈1/2048), which is ≤ ~50 MB here. `osfmk/kern/task.c:1226-1248`.
2. **The "unexplained 2.1 GB" is `iokit_mapped` — DXMT's Metal/IOGPU memory, ≈3.0-3.2 GB.** The residual
   `phys − internal − compressed` is 3084-3112 MB in the steady state of ebb4/ebb6 and 3087-3094 MB in
   ebb3, and Metal's own `MTLDevice.currentAllocatedSize` at the same moments is 3136-3254 MB. The ticket's
   2.1 GB figure subtracts `external` (919 MB), which is not a footprint term at all.
3. **The JIT pool is charged in full at creation (`internal` = pool + ~90 MB at cycle 1, in all four runs),
   while only 346 of 880-892 MB is ever used.** That is 534-546 MB of charged, idle pool — the largest
   lever a config key can pull today (`pool-split=0` −288 MB; `pool = 448` −432 MB; lazy second region in code, same effect).
4. **Compression does not help the footprint**: `internal_compressed` is charged exactly like `internal`.
   Ebb's compressor holds 885-1012 MB of the game's heap at the end of every run and the footprint is
   unchanged by it — it buys RAM, not headroom. Only the file-backed tier (`external`) removes charge.
5. **The swap tier works but converts only ~0.3-0.4 GB here**: the one comparable measurement is `internal`
   — ebb3 (classic, no swap-images) ends at 1643 MB, ebb4/ebb6 (broad + swap-images) at 1213-1355 MB, i.e.
   288-430 MB of guest anonymous memory became file-backed (`external` residency 635-919 MB; it moves with
   writeback, so compare the `internal` side). 9.6 GB is "file-backed" because 100 whole 511 MB
   **reservations** are backed with ~900 MB of real disk (`st_blocks`); the guest's dirty heap sits in ranges
   the tier refuses (`fex/jit`).
6. **The 48/64/128 MB "forced to allocate new block" lines are DXMT's ring bump allocator, not Mono/Unity
   GC.** `dxmt/src/dxmt/dxmt_ring_bump_allocator.hpp:477` (exact string, also in upstream DXMT). They are
   per-upload oversized host blocks; the last two (2×128 MB) coincide with the final 255 MB footprint step
   that killed ebb6, and the 9×64 MB burst at 23:03:56 coincides with the 576 MB step (3357 → 4166 → 5407 within that second).
7. **The kill is a burst on top of a steady state that is already ~800 MB too high**: ebb6 sat at 5320-5437 MB
   from cycle 21 to the end, then went 5333 → 5794 → 6049 in the last 5 s (two 128 MB ring blocks + unlogged
   growth), i.e. 6055-6128 MB at death in every run. Saving ~700 MB in the steady state is enough to survive
   this workload; nothing here is an unbounded leak.

---

## 1. What iOS charges, and what each `[footprint]` field means

XNU's ledger comment (`osfmk/kern/task.c:1226-1248`) is the definition:

```
phys_footprint = (internal - alternate_accounting)
               + (internal_compressed - alternate_accounting_compressed)
               + iokit_mapped
               + purgeable_nonvolatile
               + purgeable_nonvolatile_compressed
               + page_table
```

Credit sites, not just prose:

| term | where credited | note |
|---|---|---|
| `internal` | `osfmk/arm/pmap/pmap.c:6549` at `pmap_enter`, only when `PMAP_OPTIONS_INTERNAL` (anonymous, non-file object) | one charge per physical page, however many times it is mapped |
| `phys_footprint` for the same page | `pmap.c:6577` `pmap_ledger_credit(...phys_footprint...)` | |
| `external` (file-backed: vnode, MAP_SHARED) | `pmap.c:6584` — **credits `external` and `phys_mem` only, never `phys_footprint`** | dirty or clean, written back or not, is irrelevant: the *page is not internal*, so it is never billed to the footprint |
| `page_table` | `pmap.c:1690-1710` `pmap_tt_ledger_credit()` credits **both** `phys_footprint` and `page_table` by the table's size | 16 KB page granule ⇒ 16 KB table per 32 MB of mapped VA |
| `iokit_mapped` | `osfmk/vm/vm_map.c:22253-22268` `vm_map_iokit_mapped_region()` credits `iokit_mapped` **and `phys_footprint` by the whole mapping size at map time** | this is how GPU/IOGPU/IOSurface memory is billed: the size, not the residency |
| compressor | `internal_compressed` = "amount of this task's internal memory which is held by the compressor" (`task.c:1244-1247`) | counted in the footprint in full |
| jetsam | `bsd/kern/kern_memorystatus.c:1217-1218` (`get_task_phys_footprint` vs `task_get_phys_footprint_limit`) and `:5054` `memorystatus_on_ledger_footprint_exceeded()` | the limit compares the ledger, which is why `TASK_VM_INFO.phys_footprint` is the right instrument |

`TASK_VM_INFO` field sources (`task.c:6039-6150`): `internal` ← ledger *internal*; `compressed` ← ledger
*internal_compressed*; `external` ← ledger *external*; `reusable` ← ledger *reusable*;
`phys_footprint` ← `get_task_phys_footprint()` (the same ledger jetsam reads).

So Madeira's line (`build/ntdll-unix/virtual_ios.c:1294`, built at `:1242-1300`) maps 1:1:

| field | meaning for us | ebb6 at cycle 47 |
|---|---|---|
| `phys` | the number that kills | 5333 MB |
| `internal` | anonymous resident: JIT pool + Wine/FEX/guest anonymous heap | 1355 MB |
| `compressed` | the same heap after the compressor took it (still charged) | 885 MB |
| `external` | **file-backed, NOT in `phys`**: swap-tier file pages, mapped PE files, image sections | 919 MB |
| `reusable` | `VM_PURGEABLE`/reusable-tagged anon (counted inside `internal`) | 0 |
| *residual* | `phys − internal − compressed` = `iokit_mapped + page_table + purgeable_nonvolatile − alternate_accounting` | **3093 MB** |

### 1a. The residual is Metal, not page tables

Page tables are bounded by VA, not by region count: 16 KB of table per 32 MB mapped
(`pmap.c:1690-1710`). The log's own hole census says how much VA is mapped below 64 GB —
`[holes<64G] rev=ml894 free=0 MB largest=0 MB` (ebb6 cycle 30, line 19649) — i.e. ≈63 GB mapped, which is
63 GB / 32 MB × 16 KB ≈ **32 MB** of tables; the guest/FEX bands add a few more. The counter-example is in
the corpus: `sig.txt` has 119 470 regions (more than ebb's 114 994) and a residual of **30 MB** (peak 3287,
`phys 2309 / internal 1895 / compressed 384`). Page tables cannot be the 3 GB.

Metal can, and the log has Metal's own total. `[mem-census]` prints `MTLDevice.currentAllocatedSize`
(`dxmt/src/dxmt/dxmt_mem_census.hpp`), the "total amount of memory the GPU device is using for all of its
resources" (Apple: MTLDevice.currentAllocatedSize):

| run / moment | residual (phys−int−comp) | Metal currentAllocatedSize |
|---|---|---|
| ebb6 23:03:32 c4 | 263 | 65 (sampled before the burst) |
| ebb6 23:03:49 c13 | 1329 | 1389 |
| ebb6 23:03:56 c19 | 2884 | 2820 |
| ebb6 23:04:26 c31 | 3112 | 3254 |
| ebb6 23:04:56 c46-47 | 3093 | 3175 |
| ebb4 22:47:52 c145 | 2961 | 3202 |
| ebb4 22:48:22 c155 | 3086 | 3139 |
| ebb3 21:31:39 c36 | 3088 | 3138 |
| sig 21:58 (2D Unity) | 30 | (no census) |

The residual tracks Metal within ±150 MB in every run, and the 1.9 GB rise at 21:31:17-21:31:39 in ebb3 is
Metal going 1185 → 3138 MB (the scene's texture set). Apple states the mechanism: "On devices with Apple
silicon, accessed Metal resources also fall into this category [anonymous dirty memory]… because CPU and
GPU share the same pool of fast unified memory" (WWDC22 session 10106, "Profile and optimize your game's
memory"); and "iOS and tvOS monitor your app's total memory usage at runtime, and if the amount exceeds a
predetermined limit, the system terminates your app" (`docs: Reducing the memory footprint of Metal apps`).
`iokit_mapped` is the ledger term that implements it (`vm_map.c:22253`).

**[INFERENCE]** The last ~50-150 MB of the residual is `page_table` (see the bound above) plus the handful
of purgeable CA/Metal surfaces; `iokit_mapped` alone is therefore ~3.0-3.1 GB. Precision here is not
decision-relevant: no term in the residual can be *reclaimed* except by DXMT creating fewer Metal
resources, because the credit is by mapping size at creation and nothing in the app can unmap a texture the
game still owns.

### 1b. Why `internal` at cycle 1 already contains ~880 MB

`phys 985 / internal 973` at the first `[footprint]` (ebb6:576) is one second after the pool was handed
over by the debugger (`[pool-split] pair placed… 880 MB in all`). The pool is charged in full
before any game code runs. Correlation across the four runs (first `[footprint]` line vs pool size):

| run | pool span | `internal` at cycle 1 | excess |
|---|---|---|---|
| ebbgame | 384 MB | 476 | 92 |
| ebb3 | 864 MB | 970 | 106 |
| ebb4 | 880 MB | 944 | 64 |
| ebb6 | 880 MB | 973 | 93 |

and the `[phys-map]` band census at cycle 2 says the pool is fully resident and dirty —
`poolRX=384/384 … poolRW=384/384` (ebbgame), `poolRX=880/880 poolRW=880/880` (ebb6),
`poolRX=864/864` (ebb3/ebb4) — while the bump allocator had used ~41 MB (`used=0x2750000/0x37b80000`).
At cycle 30 the pool's residency has dropped to 505-507 MB (the compressor took ~370 MB of it) while its
dirty count stays 864-881 MB. The fork already documents the cause:
`app/Madeira/StikJITHelper.swift:1044-1046` — "Costs the second region's size in footprint (debugger-blessed
pages are dirty from birth)". **[INFERENCE]** the debugger's `jit26_prepare_region` path faults the region;
the observation is measured, the mechanism is not (see the 2-minute check in §6).

Corollary: the RW alias (`poolRW`) is the *same* VM object and is **not** double-charged — `internal` at
cycle 1 would be 1760+ otherwise. The `[no-footprint]` failures (`virtual_ios.c` → `JITAllocator.c:229-315`)
therefore cost nothing today; they only mean the pool cannot be moved *out* of the footprint.

---

## 2. Time series, and what grows before each kill

Death footprints (`[xp] fpMB`, last line of each log): ebb3 **6128 MB** (killed 21:33:00, ~2.5 min),
ebb4 **6055 MB** (22:48:22, ~5 min), ebb6 **6049 MB** (23:05:01, ~1.5 min); ebbgame survived 4 min at
2810 MB (peak 3115). The line is 6144 MB: `ml992: os_proc_available_memory=5170 MB + phys_footprint=973 MB
= 6144 MB` (ebb6:306).

ebb6, per `[footprint]` cycle (internal/compressed/external in MB):

| t | cycle | phys | int | comp | ext | residual |
|---|---|---|---|---|---|---|
| 23:03:26 | 1 | 985 | 973 | 0 | 85 | 12 |
| 23:03:32 | 4 | 2367 | 1811 | 293 | 450 | 263 |
| 23:03:32 | 7 | 3517 | 1806 | 508 | 473 | 1203 |
| 23:03:49 | 13 | 3445 | 1610 | 506 | 705 | 1329 |
| 23:03:56 | 19 | 4756 | 1066 | 806 | 637 | 2884 |
| 23:03:56 | 22 | 5407 | 1360 | 957 | 780 | 3090 |
| 23:04:26 | 31 | 5437 | 1370 | 955 | 794 | 3112 |
| 23:04:56 | 47 | 5333 | 1355 | 885 | 919 | 3093 |
| 23:05:00-01 | fast | 5794 → 6049 | – | 968 → 980 | – | – |

The phases are the same in all three runs:

1. **0-8 s — pool + GPU load.** `internal` jumps to pool+90 (pool charged); `external` 85→450 as the swap
   tier and x64 images come in; the residual is still small.
2. **4-30 s — the scene's textures.** Metal 65 MB → 1389 MB → 2820 MB → 3254 MB; residual 12 → 1329 → 2884
   → 3112. The 9×64 MB ring-block burst in this window (`23:03:56`, ebb6 lines 18006-18154) lands on top:
   phys 3357 (c16) → 4166 (18) → 4756 (19) → 5281 (20) → 5414 (21) = **+2.0 GB in one second**, of which 576 MB is the
   ring blocks and the rest is Metal and heap pages that the compressor then takes.
3. **30 s - end — flat at 5320-5437 MB.** The compressor moves ~1.4 GB of the game's heap from `internal`
   to `compressed` (internal 1811 → 1355, compressed 293 → 885) and the footprint does not move: it is the
   same charge. `[dc-census]` agrees that small reclaims are cosmetic: `dirty 336KB->16KB … fp 1143MB->1143MB`.
4. **Death — a burst.** Two 128 MB ring blocks at 23:04:56 (`warn: forced to allocate new block of size
   134217728`), then phys 5333 → 5794 (+461) → 6049 (+255) in ~5 s, then SIGKILL at ~6055-6128 MB.

Net: steady state ≈5.33 GB = 0.88 pool + 0.48 guest anon + 0.89 compressed heap + 3.09 GPU. The kill needs
only a ~0.7 GB cut, and the last second needs the burst to be bounded too.

---

## 3. Why 9.6 GB of "swap" does not lower `phys`

**Answer to the direct question: no.** A `MAP_SHARED` file page is charged to `external` at `pmap_enter`
(`osfmk/arm/pmap/pmap.c:6584`) and never to `phys_footprint` — writeback state does not matter, and the
compressor never sees it. The fork measured this on the device before building the tier (ml1076 canary,
`build/ntdll-unix/virtual_ios.c:20965-20975`): "512 MB written through a shared mapping of an unlinked temp
file → footprint +2 MB". The cross-check is in this run's own numbers: 9603 MB file-backed
(`[swap] ml1077 stats: 9603 MB file-backed now … disk 713 MB`, ebb6:19659) with a 5333 MB footprint is only
possible if file-backed pages are uncharged.

So why is the tier's *effect* so small here, and why does `disk` read 713 MB?

- `file used 9611 of 131072 MB` is the **offset space** (`ios_swap_take`/`ios_swap_bump`, 128 GB sparse,
  `virtual_ios.c:21150-21160`). `disk 713 MB` is `st_blocks × 512` (`ios_swap_disk_used`, `:21843-21847`).
- `reserve-backed 100 (9828MB)` — broad coverage backs **whole reservations**: 100 of them, 9828 MB,
  dominated by 18 × 511 MB `MEM_RESERVE` blocks (`[bigres] … total=9215 MB`, ebb6:18226-18269). Those pages
  are `PROT_NONE` and mostly never committed: the file's pages are only allocated when committed **and**
  dirtied, hence 713 MB of disk for 9.6 GB of VA.
- The commits that actually happen are mostly in ranges the tier refuses. `[swap] census … commit MB by
  reason: backed=241 small=69 … fex/jit=8548` (ebb6:22455). `ios_swap_why` (`:21416-21430`) refuses
  `VPROT_EXEC`/`WRITECOPY`/`GUARD`, non-`valloc` views, and anything overlapping the FEX arena or the JIT
  pool (`ios_swap_is_fexjit`). [INFERENCE] a large part of that 8.5 GB counter is the JIT/FEX code traffic
  (the counter accumulates *request bytes*, repeatedly, so it is a traffic mix, not live memory — do not
  read it as "8.5 GB is missing").
- The FEX arena reserves ~221-240 × 16 MB spans (`[span-census] … live=224`, 0x7c01000000+0x1000000) but is
  only ~112 MB resident (`[phys-map] bands … fex=230/112`), so the arena is a VA consumer, not a footprint
  consumer — it is not the missing memory either.

What the tier *did* buy, measured inside one config family: ebb3 (classic, swap-mb 4096, no swap-images)
ends with `internal 1643 / external 777`; ebb4 (broad + swap-images) `1213 / 635`; ebb6 `1355 / 919`.
**288-430 MB less anonymous.** (`external` is residency, not coverage — it fluctuates with writeback, so the
`internal` column is the one to compare.) Upstream's own numbers: Metro 2033 Redux
peak 2717 MB with broad vs ~3.3 GB without, 3.6 GB of reservations using ~630 MB of disk; Ori 494 s
without jetsam, peak 3981 MB, 1661 MB file-backed (`willfaust/Madeira#179`).

Two doc claims need correcting, and one is load-bearing:
`docs/madeira.cfg.example:7-8` says the tier maps guest memory from a file "which iOS does not charge to the
jetsam footprint" — true for the *pages that are committed and file-backed*, but it reads as if the whole
backed range is free. It also does not mention that `broad` backs reservations whose commits never arrive
(this run: 9.6 GB backed, 713 MB of disk) or that `swap-mb` caps disk, not VA.

---

## 4. The 128 MB "blocks": DXMT's ring allocator, not the Mono GC

`warn:  forced to allocate new block of size 134217728` is emitted by
`dxmt/src/dxmt/dxmt_ring_bump_allocator.hpp:477` (`WARN("forced to allocate new block of size ", block_size)`),
in `RingBumpState::allocate_or_reuse_block` — a ring that needs a block larger than any reusable one
allocates `max(requested_size, ring_block_size)`. On this device `kStagingBlockSize = 0x2000000` (32 MB,
`:22-27`); the logged 48/64/128 MB sizes are single oversized uploads (one `UpdateSubresource`/upload
larger than a block), allocated as a host `malloc` **plus** a placed Metal buffer
(`StagingBufferBlockAllocator::allocate`, `:300-340`), so they are charged as anonymous host memory and
count in `internal`.

Per-run census (all lines, grep `forced to allocate`):

| run | block sizes | total |
|---|---|---|
| ebb3 | 1×128, 2×48, 10×64 | 864 MB |
| ebb4 | 3×128, 2×48, 10×64 | 1120 MB |
| ebb6 | 2×128, 2×48, 9×64 | 928 MB |

and they are *bursts*, not a leak: ebb6's 9×64 MB all land at 23:03:56, in the same second the footprint
steps 3357 → 4166 → 5407; the 2×128 MB land at 23:04:56, in the second the footprint steps out of its plateau
(5333 → 5794 → 6049). They are freed when the ring's sequence passes them (`free_blocks`, `:437-457`), so
each burst is transient — but transient is enough when the steady state is 800 MB from the line.

There is no Mono/Unity GC evidence in these logs at all: the only runtime message is the DXMT one, and
`sig.txt` (Unity too) has zero. What the Unity heap does show is `internal`+`compressed` ≈ 1.36 GB at steady
state, and it stops growing after ~30 s — the game is not leaking; it is simply bigger than the budget.

Two instrument bugs found in the same area, both worth fixing before the next run:

- **`[mem-census] tex-private live=8543MB` is an over-count.** `mem_census_texture_bytes()` /
  `mem_census_texel_bytes()` (`dxmt/src/dxmt/dxmt_mem_census.hpp:232-262`) charge the *decoded* size for
  every BC format because "on A15 every BC format is remapped by `remap_unsupported_bc()`". This device is
  an **A17 Pro (AGXG16)** and the log says `[iOS DXMT] supportsBCTextureCompression = YES`
  (ebb6:11777), so BC textures are *not* remapped: BC1/BC4 are counted at 4 B/px instead of 0.5 (8×),
  BC3/5/7 at 4 instead of 1 (4×). Metal's `currentAllocatedSize` (3175 MB) is the authoritative number;
  the census "LIVE=8785MB" must not be quoted as texture memory.
- The **`mtl` "LIVE" vs "Metal" gap** is therefore not "requested capacity vs residency" — it is mostly
  this per-format error.

The `ml992` clamp (`virtual_ios.c:24829-24920`) reports `MmHighestPhysicalPage` = 6144 MB (the measured
`os_proc_available_memory + phys_footprint`), so `GlobalMemoryStatusEx.ullTotalPhys` = 6144 MB; `totalphys`
overrides it. `avail-phys` (`:24698-24770`) instead rewrites `ullAvailPhys` to "what remains before the
limit", with the documented throttled ladder (<400 MB critical / <1000 MB moderate) for Chromium. Neither
changes the GPU allocations here: ebb3 (budget 1024) reached 3138 MB of Metal and ebb4 (budget 2304) 3376 MB
— the reported video budget does not constrain this engine (see §5.1).

---

## 5. Levers, ranked by expected MB

### 5.1 Config-only (no reinstall; exact keys, global vs per game)

| # | lever | where | expected MB | evidence |
|---|---|---|---|---|
| 1 | `pool-split = 0` | game file (or madeira.cfg) | **−288** | log: "the single-region pool would have been 592MB"; span 880 → 592. Pool used only 346 MB (`used=0x159e1000/0x37b80000`) |
| 2 | `pool = 448` (with `pool-split = 0`) or `pool = 512` with split | game file | **−432 / −368** | pool is charged 1:1 (§1b); 346 MB used leaves 100/165 MB headroom. Do not go below 400: ebbgame ran with 384 and used 335 (87 %) |
| 3 | `env.MADEIRA_JIT_DUMP` unset/0 | env | **−0 to −600 (keep off)** | `#179`: reading the untouched pool alias to dump charged ~600 MB and Hollow Knight was killed 4 s later; opt-in since ml1242 |
| 4 | `env.DXMT_SMALL_RINGS = *` | env (dxmt) | **−30 … −300** | 32 MB → 4 MB ring blocks; `init-upload` peaked 354 MB and `staging-ring` 40 MB in ebb6; upstream measured 132 MB + 68 MB held through a session (`dxmt_ring_bump_allocator.hpp:40-58`). Does **not** cap oversized blocks |
| 5 | `totalphys = 4096` | game file | **unknown, potentially large** | Unity sizes streaming/quality from `SystemInfo.systemMemorySize` = `GlobalMemoryStatusEx.ullTotalPhys` (ml992 clamps to 6144 today). A/B worth one run; risk: an engine that gates on ≥6 GB [INFERENCE] |
| 6 | `avail-phys = 1` | game file | **0 … ?** | makes `ullAvailPhys` = remaining headroom; the only lever that lets the engine itself react (proven for Chromium, not for Unity). Costs nothing, so try it |
| 7 | `swap-mode = 2`, `swap-min-mb = 1`, `swap-images = 1` + `env.MADEIRA_X64_IMAGE_NOCOPY = 1` | game file | **−290 … −430 (already in use)** | ebb3 vs ebb4/ebb6 internal 1643 vs 1213-1355 |
| 8 | `swap-mb` 6144 → 3072 | game file | 0 (footprint), −disk | 713 MB of disk in use; the cap is on `st_blocks` (`:21843`), never approached |
| 9 | `vram-mb` / `vram-trim-mb` / `ram-reserve-mb` | — | **0** | Metal total was 3138/3376/3254 MB for budgets 1024/2304/1536; the trim needs the game to re-query DXGI, and Unity queried **once** (`[wmt] ml1075 … 1 queries so far`, ebb6:3588, and no later `[wmt]` line although the budget should have fallen to ~811 MB). `ram-reserve-mb` is inert here: cap 6145 ≥ limit 6144 |
| 10 | `env.MADEIRA_FREE_DELAY_MS = 0` | env | 0 (avoid a regression) | it *holds* released 1-16 MB guest blocks mapped; upside is CPU, downside is footprint |
| 11 | `arena-mb` | game file | 0 footprint (VA only) | FEX arena is 112 MB resident of 3.5 GB reserved (`fex=230/112`); only useful when a VA hole is the problem (`virtual_ios.c:30846-30880`) |
| 12 | `quiet-log`, JIT dump size, log verbosity | — | ≈0 | log traffic, not memory |

Do not expect anything from `vram-mb` for this title. The one config line worth trying *because it is free*:
`vram-mb = 512` together with `env.MADEIRA_DXGI_BUDGET_EVENTS = 1` — if the engine ever subscribes, the
event path (`dxmt/src/dxgi/dxgi_adapter.cpp:25`) is the only way a shrinking budget reaches it.

### 5.2 Code changes (file:line, minimal patch, expected log evidence)

| # | change | where | expected | evidence to look for |
|---|---|---|---|---|
| A | **Take region B lazily.** `pool-split` takes the second debugger region eagerly at startup (880 MB span, 534 MB idle). Ask for it only when the bump crosses region A's end, or not at all when `pool <= region A`. | `app/Madeira/StikJITHelper.swift:1003-1105` (`takeSecondRegion`, `mapSplitAlias`) | **−288 MB** for this title, no config change for other titles | `[pool-split]` absent; `internal` at cycle 1 smaller by 288 MB; `[phys-map] poolRX=592/…` |
| B | **Bound oversize ring blocks.** In `allocate_or_reuse_block`, clamp `block_size` to `kStagingBlockSize` (or 16 MB) and satisfy larger uploads by chaining several fixed blocks, or route one-shot uploads through a dedicated upload heap that is released at the frame boundary. Precedent: `naive17/kitsune-ios:patches/dxmt/0010-dxmt-bound-staging-and-dynamic-buffer-memory.patch`. | `dxmt/src/dxmt/dxmt_ring_bump_allocator.hpp:418-480` | **−256 MB at the kill step** (ebb6 2×128 MB); ebb4's burst held 3×128 + 2×48 MB, ebb3's 1×128 + 2×48 + 10×64 | `forced to allocate new block of size` disappears for ≥16 MB; `internal` at the 23:04:56 step does not jump 461 MB |
| C | **Keep the upload heap small.** `init-upload` peaked 354 MB (ebb6) / 1122 MB requested; the resource initializer's upload/zero heap is retained 300 submissions. Cap it (small rings already parameterised) and punch it back after a load. | `dxmt/src/dxmt/dxmt_resource_initializer.cpp` (`MEMOWN_INIT_UPLOAD`), `dxmt_ring_bump_allocator.hpp:40-58` | **−100 … −300 at load peaks** | `[mem-census] init-upload peak=` falls |
| D | **Make `[mem-census]` honest.** `mem_census_texel_bytes()` must ask the device (`supportsBCTextureCompression`) or use `MTLTexture.allocatedSize`; the BC→RGBA assumption is A15-only. | `dxmt/src/dxmt/dxmt_mem_census.hpp:232-262` | 0 MB, but every future "who owns the gigabyte" conclusion depends on it | `tex-private live` ≈ Metal `currentAllocatedSize` for BC-heavy scenes |
| E | **Evict on pressure (the only GPU lever).** DXMT creates 908 private textures and frees 39 (ebb6:22149). Add a budget check at texture creation: when `Metal currentAllocatedSize + new > budget`, invalidate the least-recently-used textures the game has released (`D3D11_USAGE_DEFAULT` with no live view) or force `setPurgeableState(.volatile)` on the ones DXMT owns (read-back staging, presenter, init-upload). Volatile memory is explicitly not charged (Apple: "doesn't count them toward the memory limit"). | `dxmt/src/dxmt/dxmt_texture.cpp`, `dxmt/src/d3d11/d3d11_texture.cpp` + the budget hook in `dxmt/src/winemetal/unix/winemetal_unix.c:415` | **unknown, 0 … 1 GB** — only the engine's own working set can be returned; needs the census fix (D) to measure | `tex-private live` falls without the game failing; `residual` falls |
| F | **The swap tier cannot help the GPU or the pool** — do not spend effort there before A/B/C. If anything, extend coverage to guest commits adjacent to (not inside) the FEX arena, since 5.4 GB of reservations are skipped as `fex/jit/band`; but the excluded ranges are executable/FEX-owned by construction (`virtual_ios.c:21416-21430`), so this needs a per-range census first. | `build/ntdll-unix/virtual_ios.c:21416` | 0 today; up to ~0.5 GB if a writable non-exec range is being refused | a new `[swap] refused-range` line with base/size/prot |
| G | **Pool out of the footprint.** The kr=4 ladder fails because the entry returned for the RW alias covers **16 KB of 592 MB** (`[no-footprint] … entry covers only 16384 …`): the alias is a debugger/shared mapping, not a plain anonymous object, so `mach_make_memory_entry_64` hands back a partial copy entry and `mach_memory_entry_ownership` rejects its kind. Attacking this needs the pool created as an object *we* own (VM_LEDGER_FLAG_NO_FOOTPRINT at `MAP_MEM_NAMED_CREATE` time, as `jit_region_create` already does and which succeeds) with the debugger only blessing the RX view — then the charge would be 0 instead of 880 MB. **[INFERENCE]** not proven on device; it is the only route to the full 880 MB. | `app/Madeira/JITAllocator.c:104-175` vs `StikJITHelper.swift:1003-1105` | **−880 MB if it works**, otherwise 0 | `[no-footprint] … ownership OK … delta −880 MB` at pool creation |

Two measurement actions that must precede B/E and that cost one run each:

1. **`pool = 448` (or `pool-split = 0`)**: if `internal` at cycle 1 falls by 432 (or 288) MB and
   `[phys-map] poolRX` follows, the "dirty from birth" charge is confirmed and lever 2 is safe. If it does
   not move, the pool is lazily faulted and only the *used* pages are charged — then the 973 MB at cycle 1
   is something else and §1b needs redoing.
2. **`env.DXMT_SMALL_RINGS = *`**: read `[mem-census] init-upload peak` and `staging-ring peak`; if they
   drop to <100 MB the load burst (which is what pushed ebb4 to 5586 and ebb6 to 5437) shrinks.

---

## 6. Appendix: the numbers behind the tables

- `[phys-map] bands rev=ml360 (dirty/res MB)` ebb6 cycle 2: `poolRX=880/880 poolRW=880/880 hostlow=104/1012
  guest=82/172 pa=0/0 fex=26/111` (line 6418); cycle 30: `poolRX=881/507 poolRW=880/505 hostlow=297/547
  guest=645/460 pa=139/505 fex=230/112` (line 19655), `regions=122739 total_dirty=3074`.
- `[phys-map] tag 0 totals … dirty=2601 res=2462 swap=1034` (cycle 30) — the walk's "dirty" includes
  file-backed dirtied pages and counts the pool twice (both bands), which is why it exceeds
  `internal+compressed` and must not be compared to the ledger.
- `[swap] ml1077 stats` evolution, ebb6: 51 MB file-backed (cycle 2) → 8403 MB (23:03:56) → 9603 MB
  (23:04:26, disk 713 MB) → unchanged; `[swap] census … reserve-backed 100 (9828MB) … disk=903MB`.
- `[wmt] ml1042 … budget = 1536 MB (limit 0, footprint 0, Metal recommends 5461 MB)` and
  `ml1103 trim starts 1536 MB below the kill line`; only one `ml1075` line (1 query), so the trim never ran.
- `ml992` line, ebb6:306; `ml993` path exists (`memorystatus_control(GET_MEMLIMIT_PROPERTIES)`) but the
  measured `os_proc_available_memory + footprint` answer is what gets used (5170 + 973 = 6144).
- `[bigres]` 18 × 511 MB reservations, `total=9215 MB` (ebb6:18226-18273) — matched by the 9828 MB of
  whole-reservation backing.
- `[span-census]` FEX spans 0x7c01000000 + 16 MB, `live=224` at peak → ~3.5 GB reserved in the FEX band,
  of which `[phys-map] fex=230/112` is resident.
- Upstream precedent: `willfaust/Madeira#179` (broad coverage: Metro 2717 vs ~3300 MB; Ori 3981 MB peak with
  1661 MB file-backed; JIT-pool dump reading untouched pages charged ~600 MB), `#219` (low-RAM devices need
  the tier; page-crossing store freezes), `#323` (`swap-min-kb` floor). The DXMT ring warning string and
  the "bound staging and dynamic buffer memory" patch exist upstream in `thebcd69/bcd-games` and
  `naive17/kitsune-ios` respectively.
