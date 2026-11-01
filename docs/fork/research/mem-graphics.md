# Graphics memory on iOS: DXMT / wined3d / d3d9-emulated

Scope: how D3D9/D3D11 resources become Metal memory, what the VRAM knobs actually
do, and which levers could save MB. Evidence is `file:line` in this tree, log lines
from `/tmp/g2/dev`, and Apple/upstream docs. Anything not directly observed is
marked `[INFERENCE]`.

> **Review correction (2026-11-01).** `ram-reserve-mb` is not reporting-only: it
> feeds `madeira_avail_memory`, which drives the D3D11 mip clamp
> (`d3d11_texture_device.cpp:509`), the P4 relief pass (`dxmt_staging.cpp`) and
> mirror eviction. The D3D9 mirror cache budget is 8 MB since dxmt `41fe66b`.

## 0. Answer in one paragraph

Every knob the fork exposes (`vram-mb`, `vram-trim-mb`, `ram-reserve-mb`,
`DXMT_MAX_VRAM_MB`) only changes **numbers handed to the guest** — DXGI
`DedicatedVideoMemory` / `QueryVideoMemoryInfo.Budget`, D3DKMT segment size, and
D3D9 `GetAvailableTextureMem`. Nothing in the Metal allocation path reads them, so
they do not lower resident Metal memory. Proof from the logs: Esoteric Ebb ran with
budgets 1024 / 2304 / 1536 MB and died at phys_footprint 5896 / 5586 / 5437 MB
respectively, while Metal's own `currentAllocatedSize` reached **3175 MB** under a
1536 MB budget, and the game queried the budget exactly **once** per run
(`ml1075 ... 1 queries so far`), so even the dynamic trim never fired. The only
graphics lever in the tree that reaches Metal is the **BC mip clamp** (`ml675` /
`ml2000`), and it is off by default for 64-bit modules.

## 1. Which D3D path each title uses (from the logs)

| Title | Path | Evidence |
|---|---|---|
| Esoteric Ebb (Unity, 64-bit) | DXMT **d3d11.dll** (sysx64) → winemetal → Metal | `/tmp/g2/dev/ebb6.txt:9284` (`d3d11.dll -> sysx64\d3d11.dll`), `:11777` `[iOS DXMT] supportsBCTextureCompression = YES ... AGXG16Device`, `:11797` `dxmt-encode-thr` |
| SIGNALIS (Unity, 64-bit) | same DXMT d3d11 | `/tmp/g2/dev/sig.txt:12125`, `:12245`, `:12277` |
| Batman: Arkham Asylum (32-bit UE3) | i386 `d3d9.dll` = DXMT **shim** → `d3d9-emulated.dll` = DXMT's i386 D3D9 frontend (FEX) → winemetal's 32-bit unixcall table | `/tmp/g2/dev/main6.txt:9424` (`[d3d9] MADEIRA_D3D9 unset: forwarding to d3d9-emulated.dll`), `:11950` (`d3d9-emulated.dll` load), `:12014` `driver="DXMT (Metal)"`; design: `docs/WOW64.md:145,157-170` |
| — never wined3d | wined3d's GL backend fails and is not what renders | `main6.txt:11991` `wined3d_adapter_gl_init Failed to get a GL context`, then `:12014` DXMT caps; `docs/WOW64.md:181` (`d3d9 = wined3d` is opt-in) |

`madeira-d3d12` (the Metal-based D3D12 runtime) is **not** in these runs:
`ebb6.txt:104` `madeira-d3d12: gate off (madeira.cfg d3d12 unset)`.

## 2. Resource → Metal, with the double-store accounting

Chain (all titles): PE `d3d9.dll`/`d3d11.dll` → `winemetal.dll` thunks
(`dxmt/src/winemetal/winemetal_thunks.c`) → `__wine_unix_call` →
`dxmt/src/winemetal/unix/winemetal_unix.c` (the unix side; 32-bit callers get
`dxmt_winemetal_unix_call_wow64_funcs`, `winemetal_unix.c:6997-7010`) → Metal.
Object model: `dxmt/src/dxmt/dxmt_texture.cpp` / `dxmt_buffer.cpp`; `Texture` /
`Buffer` own a `TextureAllocation` / `BufferAllocation` and swap it on `rename()`.

