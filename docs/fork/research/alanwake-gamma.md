# Alan Wake: exclusive-fullscreen black screen — DXMT D3D9 gamma/present path

Scope: root-cause the fullscreen-only black frame in the D3D9 present path and design the
minimal fix. No edits made, no builds, no phone. Repo: `/Users/filip/Developer/Madeira`,
dxmt submodule `b00f6a1` (v0.73-210). Logs: `/tmp/aw2.txt`, `/tmp/aw3.txt` (fullscreen),
`/tmp/aw4.txt` (windowed, `-window -w1424 -h656`).

**Verdict up front:** the frame is black because the D3D9 gamma LUT is the *only* thing
fullscreen mode changes in the present path, and dxmt applies the app's ramp **without the
validity check DXVK has** — a flat/zero ramp (fade-from-black, or a ramp a game never fills)
becomes a black frame instead of being ignored. Fix is ~30 lines in two files + one log
line, no perf cost. This is a *likely* cause, not proven: whether Alan Wake calls
SetGammaRamp at all is not observable in today's logs (no gamma line exists anywhere — see
§4), so the patch ships with the log line that settles it in one device run.

---

## 1. The gamma path as implemented (all line numbers in this repo)

Entry: `MTLD3D9Device::SetGammaRamp` (dxmt/src/d3d9/d3d9_device.cpp:3088) →
`m_implicitSwapChain->SetGammaRampForChain(Flags, pRamp)` (:3097).

`MTLD3D9SwapChain::SetGammaRampForChain` (dxmt/src/d3d9/d3d9_swapchain.cpp:1332-1364):
- `Flags` (D3DSGR_NO_CALIBRATION / _CALIBRATE) ignored (:1333-1334).
- dedupes an identical re-set with `memcmp` (:1344) and returns early (:1356) — good, this
  prevents a PSO rebuild per frame.
- stores the WORD ramp unconditionally (:1354-1355) so `GetGammaRamp` round-trips byte-
  identical.
- `reapplyGammaRamp()` (:1362).

`reapplyGammaRamp` (:1366-1405):
- bails on headless (`m_presenter == nullptr`) (:1367) or no ramp (:1367).
- gate: `if (!ShouldApplyGammaRamp(m_gammaRamp, m_params.Windowed)) { changeGammaRamp(nullptr); return; }` (:1376-1379).
- upsample 256→1024 (:1387-1404): `src_lo = lut_i/4`, `src_hi = min(src_lo+1, 255)`,
  `t = (lut_i%4)/4`, `a = float(ch[src_lo])/65535.0f`, `a + (b-a)*t`; `gpu_ramp.version = ++m_gammaVersion`.

`d3d9_gamma.hpp` (pure helpers, :25-61): identity entry `i*257`; `SynthesizeIdentityGammaRamp`;
`IsIdentityGammaRamp`; `ShouldApplyGammaRamp(ramp, windowed) = !windowed && !IsIdentityGammaRamp(ramp)`.

Presenter side: `Presenter::changeGammaRamp` (dxmt/src/dxmt/dxmt_presenter.cpp:83-104) — fills
`gamma_lut_rgba_` (clamped 0..1, alpha 1.0, :91-96), `replaceRegion` into a
**1024×1 RGBA32Float**, `WMTResourceStorageModeShared`, `WMTTextureUsageShaderRead` texture
created in the ctor (:26-35); bumps `gamma_version_`, clears `pso_valid` (deferred rebuild).
`buildRenderPipelineState(..., gamma_enable)` passes it as function constant 0x105
(:208, :235-237). `encodeCommands` binds the LUT at fragment texture slot 1 (:184) and
draws a fullscreen triangle; **on a nil drawable it returns early and the present is
dropped** (:168-172).

Shader (dxmt/src/dxmt/dxmt_command.metal):
```
constant bool present_gamma_enabled [[function_constant(0x105)]];        :374
constexpr sampler gamma_sampler(coord::normalized, filter::linear, address::clamp_to_edge);  :377
texture2d<float, access::sample> gamma_lut [[texture(1), function_constant(...)]];           :393
if (present_gamma_enabled && !present_hdr_pq && !present_with_hdr_metadata) {               :409
  output_rgb = float3(gamma_lut.sample(gamma_sampler, float2(output_rgb.r, 0.5)).r, ...);   :411-413
}
```

### Correctness checks requested, one by one (all CONFIRMED by reading the code)
| Item | Finding |
|---|---|
| WORD→float scaling | `float(v)/65535.0f` — correct full scale; identical to DXVK `MapGammaControlPoint` (`65535.0f * x`, dxvk d3d9_swapchain.cpp:10-14). No 8-bit/16-bit mistake. |
| LUT size/format | 1024×1 RGBA32Float, shared storage, shader-read; alpha forced 1.0. Fine. |
| Sampling coordinates | normalized, linear, `clamp_to_edge`, sampled at `(channel, 0.5)`. Correct: coord 0 clamps to texel 0 (no wrap), coord v lands at texel `v*1024-0.5` ⇒ effective response ≈ `ramp[255*v]`, i.e. 8-bit accurate. |
| Identity detection | `i*257` for both Get-before-Set synthesis and the apply gate, one source of truth. Matches DXVK's identity test. No divergence. |
| **Ramp validation** | **Missing.** DXVK refuses a ramp that is flat/inverted, non-monotonic, or has a ≥32767 step, per channel, and applies only if at least one channel passes (`validateGammaRamp`, dxvk d3d9_swapchain.cpp:690-709, used at :719-722). dxmt has no equivalent — this is the only behavioural divergence in the whole path, and it is the divergence that turns a bad ramp into a black frame. |
| All-zero ramp (fade-in / never filled) | `IsIdentityGammaRamp` returns **false** (identity has 0 at index 0 too, but index 1 differs), so `ShouldApplyGammaRamp` is **true in fullscreen** ⇒ LUT all zeros ⇒ `sample()` = 0 for every channel ⇒ **black frame**. In windowed it is ignored (picture fine). In DXVK the same ramp is rejected ("ramp inverted or flat") ⇒ LUT untouched ⇒ picture stays. This asymmetry reproduces the observed symptom exactly. |
| SetGammaRamp before the presenter exists | Stored (`:1354-1355`), push no-ops (`:1367`), and **nothing re-pushes it when a Presenter appears**: `createPresentTarget` (:394-441) never calls `reapplyGammaRamp`; only `ResetForDeviceReset`'s tail does (:655). So gamma set while headless / across a window-change rebuild is silently lost. Lost-gamma bug, not a black one. (The comment at :650-655 says a "rebuilt Presenter starts with an identity LUT"; it actually starts LUT-free with `gamma_version_ 0`.) |
| Reset re-pushes a stale ramp? | Yes and correctly: `reapplyGammaRamp()` at :655 re-evaluates the windowed gate against the new params and re-pushes the app's last ramp (clears it when windowed). That is right D3D9 semantics, not staleness. `changeGammaRamp(nullptr)` no-ops unless `gamma_version_ != 0` (presenter :84-88), so a windowed Reset does not churn the PSO. |

## 2. Comparison with DXVK and wined3d

- **DXVK** (fetched master `src/d3d9/d3d9_swapchain.cpp`): `SetGammaRamp` (:711) validates
  (:719-722), stores `m_ramp` (:724), builds 256 control points, detects identity against
  `MapGammaControlPoint(i/(N-1))` (:728-742), and only `setGammaRamp(N, cp)` when
  `!isIdentity && !m_presentParams.Windowed` (:744-746). On Reset it re-applies the stored
  ramp after a windowed↔fullscreen flip (:669). Same design as dxmt, **minus validation**.
  DXVK also loses animated fades the same way dxmt would if it validated — accepted upstream
  trade-off (a black screen beats a missing fade).
- **wined3d** (wine/dlls/wined3d/swapchain.c:378-395): forwards to
  `wined3d_output_set_gamma_ramp` → the display driver; no windowed gate, no image-side LUT,
  and winemac.drv has a real display-gamma path (wine/dlls/winemac.drv/display.c:997-1019,
  `allow_set_gamma`). On iOS there is no display gamma the app may touch, so an image-side
  LUT is the only faithful option — dxmt's approach is right; it just needs DXVK's guard.