### Textures
* D3D11 (`dxmt/src/d3d11/d3d11_texture_device.cpp:610`): one `MTLTexture`.
  Storage mode by usage — DEFAULT/IMMUTABLE → `WMTResourceStorageModeManaged`,
  DYNAMIC/STAGING → `Shared` (`d3d11_resource_helper.cpp:383-397`). On iOS
  "Managed" does not exist and is treated as unified/shared —
  `winemetal_unix.c:5496` ("Managed storage mode doesn't exist on iOS (unified
  memory)"). **No CPU-side copy of a D3D11 texture is retained.**
* D3D9 (`d3d9_device.cpp:3120-3197`): one `MTLTexture`, `Private` for
  `D3DPOOL_DEFAULT`, `Shared` for SYSTEMMEM/SCRATCH/MANAGED.
* D3D9 `D3DPOOL_MANAGED` is the **only double-stored path**: the Shared texture
  *plus* a host mirror (`guest_alloc` + a Shared `MTLBuffer` wrapping those pages,
  `d3d9_texture.cpp:233-300`), because UnlockRect stages from the mirror and never
  aliases the sampled pages (`d3d9_device.cpp:3146-3175`). Retention is bounded:
  small mirrors cached up to 32 MB (`d3d9_texture.cpp:316`), mirrors released after
  4 read-backs (`:309`), retired mirrors returned to a device pool capped at
  64 MB / 128 entries (`d3d9_device.hpp:1525,1529`).
* BC formats are **not** expanded on this device: `supportsBCTextureCompression =
  YES` (`ebb6.txt:11777`), and `remap_unsupported_bc()` returns early
  (`winemetal_unix.c:926-928`). The RGBA8-decode path (`dxmt_resource_initializer.cpp:232-252`)
  is an A15 workaround and is inactive here.
* D3D9 only: an sRGB-sampling texture gets `WMTTextureUsagePixelFormatView`
  (`d3d9_device.cpp:3126-3136`), which the comments state opts that texture out of
  AGX lossless compression — a real footprint cost, and one the D3D11 path does not
  pay (it uses `PixelFormatView` only for TYPELESS, `d3d11_resource_helper.cpp:371-375`).

### Buffers
* 64-bit: Metal allocates the storage and DXMT uses `[buffer contents]` as the CPU
  pointer — single copy (`winemetal_unix.c:805-806`).
* 32-bit (Batman): `Buffer::allocate` forces `CpuPlaced` (`dxmt_buffer.cpp:186-191`),
  so DXMT `aligned_malloc`s guest-addressable pages and passes them to
  `newBufferWithBytesNoCopy` (`dxmt_buffer.cpp:26-31`, `winemetal_unix.c:800-804`) —
  also single copy; the guest pointer *is* the Metal storage.
* Transient extra copies exist but are bounded: a 32 MB staging ring per block
  (`dxmt_command_queue.cpp:29-34`, `dxmt_staging.hpp:25-40` incl. the ml1246 rename
  budget) and the resource initializer's upload heap
  (`dxmt_resource_initializer.cpp:52,764`).
* Remote-Metal mode (`wmtr`) is the one place a shadow `calloc` is made for a
  CPU-visible buffer without caller memory (`winemetal_unix.c:717-800`); not used
  by these runs (`wmtr_enabled()` false — no `[wmt-remote]` lines).

### Net
`[mem-census] tex-private 8543 MB` vs `METAL currentAllocatedSize=3175 MB` in the
same breath (`ebb6.txt:22148-22149`) cannot both be resident — see §4.

## 3. What the knobs read (and do not do)