## 3. Is gamma really the only fullscreen-dependent difference? (CONFIRMED — this is the core evidence)

Diffing the two logs:
```
aw2 (fullscreen): d9 swap params (create): 1424x656 fmt=22 count=1 swapEffect=1 windowed=0 presentInterval=2147483648 flags=2 msaaType=0 msaaQuality=0 refreshHz=0 rotation=off
aw4 (windowed):   d9 swap params (create): 1424x656 fmt=22 count=1 swapEffect=1 windowed=1 presentInterval=2147483648 flags=2 msaaType=0 msaaQuality=0 refreshHz=0 rotation=off
both (reset):     presentInterval=1
both:             d9 layer extent: backbuffer 1424x656 window-client 1424x656 ... -> drawable 1424x656 present=blit
aw2:              [swap-win] #2 layer: window layer (0,0 852x392 pt), metal layer drawable 1424x656 px   (after the Reset)
```
- `grep -n Windowed dxmt/src/d3d9/d3d9_swapchain.cpp` ⇒ **two** hits: a log field (:129) and
  the gamma gate (:1376). Present, backbuffer, resolve target, rotation, layer props: none
  branch on `Windowed`.
- Present shader inputs: `is_pq` and `with_hdr_metadata` come from
  `WMTQueryDisplaySettingForLayer`, and on iOS that call **always returns version 0**
  (dxmt/src/winemetal/unix/winemetal_unix.c:5256-5266: `params->version = 0; (void)layer; return`),
  so the presenter uses `colorspace_` = `layerColorSpace(X8R8G8B8)` = SRGB
  (d3d9_swapchain.cpp `layerColorSpace`), i.e. no HDR/PQ path in either run.
  `BackbufferIsSRGB` = `Is_sRGBVariant(BGRX8Unorm)` = false; `is_ms` false; extent matched ⇒
  `present_blit_`, `source.read(uint2(position.xy))` 1:1.
- Therefore the fragment shader's arithmetic differs between the two runs in **exactly one
  term**: `present_gamma_enabled`. Everything else — params, format, extent, pipeline
  selection, layer, display settings — is byte-identical in the logs.
- Consequence: *given* the backbuffer is drawn (census: 1 Clear + 1 DrawPrimitive +
  1.1 vertex-buffer lock + 1.5 surface locks per frame, i.e. a Bink video quad per frame,
  900 presents/900 frames), a black frame with a working 1:1 blit means the blit's output is
  zero — i.e. the LUT says zero, or the LUT pipeline is broken. **If the game never calls
  SetGammaRamp, gamma is exonerated and hypothesis H3 below takes over.**

## 4. Does Alan Wake call SetGammaRamp? (partly answered — new evidence)

- No log line exists anywhere: `grep -i gamma /tmp/aw*.txt` ⇒ 0 hits in all four runs
  (aw, aw2, aw3, aw4). The ramp state is completely unobservable today.
- Census *does* bound it (arithmetic over `[d3d9-census]` top-20, method codes from
  dxmt/src/d3d9/d3d9_census_names.h: `SetGammaRamp=70`, `Present=66`, `BeginScene=90`,
  `EndScene=91`, `Clear=92`, `SetViewport=96`, `SetRenderTarget=86`). The summary fills 20
  ranks by count with ties broken by code order, so a `SetGammaRamp` with count ≥ the
  20th-ranked count would have displaced the shown entry with the next-highest code:
  - aw2/aw3 summary 1 (1 frame, covers CreateDevice→first present): 20th = 31, code 195 ⇒
    **< 31 calls** during startup.
  - summary 2 (99 frames): 20th = 99, code 86 (> 70) ⇒ **< 99 calls = < 1 per frame**.
  - summary 3 (900 frames): 20th = 900, codes 66/90/91/92/96; `BeginScene` (90) is shown, so
    a 900-count `SetGammaRamp` (70) would have displaced it ⇒ **< 900 calls in 900 frames**.
  - Same bounds hold in the windowed run (aw4: <99 in the 99-frame window).
- What this proves: the game does **not** animate the ramp (a 30 Hz fade over 900 frames =
  27 000 calls would top the list). So a "fade from black that never completes" is
  **excluded**; if gamma is the cause it is a *single static* ramp set at startup (or on a
  brightness change) that is degenerate.
- What it does not prove: whether it is called once/twice at all. That needs the log line
  below. (`MADEIRA_D3D9_LAST=1` enables the `[d3d9-last]` ring — dxmt/src/d3d9/d3d9_census.hpp:125-134 —
  which would also answer it for a startup-only call, at the cost of a lot of I/O.)
- Static binary analysis was not possible: the game is not on this Mac
  (`find ~ -maxdepth 6 -iname "AlanWake*.exe"` ⇒ nothing; it lives in the phone's Wine
  container).

## 5. Ranked hypotheses for "black in fullscreen only, picture with -window"

**H1 (primary). A degenerate ramp is applied by the LUT, fullscreen only.**
Mechanism: dxmt honours any non-identity ramp (:1376, d3d9_gamma.hpp:59-61) with no
validation (:1332-1364); an all-zero or near-zero ramp maps every channel to ~0 in the
present blit; windowed never builds the LUT, so the same session shows a picture.
Evidence: §3 (gamma is the only differing shader input, everything else verified identical
from the logs), §2 (DXVK's guard is exactly what is missing), §4 (any ramp use is static,
which is consistent with a permanent black screen).
Not confirmed: the ramp's values and whether it is set at all. Cost to confirm: one log line.

**H2 (latent, same gate). The gamma present pipeline fails to build and is never checked.**
`buildRenderPipelineState` ignores both `WMT::Error` and a nil PSO
(dxmt_presenter.cpp:204-240); `encodeCommands` then calls `setRenderPipelineState(nullptr)`
(:190-194) and the triangle renders nothing, into a `WMTLoadActionDontCare` drawable (:177) ⇒
black, fullscreen only (the only place `gamma_enable` is true).
Probability now judged low: the LUT is RGBA32Float with a linear sampler, which needs
`supports32BitFloatFiltering`; probed on this Mac (`MTLDevice supports32BitFloatFiltering`
⇒ 1 on Apple M4), and A17 Pro is the same Apple-GPU family table [INFERENCE].
Keep it as a one-line "PSO built: ok/no" log because today a failure is silent.

**H3. Game-side content difference (the backbuffer really is black in fullscreen).**
No mechanism found in the engine path, and the census shows the same draw/lock/present shape
in both runs; but the game *does* take a different Win32 branch (window style 94000000
WS_POPUP vs 04ca0000/14ca0000, plus a Reset that changes presentInterval
0x80000000→1). Cannot be excluded from logs alone. Discriminator if H1's log comes back
clean: read back the backbuffer's mean luminance at Present.

**H4. Layer created wrong in fullscreen (secondary, real, probably not the whole story).**
aw2:10593 `[swap-win] #1 layer ... window layer (-0,335 393x181 pt), metal layer drawable 0x0 px`
vs aw4:10645 `... (-2,-9 856x412 pt) ... drawable 0x0 px, fitted to the desktop`.
Until the Reset (aw2:12741) the fullscreen layer was 393×181 pt (≈1/3.6 of the window) with a
**0×0 drawable**, and `encodeCommands` drops presents on a nil drawable
(dxmt_presenter.cpp:168-172) ⇒ frames dropped, not black-blitted. Self-corrected at the
Reset, so it can only explain the first ~1 s of Alan Wake — but it would fully explain a
fullscreen black screen in a title that never Resets. Separate ticket.

**H5. Alpha / opaque / sRGB / HDR.** Dismissed by code: backbuffer is BGRX8Unorm
(d3d9_format.cpp:23-24) so `output.w` = 1.0 and `layer_props_.opaque = true`
(dxmt_presenter.cpp:19); `Is_sRGBVariant(BGRX8Unorm)` false; iOS display query returns
version 0 ⇒ no PQ/HDR-EDR path. Same in both runs in any case.

## 6. The minimal fix (do not apply — this is the design)