| Knob | Reader | Effect |
|---|---|---|
| `vram-mb` | `winemetal_unix.c:415-438` (`madeira_ml1042_video_budget`) | Returns a substitute for `MTLDevice_recommendedMaxWorkingSetSize` (`:444-451`). See §3.1 |
| — same — | `build/win32u-unix/d3dkmt_ios.c:425-436` (`madeira_kmt_dedicated_bytes`) | D3DKMT dedicated segment size (else 4096 MB) |
| `vram-trim-mb` | `winemetal_unix.c:394-403` | Distance below the kill line at which the *advertised* budget starts shrinking 1:1, floor 768 MB (`:404-408`) |
| `ram-reserve-mb` (default 1536) | `winemetal_unix.c:332-348` | `cap = hw.memsize - reserve`, budgets plan with `min(os_proc_available_memory, cap)` |
| `DXMT_MAX_VRAM_MB` | `dxmt/src/d3d9/d3d9_device.cpp:1856-1869` | Ceiling for `GetAvailableTextureMem` only; **1024 MB default on the i386 build** (`:1866-1868`) |

### 3.1 Where the budget surfaces, and where it stops
* DXGI: `DedicatedVideoMemory = recommendedMaxWorkingSetSize`
  (`dxmt/src/dxgi/dxgi_adapter.cpp:340`), `QueryVideoMemoryInfo.Budget =
  recommendedMaxWorkingSetSize`, `CurrentUsage = currentAllocatedSize`
  (`:429-431`). nvapi: `:1005`.
* D3D9: `GetAvailableTextureMem` = `available_texture_mem_bytes(budget,
  unified=true, cap, used)` (`d3d9_device.cpp:1877-1879`,
  `d3d9_texture_mem.hpp:22-45`) → **halved** on unified memory, clamped below 4 GB,
  then clamped by `DXMT_MAX_VRAM_MB`, then minus live DEFAULT-pool bytes, rounded
  down to 1 MB.
  Consequence: on the i386 build `GetAvailableTextureMem` is ≤ 1024 MB **no matter
  what `vram-mb` says** (2304 MB → 1152 → capped 1024). `DXMT_MAX_VRAM_MB` is the
  only knob that moves what Batman-class games see.
* Nothing else. `grep -rn "recommendedMaxWorkingSetSize" dxmt/src` returns only
  dxgi, d3d9-GetAvailableTextureMem, nvapi and the winemetal accessor. There is no
  `setPurgeableState`, no allocation refusal, no budget-driven texture eviction:
  `grep -rn "Purgeable|purgeable" dxmt/src` → no hits.
* `MADEIRA_DXGI_BUDGET_EVENTS=1` adds a real budget-change event
  (`dxgi_adapter.cpp:63-118, 155-200`), signalled on 32 MB moves — only helps titles
  that wait on it (RDR2 class). No `[budget-event]` line in any of these logs.

### 3.2 What the logs prove
* Ebb, three budgets, three jetsams:
  `ebb3.txt:3629` 1024 MB (peak 5896, `:29671`); `ebb4.txt:3566` 2304 MB (peak
  5586, `:40717`); `ebb6.txt:3584` 1536 MB (peak 5437, `:22012`). Same class of
  death, 5.4-5.9 GB.
* The budget is read **once**: `ebb6.txt:3588`, `sig.txt:3654`, `main6.txt:3564` —
  all `1 queries so far`, from launch to kill. `ml1075`'s dynamic trim is computed
  only inside that accessor (`winemetal_unix.c:380-382`), so for these titles it is
  dead code.
* Metal memory grows regardless of the budget: `ebb6.txt:16402` 1389 MB →
  `:17483` 1326 → `:18123` 2820 → `:19438` 3254 → `:22148` **3175 MB** under a
  1536 MB budget. `SIGNALIS` stays at 679-745 MB for 20 minutes (`sig.txt:40537`).
* `ram-reserve-mb 1536` on this device yields cap 6145 MB
  (`ebb6.txt:3586`) — one MB above the real kill line (6144 MB per
  `main6.txt:293`, `os_proc_available_memory=5362 + phys_footprint 781 = 6144`), so
  the cap constrains nothing here.