**6.1 Validation helper** — dxmt/src/d3d9/d3d9_gamma.hpp, insert after `IsIdentityGammaRamp`
(current lines 44-50, before `ShouldApplyGammaRamp` at :54-61):
```cpp
// True when one channel is a ramp a display could honour: strictly rising end to
// end, monotonic, no DXVK-style "huuge jump". Port of DXVK
// src/d3d9/d3d9_swapchain.cpp validateGammaRamp (:690-709), which SetGammaRamp
// (:719-722) requires for at least one channel before the ramp reaches the
// blitter. The reason transfers exactly: an all-zero ramp (a fade from black, or
// one a game never fills) is "flat", and honouring it maps every channel to 0 --
// in dxmt that is not a dim display but a black *frame*, because the LUT runs in
// the present blit and only in fullscreen (ShouldApplyGammaRamp).
inline bool
IsUsableGammaChannel(const WORD *ch) {
  if (ch[0] >= ch[255])
    return false;
  for (uint32_t i = 1; i < 256; ++i) {
    if (ch[i] < ch[i - 1])
      return false;
    if (static_cast<uint32_t>(ch[i]) - ch[i - 1] >= UINT16_MAX / 2)
      return false;
  }
  return true;
}

// DXVK's shape: keep the ramp if ANY channel is usable.
inline bool
IsUsableGammaRamp(const D3DGAMMARAMP &ramp) {
  return IsUsableGammaChannel(ramp.red) || IsUsableGammaChannel(ramp.green) ||
         IsUsableGammaChannel(ramp.blue);
}
```

**6.2 Gate + the verification log line** — dxmt/src/d3d9/d3d9_swapchain.cpp:1376-1379.

before:
```cpp
  if (!ShouldApplyGammaRamp(m_gammaRamp, m_params.Windowed)) {
    m_presenter->changeGammaRamp(nullptr);
    return;
  }
```
after:
```cpp
  const bool usable = IsUsableGammaRamp(m_gammaRamp);
  const bool applied = usable && ShouldApplyGammaRamp(m_gammaRamp, m_params.Windowed);
  // One line per decision change (deduped like layerDrawableExtent above): the
  // report this exists for is "black in fullscreen, fine with -window", and the
  // LUT is the only present-path input windowed mode alters (fs_present_quad's
  // present_gamma_enabled). Printing the ramp's ends makes the next device log an
  // answer instead of a hypothesis. Zero cost: at most one line per set/reset.
  {
    static bool logged = false;
    static WORD last_r0 = 0, last_r255 = 0, last_g0 = 0, last_g255 = 0, last_b0 = 0, last_b255 = 0;
    static bool last_applied = false;
    if (!logged || m_gammaRamp.red[0] != last_r0 || m_gammaRamp.red[255] != last_r255 ||
        m_gammaRamp.green[0] != last_g0 || m_gammaRamp.green[255] != last_g255 ||
        m_gammaRamp.blue[0] != last_b0 || m_gammaRamp.blue[255] != last_b255 ||
        applied != last_applied) {
      logged = true;
      last_r0 = m_gammaRamp.red[0], last_r255 = m_gammaRamp.red[255];
      last_g0 = m_gammaRamp.green[0], last_g255 = m_gammaRamp.green[255];
      last_b0 = m_gammaRamp.blue[0], last_b255 = m_gammaRamp.blue[255];
      last_applied = applied;
      Logger::warn(str::format(
          "[d9-gamma] ramp r=", m_gammaRamp.red[0], "..", m_gammaRamp.red[255],
          " g=", m_gammaRamp.green[0], "..", m_gammaRamp.green[255],
          " b=", m_gammaRamp.blue[0], "..", m_gammaRamp.blue[255],
          " identity=", IsIdentityGammaRamp(m_gammaRamp) ? 1 : 0,
          " usable=", usable ? 1 : 0,
          " windowed=", m_params.Windowed ? 1 : 0,
          " lut=", applied ? 1 : 0));
    }
  }
  if (!applied) {
    m_presenter->changeGammaRamp(nullptr);
    return;
  }
```
Net behaviour change: a ramp DXVK would refuse no longer reaches the LUT (`lut=0`), the
frame is presented unmodified, and `GetGammaRamp` still returns the app's bytes
(`m_gammaRamp` storage at :1354-1355 is untouched). ~30 lines total, one file + one header,
no allocation, no per-frame cost (the log dedupes; the identity/degenerate cases keep the
LUT-free PSO, so nothing recompiles).