## 4. Reading the census: the texture numbers are inflated

`mem_census_texel_bytes()` returns 4 bytes/texel for "RGBA8/BGRA8/**BC1**/BC2/BC3/
BC7-as-RGBA8/depth32/etc." (`dxmt/src/dxmt/dxmt_mem_census.hpp:239-258`), with a
header comment that this models a device where BC is **decoded** to RGBA8
(`:230-238`). On an A17 that samples BC natively (§2), the real cost is 0.5 B/texel
(BC1) or 1 B/texel (BC3/BC7) — i.e. the census over-counts BC1 8x and BC3/BC7 4x.

Cross-check: SIGNALIS, whose textures are uncompressed, reports
`LIVE=724MB ... METAL currentAllocatedSize=725MB` (`sig.txt:40918`) — 1:1. Esoteric
Ebb (BC-heavy) reports `LIVE=8785MB ... METAL 3175MB` (`ebb6.txt:22148`), a 2.8x
gap that matches a BC1/BC3 mix, and 8.5 GB of live textures is impossible inside a
6.1 GB process [INFERENCE: exact mix not logged; the per-format split is what §7.5
would print].

Other accounting facts worth having:
* `phys_footprint = internal + compressed + external` does **not** close: Ebb's
  last full line is `phys=5333 internal=1355 compressed=885 external=919`
  (`ebb6.txt:22565`), leaving **2174 MB** unattributed. `phys_footprint` includes
  IOKit mappings and `TASK_VM_INFO` exposes no separate field for them
  [INFERENCE]. Metal's own capacity (3175 MB) is the same order, so the gap is
  Metal residence plus not-yet-touched private textures — **not** an unknown leak.
* Transient graphics peaks measured: `init-upload peak=354MB`, `staging-ring
  peak=40MB`, `buffer` 199 MB (`ebb6.txt:22150-22153`).

## 5. Upstream / external evidence

* This fork's own comment is the canon for why the budget exists:
  `winemetal_unix.c:303-322` — on a 12 GB phone the guest filled 4 GB of "RAM" and
  streamed toward a multi-GB "VRAM" simultaneously; the budget makes the two pools
  share one limit. It never claimed to reclaim Metal memory.
* `ml1103` records the failure mode of a *small* budget: `ph-rdr56` raised
  `vram-mb` to 3072, the city scene still hit 7.1 GB, the trim cut the budget to
  2625 MB, and the game went back to **evicting and re-streaming** — i.e. a smaller
  advertised budget trades memory for pop-in, and only if the engine polls.
* DXMT upstream (`3Shain/dxmt`) has no issue about iOS memory budgets; its open
  memory-adjacent items are WoW64 placed-buffer speed (#161) and DXMT 1.0 (#151).
  `willfaust/Madeira` has no Metal-memory issue; the DX9 blocker is #446 (UE3 /
  CryEngine deadlock in early init), plus this fork's local
  `ReadProcessMemory`-inside-`__TRY` BUS fault (`main6.txt` tail).