**6.3 Two-line optional hardening** (recommended, separate commit): in
`Presenter::buildRenderPipelineState` (dxmt_presenter.cpp:204-240) after building both PSOs,
`if (!present_blit_ || !present_scale_) Logger::warn("d9: present pipeline build failed (gamma=…)");`
— today a nil PSO silently produces a black frame (H2).

**6.4 Not part of the minimal fix, worth its own ticket:** `createPresentTarget`
(:394-441) should call `reapplyGammaRamp()` after standing up the Presenter (gamma set while
headless / across a window-change rebuild is currently lost), and
`d3d11_swapchain.cpp:830` (`presenter->changeGammaRamp(output->GetGammaRamp())`) has the same
missing validation for DXGI gamma.

### How to verify on device (prediction table)
Log line to grep, fullscreen run, immediately after `d9 swap params` / `[d9-display]`:
| Log | Meaning | Next |
|---|---|---|
| `[d9-gamma] ramp r=0..0 g=0..0 b=0..0 identity=0 usable=0 windowed=0 lut=0` and the picture is now visible | H1 confirmed: a zero/flat ramp was blackening the frame | ship 6.1/6.2 |
| `ramp r=0..255 g=0..255 b=0..255 … usable=1 lut=1` (a real ramp) and **still black** | gamma exonerated | probe backbuffer luminance at Present (H3), then H2 log from 6.3 |
| **no `[d9-gamma]` line at all** in a fullscreen run | the game never calls SetGammaRamp ⇒ gamma cannot be the cause; H4/H3 | open the layer-at-creation ticket (H4) first |
| `identity=1` | game set the identity explicitly; LUT correctly off | gamma exonerated |

Cross-check with `-window`: the same run must print `windowed=1 lut=0` and show the picture;
that also proves the LUT is the only delta.

## 7. Worth pursuing? — verdict for this slice

- **Fix cost:** ~30 lines (one header helper + one gate block + one log line), no allocation,
  no per-frame cost, no API-surface change; it *removes* a code path for bad ramps rather
  than adding one. Risk: a legitimate "hold the screen black" ramp stops being honoured —
  exactly the trade-off DXVK already made upstream, so compatibility-wise it converges on the
  reference implementation.
- **Needed if `-window` works?** For Alan Wake, no: windowed costs nothing measurable on this
  route — identical `D3DPRESENT_PARAMETERS` (1424×656 X8R8G8B8, count=1,
  D3DSWAPEFFECT_DISCARD, vblank-clocked presentInterval), identical 1:1 blit pipeline,
  identical 852×392 pt layer / 1424×656 px drawable, same 120 presents/s. Windowed only
  changes the Win32 window style and forbids a display-mode change, i.e. the same thing it
  changes on desktop. So `-window` is a legitimate workaround for this title.
- **Still worth fixing, and cheap:** the same class of bug hits *any* D3D9 title that sets a
  degenerate/very dark static ramp (brightness sliders at minimum, splash-screen fades,
  uninitialised ramps) — and there it is a full-screen blackout, the most expensive failure
  mode to diagnose, with zero diagnostics today (`grep -i gamma` returns nothing in 6.6 MB
  of log). The log line alone is worth the patch.
- **Do the log line first, then the guard** (same commit is fine): the guard alone would also
  hide the evidence that a game is setting a ramp we then refuse.

### Confidence
- CONFIRMED from code + logs: gamma is the only fullscreen-dependent input to the present
  blit; dxmt has no ramp validation while DXVK does; an all-zero ramp ⇒ black frame in
  fullscreen and a normal frame in windowed; the game does not animate the ramp; the
  creation-time layer defect (393×181 pt / 0×0 drawable, fixed at Reset).
- [INFERENCE]: that Alan Wake sets a ramp and that its values are near zero (§4 has no way to
  see it); that the A17 LUT pipeline compiles (probed on M4 only); that the game's content
  itself is not black in fullscreen (H3, ruled out only by absence of a mechanism).