* `MTLPurgeableState` (KeepCurrent/NonVolatile/Volatile/Empty): volatile resources
  may be discarded by the system and **cannot be made volatile while a command
  buffer is using them**, which collides with triple buffering
  (Apple Developer Forums, `developer.apple.com/forums/tags/metal` — "Cannot set
  purgeability state to volatile while resource is in use by a command buffer");
  `recommendedMaxWorkingSetSize` exists on iOS 16+
  (`developer.apple.com/documentation/metal/mtldevice/recommendedmaxworkingsetsize`).
* Apple's guidance for reclaimable caches: purgeable memory is freed without paging,
  so it is for data that can be recomputed
  (`developer.apple.com/library/archive/.../CachingandPurgeableMemory.html`).

## 6. Options the port could use, judged

| Option | Verdict |
|---|---|
| `storageModePrivate` vs `Shared` | **No saving on iOS.** Both are unified; the difference is caching/hazard behaviour. Do not "fix" DEFAULT-pool storage as a memory change. |
| `MTLStorageModeMemoryless` | Already ruled out with a reason: DXMT splits frames across encoders and a memoryless depth attachment does not survive an encoder boundary (`d3d9_device.cpp:3890-3900`, `:670-672`). Revisit only for a single-encoder render path. |
| `MTLPurgeableState` (Volatile/Empty) | Real but narrow: apply to DXMT-owned *transient* resources (staging ring blocks, initializer heap, retired mirror pool) after `waitUntilCompleted`. Never to textures the app may sample. |
| `MTLHeap` placement (`heapTextureSizeAndAlign` / `newPlacementHeap` / `newTextureAtOffset`, `winemetal.h:1974-1976`, `ml1072`) | Implemented and used **only** by the D3D12 runtime. Placing d3d11/d3d9 textures in a private heap removes per-texture page rounding; gain is driver overhead, not content [INFERENCE: single-digit % of texture bytes, worth an experiment]. |
| ASTC transcode | **Do not.** BC1 is 0.5 B/texel; ASTC 4x4 is 1 B/texel. Transcoding grows memory 2x here. It only pays on a device without BC (`remap_unsupported_bc` devices), which this is not. |
| Mip clamp (drop top levels of large BC textures) | Already implemented, quality-lossy, biggest per-MB lever. §7. |
| Purgeable/`Empty` on the Metal drawables / gamma LUT | Negligible (<10 MB). |

## 7. Actions

### (a) Config-only — no reinstall

Global (`Documents/madeira.cfg`):
1. `env.MADEIRA_MIP_CLAMP_AUTO = 1` — turns the adaptive clamp on for **64-bit**
   modules too (default is `kMadeira32BitModule`, `d3d11_texture_device.cpp:466`).
   It then clamps bias 1 on ≥1024 px BC textures only while headroom < 1536 MB
   (`d3d11_mip_clamp_policy.hpp:18,32-47,64-66`, `d3d11_texture_device.cpp:497-535`), which
   is exactly the Ebb death window. Applies to Unity/UE D3D11 titles; no effect on
   D3D9 (see code change 1).
2. `ram-reserve-mb`: leave at 1536. On this 8 GB phone the cap (6145) sits at the
   kill line, so it neither helps nor hurts [verified: `ebb6.txt:3586`].
3. Do **not** lower `vram-mb` globally: on the DX9 path it is masked by
   `DXMT_MAX_VRAM_MB=1024` anyway, and for Unity titles the budget is read once.

Per game:
4. Esoteric Ebb / any Unity D3D11 title that dies at ~6 GB: add
   `dxmt = d3d11.mipClampBC=1` (deterministic, not headroom-dependent) — the
   supported route is the per-game `dxmt` key (`ContentView.swift:2908-2968`,
   `ConfigCatalog.generated.swift:16`). For a milder variant use
   `dxmt = d3d11.mipClampAuto=1;d3d11.mipClampAutoMB=2048` in the game's own file,
   which enables it *and* raises the threshold without touching global state.
5. D3D9 titles (Batman and future 32-bit DX9): `env.DXMT_MAX_VRAM_MB` is the only
   number the game sees (default 1024 MB). Try `env.DXMT_MAX_VRAM_MB = 768` to stop
   a UE3 texture pool from growing as far, and `512` if it thrashes; expect texture
   pop-in instead of a jetsam. `vram-mb`/`vram-trim-mb` change nothing below
   2048 MB (see §3.1).
6. `env.MADEIRA_DXGI_BUDGET_EVENTS = 1` only for a title known to wait on the
   budget event; it is inert for these three (1 budget query per run).

### (b) Code changes — ranked by MB saved

1. **D3D9 BC mip clamp** (no equivalent exists today; `grep mipClamp
   src/d3d9` → none). Insert the same policy in `d3d9_device.cpp` `CreateTexture`
   just before `info` is filled (~`:3120-3145`), reusing
   `d3d11_mip_clamp_policy.hpp` + `QueryHeadroomMB` (move the MadeiraCtl op 7
   helper into a shared header). Drop `bias` levels from the *physical* Metal
   descriptor while keeping the D3D descriptor logical, exactly as ml675 does
   (`d3d11_texture_device.cpp:546-600`). Expected log: `[mip-clamp] ml2000 auto
   headroom=… clamping large BC textures (threshold 1536 MB)`. MB: for a full mip
   chain, dropping level 0 leaves 25% of the chain's bytes (37.5% with one mip), so
   tens of percent of a DX9 title's texture memory — Batman currently creates none
   (it dies in `NtReadVirtualMemory` before texture creation), so this is gated on
   the boot fix.
2. **Pressure-driven reclaim of transient pools.** Hook the two allocation choke
   points (`dxmt_texture.cpp:164` `Texture::allocate`, `dxmt_buffer.cpp:149`
   `Buffer::allocate`): when `MadeiraCtl op 7` headroom < ~1024 MB, run a relief
   pass — free `StagingResource` spare pools and `free_blocks` on
   `staging_allocator`/`copy_temp_allocator`/`argbuf_allocator`
   (`dxmt_command_queue.cpp:29-34`), trim the initializer heap's spare blocks, drain
   the d3d9 buffer-backing pool (`d3d9_device.cpp:805-856`), and call
   `dyn_census`'s eligible trim. This must key on **footprint, not on a budget
   query** — the queries never repeat (`ml1075 ... 1 queries`). Measured ceiling:
   `init-upload peak=354MB`, `staging-ring peak=40MB`, pool 64 MB
   (`ebb6.txt:22150-22153`, `d3d9_device.hpp:1529`) → ≤ ~450 MB worst case, ~100 MB
   typical.
3. **d3d9 mirror retention**: `kMirrorRetentionBudget` 32 MB → 8 MB
   (`d3d9_texture.cpp:316`) and evict MANAGED mirrors when headroom < 1024 MB
   (reuse `evictManagedMirror`'s re-arm path, `:614-628`, plus a real release of
   `m_mirrorBacking` via `releaseBufferBacking` when the pool is over its cap). MB:
   ≤ 64 MB worst case (pool cap) + up to 32 MB of retained small mirrors.
4. **`MTLPurgeableState` on transient DXMT-owned memory**: after
   `MTLCommandBuffer_waitUntilCompleted` (`winemetal_unix.c:604`), set
   `Empty` on retired staging blocks / initializer-heap blocks instead of keeping
   them; add `MTLResource_setPurgeableState` to the winemetal slot table
   (`winemetal.h` + thunk, following the ml880 pattern) since it does not exist
   today. MB: overlaps (2); take this only if (2) shows retained capacity rather
   than freed capacity.
5. **Fix `mem_census_texel_bytes`** (`dxmt_mem_census.hpp:239-258`): BC1/BC2 →
   0.5 B/texel, BC3/BC4 → 1, BC5 → 1, BC6H/BC7 → 1, honouring
   `query_bc_support()` (pass the physical format instead of guessing from the
   logical one). Saves 0 MB; stops the next investigation from sizing a fix
   against a phantom 8.5 GB (see §4).
6. **Optional experiment: placement heaps for sub-1 MB textures** using the
   existing ml1072 API (`winemetal.h:1974-1976`, currently D3D12-only): one
   `newPlacementHeap` per size class, `newTextureAtOffset` per texture. Expected
   single-digit % of texture bytes from page rounding [INFERENCE]; measure with
   `METAL currentAllocatedSize` before/after.

Do **not** pursue: Private-vs-Shared storage as a memory change, ASTC transcode,
memoryless depth, or a "budget enforcement" path that refuses allocations —
a refused `newTexture` is an unrecoverable device-lost in D3D9 and a null resource
in D3D11, and the fork's own `ml1103` note describes why shrink-induced re-streaming
is worse than the memory it saves.
