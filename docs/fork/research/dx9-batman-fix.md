# Batman: Arkham Asylum — two root causes, minimal fixes

Both are fork-local, both small, and neither changes behaviour for 64-bit
callers. Evidence: `/tmp/g2/dev/bm.txt` (GL enabled → the *game* dies at load),
`main5.txt`/`main6.txt` (`MADEIRA_NO_GL=1` → the *launcher* dies later, same
address in both).

## 0. Ranked findings

| # | Finding | Impact | Fix |
|---|---|---|---|
| 1 | `NtReadVirtualMemory`'s current-process branch copies with `memmove()` inside `__TRY`. On iOS a host BUS/SEGV is not an SEH event, so `__TRY` never runs and the raise happens on the dispatcher kernel stack → `Exception frame is not in stack limits` → `exit_code=0x1f` (`main6.txt:12664-12802`). | Fatal; any 32-bit title reading its own memory | ~30 lines, `virtual_ios.c` |
| 2 | `wow64_thread_attach()` gets an **already-translated host** `args` and feeds it to `get_teb64(ULONG)`, which truncates it to 32 bits and dereferences the guest address (`bm.txt:12973+`, fault at `0x302fdc`). The fork's fix is in `patches/wine-opengl-winios.patch`, which this tree has **not applied**. | Fatal for every 32-bit GL caller (`wined3d`→`d3d9`) | apply the patch (no code change) + 4-line hardening |
| 3 | `bus_handler()` never honours `thread_data->jmp_buf`; `handle_syscall_fault()` does (`signal_arm64_ios.c:9758-9782`). Every `__TRY` in a unix syscall implementation is a landmine for *other* host faults. | Fatal, class-wide | 6 lines, `signal_arm64_ios.c:14391` |
| 4 | `virtual_check_buffer_for_read()` (source probe of `NtWriteVirtualMemory`) has the same `__TRY`+load shape as #1. | Fatal on a bad source | ~12 lines (`SHOULD`) |
| 5 | Next blocks after 1–2: GL must work (`wined3d_caps_gl_ctx_create: Failed to find a suitable pixel format`, `main6.txt:11990` — a consequence of `MADEIRA_NO_GL=1`), then D3D9 device creation, then the UE3-early-init deadlock class of upstream #446. | — | §4 |

## 1. `NtReadVirtualMemory` on the current process

### 1.1 Evidence

```
main6.txt:12664 [store-noalias] #1 addr=0x798468ff6e insn=0x38401426 region 0x7980000000+0x8000000 prot=0
main6.txt:12666 [mach-deliver] no TEB owns sp=0x12637fbd0 (pc=0x19f37215c x18=0x0 registry=0x7900300000)
main6.txt:12695 sym pc=_platform_memmove+0x1bc  lr=…`NtReadVirtualMemory+0xf0
main6.txt:12776 err:seh:bus_handler BUS #1: pc=0x19f37215c addr=0x798468ff6e
main6.txt:12780   VERDICT <== ANONYMOUS, NEVER RESIDENT — never materialised rev=ml560
main6.txt:12787 BUS->AV: unreadable target addr=0x798468ff6e pc=0x19f37215c rw=0
main6.txt:12791 [exc-disp] raise tid=00a8 code=c0000005 … p1=798468ff6e
main6.txt:12793 err:seh:NtRaiseException Exception frame is not in stack limits => unable to dispatch exception.
main6.txt:12794 err:process:NtTerminateProcess NtTerminateProcess(…, exit_code=0x1f)
```

`main5.txt:12920-13029` is byte-identical. Registers (`main6.txt:12674-12681`):
`x0=0x79032be354` (valid guest buffer), `x1/x22=0x798468ff6e` (source, **host**),
`x2=4`, guest `x25=0x8468ff6e`; `0x798468ff6e - 0x8468ff6e = 0x7900000000` — the
caller's window base (`main6.txt:8727`). The WoW64 path already translated the
guest argument (`build/ntdll-unix/ios_wow.h:3-18`): the fault is purely a host
load on a never-materialised page. The `no TEB owns sp=0x12637fbd0` line is not a
missing TEB — that is the dispatcher's *kernel* stack (same in `bm.txt:12977`);
delivery is "best effort" onto the guest stack, which is not what
`call_seh_handlers` was handed → `EXCEPTION_STACK_INVALID` (`thread_ios.c:2366`).

### 1.2 Why `__TRY` cannot help; what the port does instead

`virtual_ios.c:34987-35002`:

```c
    else if (process == GetCurrentProcess())
    {
        __TRY { memmove( buffer, addr, size );
```

The rule is in the port's own comment (`virtual_ios.c:32397-32404`, written for
`ios_ec_hook_peek`): *"an address in a reserved region that never materialises
raised a SIGBUS that bus_handler hands to the guest without honouring the
`__TRY` … The kernel copy returns an error instead."* That is this crash,
described one revision before it happened. Fault-free primitives in use:
`ios_safe_read64()` (`:4825-4833`), `ios_ec_hook_peek()` (`:32406-32414`),
`ios_reply_host_writable()`/`ios_read_reply_paged()` (`server_ios.c:641-704`).
`virtual_uninterrupted_read_memory()` (`:27425-27452`) is unusable: it returns 0
when `find_view()` finds no view (this case), cannot tell "no view" from
"unreadable", and needs `virtual_mutex` (an mmap under it deadlocked the port,
`virtual_ios.c:21478`).

### 1.3 Patch (primary)

Add above `NtReadVirtualMemory` (`virtual_ios.c:34977`) and replace the
current-process branch body:

```c
#ifdef WINE_IOS
/* madeira: read guest memory without taking a host fault. A plain memmove()
 * reaches the source with a host load, and that fault is not an SEH event here
 * (bus_handler hands it to the guest from the dispatcher stack -> "Exception
 * frame is not in stack limits", main6.txt). The kernel copy returns an error
 * instead (ios_ec_hook_peek) and still pages data in; the destination stays a
 * guest store, so JIT-pool RX pages go through their RW alias. */
static SIZE_T ios_read_fault_free( void *dst, const void *src, SIZE_T size )
{
    char bounce[0x4000];   /* one iOS host page (16 KB; 4 KB fits too) */
    SIZE_T done = 0;
    while (done < size)
    {
        const char *s = (const char *)src + done;
        SIZE_T n = min( size - done, host_page_size - ((UINT_PTR)s & host_page_mask) );
        mach_vm_size_t got = 0;
        if (mach_vm_read_overwrite( mach_task_self(), (mach_vm_address_t)(uintptr_t)s, n,
                                    (mach_vm_address_t)(uintptr_t)bounce, &got ) != KERN_SUCCESS
            || got != n)
            break;             /* an AV, not a crash: keep what was copied */
        memcpy( (char *)dst + done, bounce, n );
        done += n;
    }
    return done;
}
#endif
```

```c
    else if (process == GetCurrentProcess())
    {
#ifdef WINE_IOS
        SIZE_T requested = size;   /* readable prefix copied; bytes_read says how much */
        size = ios_read_fault_free( buffer, addr, requested );
        status = (size == requested) ? STATUS_SUCCESS : STATUS_PARTIAL_COPY;
#else
        __TRY { memmove( buffer, addr, size ); status = STATUS_SUCCESS; }
        __EXCEPT { status = STATUS_PARTIAL_COPY; size = 0; }
        __ENDTRY
#endif
    }
```

* Batman case → `STATUS_PARTIAL_COPY`, `*bytes_read == 0` — what Wine's test
  expects for an illegal remote address (`wine/dlls/ntdll/tests/info.c:2878-2883`,
  `todo_wine`). Returning `ACCESS_VIOLATION` when `done == 0` is a one-line variant.
* `bytes_read` becomes honest for partial reads (the `__EXCEPT` path zeroes it).
  No lock, no wineserver call; one 16 KB bounce per page.
* `NtWow64ReadVirtualMemory64` (`:35438-35462`) needs nothing: it already goes
  through the server's `read_process_memory`, which returns errors, not faults.

### 1.4 Same pattern elsewhere (`SHOULD`)

`virtual_check_buffer_for_read()` (`virtual_ios.c:27356-27382`) probes with
`volatile` loads inside `__TRY`; it is the **source** probe of
`NtWriteVirtualMemory` (`:35026`) and `NtWow64WriteVirtualMemory64` (`:35487`).
Probe the first and last byte of every page through the kernel instead (a file
page can be readable at its start and BUS at its end):

```c
    while (size)      /* first and last byte of every page, through the kernel */
    {
        const char *p = ptr;
        SIZE_T n = min( size, host_page_size - ((UINT_PTR)ptr & host_page_mask) );
        if (!ios_safe_probe( p ) || (n > 1 && !ios_safe_probe( p + n - 1 ))) return FALSE;
        ptr = p + n; size -= n;
    }
    return TRUE;
```

with `ios_safe_probe()` = one `mach_vm_read_overwrite` of 1 byte into a local
(the `ios_safe_read64()` shape). `virtual_check_buffer_for_write()` (`:27390`)
stays: there is no kernel "will a store succeed" probe, and `vm_region` would
wrongly refuse JIT-pool RX pages (writable only via the alias) and write-watched
pages; a truly unwritable destination is a guest bug, and §3 keeps its AV
dispatchable.

### 1.5 Log evidence

* Gone: `[store-noalias] … addr=0x798468ff6e`, `bus_handler BUS #1:`, `BUS->AV:`,
  `[exc-disp] raise … c0000005`, `Exception frame is not in stack limits`,
  `exit_code=0x1f`, `abort_process: status=0x1f`, `[srv-kill] … pid=00a4 violent=1`
  (`main6.txt:12794-12802`). Present instead (if the one-shot line is kept):
  `[rvm-safe] read stopped at 0x0 of 0x4 (0x798468ff6e): host copy refused —
  STATUS_PARTIAL_COPY, 0 bytes`.
* Eventually `[d3d9-modes] … CreateDevice … hr 0x0` and `presents>0` instead of
  `detach-wait: presents=0 running=1` (`main6.txt:13514`).

## 2. The 32-bit `opengl32.dll` init crash

### 2.1 Evidence

```
bm.txt:12973 [unixlib] opengl32 (winios WGL) (module 0x727a820000) -> wow64 table (0x1082955b0)
bm.txt:12974 [store-noalias] #3 addr=0x302fdc insn=0xb98fdd09 pc=0x105fe368c
bm.txt:12977 [mach-deliver] no TEB owns sp=0x129dffcd0 (pc=0x105fe368c x18=0x7200300000 …)
bm.txt:12979 [fault_rip] addr=0x302fdc kr=1(INVALID_ADDRESS)
bm.txt:12985 [ec-fault-regs] x8=0x302000 … x0=0x7200302000 x2=0x7200302000 | teb=0x7200300000
bm.txt:12988 [mach_exc] insn_stream PC-12..PC+8: 35fffb08 17ffffd2 2a0003e8 [b98fdd09] …
bm.txt:12989 sym pc=…`wow64_thread_attach+0x4 lr=…`__wine_unix_call_dispatcher+0x78
bm.txt:13047 loader_init "opengl32.dll" failed to initialize, aborting
bm.txt:13048 … ShippingPC-BmGame.exe failed, status c0000142
```

The instruction stream settles it: `0x2a0003e8` = `mov w8, w0` (**the truncation
to `ULONG`**), then `0xb98fdd09` = `ldrsw x9, [x8, #0xfdc]` — the read of
`TEB32.WowTebOffset` (`FEX/Source/Windows/include/winternl.h:368`) at `0x302fdc`.
At entry `args` (`x0` = the dispatcher's `x2`) was the **host** pointer
`0x7200302000`; `get_teb64(ULONG)` turned it into **guest** `0x00302000`.
`wine/dlls/opengl32/unix_private.h:88-92`:

```c
static inline TEB *get_teb64( ULONG teb32 )
{
    TEB32 *teb32_ptr = ULongToPtr( teb32 );      /* identity map on Linux */
    return (TEB *)((char *)teb32_ptr + teb32_ptr->WowTebOffset);
}
```

The identity assumption is the bug: upstream WoW64 maps the 32-bit TEB below
4 GB in the same address space, so `ULongToPtr` is exact; here it is not
(`ios_wow.h:3-10`: "XNU's mandatory 4 GB `__PAGEZERO` makes the classic WoW64
identity impossible").

The contract is written down (`wine/include/wine/unixlib.h:41-77`): an entry in
`__wine_unix_call_wow64_funcs` receives `args` as a **HOST** pointer, while every
pointer **embedded** in that block is a 32-bit **GUEST** address; enforced at
`FEX/Source/Windows/WOW64/Module.cpp:892`. `wow64_thread_attach`
(`wine/dlls/opengl32/unix_wgl.c:2829-2832`) is called as
`UNIX_CALL( thread_attach, NtCurrentTeb() )` (`wgl.c:2168`) — the TEB pointer
*is* `args`, so it arrives converted and is then treated as guest data. Its
siblings differ: every `wow64_wgl_*`/`wow64_gl_*` thunk reads `params->teb`, an
*embedded* `PTR32` (`unix_thunks.c:33689`, 3 060 sites), where +B is required.

### 2.2 Why this tree crashes: the patch is not applied

`patches/wine-opengl-winios.patch:255-330` replaces exactly this helper
(`get_teb64` → `ios_wow_host_ptr( teb32 )`) and rewrites every dereferenced
`ULongToPtr(params->…)` (hglrc, hDc, ppfd, buffer pointers, `copy_wow64_ptr32s`).
In this tree the submodule is **unpatched**: `unix_private.h:88` still reads
`ULongToPtr`, `unix_thunks.c:33689` still reads `ULongToPtr(params->hglrcSrc)`,
and `nm build/ntdll-unix/obj/opengl32_wgl.o` / `…_thunks.o` reference no
`ios_wow_*` (while `libntdll_unix.a` does). Yet applying the patch is a *manual*
step (`docs/BUILDING.md:93,100`: `git -C wine apply ../patches/wine-opengl-winios.patch`).
**That is the fix for #2 and it needs no code change.** It cures this site even
though the `ULONG` parameter stays: `0x7200302000` → truncate → `0x00302000` →
`ios_wow_base() + 0x302000` → `0x7200302000`, exact because `IOS_WOW_WINDOW_SIZE`
is `1<<32` and the base is 4 GB aligned (`ios_wow.h:44`) — correct by
coincidence, which is what §2.3 removes.

### 2.3 Hardening (`SHOULD`, upstreamable)

`wine/dlls/opengl32/unix_wgl.c:2829` (`unixlib.h`, which brings `ios_wow_base` /
`ios_wow_host_ptr`, is already included at line 39):

```c
NTSTATUS wow64_thread_attach( void *args )
{
#ifdef WINE_IOS
    /* `args` is a HOST pointer (only the outer pointer is converted);
     * get_teb64()'s ULONG would truncate it to 32 bits. */
    TEB32 *teb32 = args;
    if (ios_wow_base()) return thread_attach( (TEB *)((char *)teb32 + teb32->WowTebOffset) );
#endif
    return thread_attach( get_teb64( (ULONG_PTR)args ) );
}
```

and `unix_private.h:88`, so both shapes are accepted:

```c
static inline TEB *get_teb64( ULONG_PTR teb32 )   /* embedded field or host pointer */
{
    TEB32 *teb32_ptr = ios_wow_in_window( (const void *)teb32 )
                       ? (TEB32 *)teb32 : ios_wow_host_ptr( teb32 );
    return (TEB *)((char *)teb32_ptr + teb32_ptr->WowTebOffset);
}
```

`ios_wow_in_window()` is `ios_wow.h:91`; with no window both helpers degrade to
`ULongToPtr`, i.e. upstream behaviour.

### 2.4 Log evidence

* Gone: `addr=0x302fdc`, `[mach-deliver] no TEB owns sp=`, `[mach_exc] UNHANDLED #3`,
  `loader_init "opengl32.dll" failed to initialize`, `status c0000142`.
* Present: `[unixlib] opengl32 (winios WGL) … -> wow64 table` then GL activity
  (`[winios-gl] perf hwnd=… presents/s=… (32-bit thunk …)` with
  `env.MADEIRA_GL_PERF=1`), and `wined3d_caps_gl_ctx_create Failed to find a
  suitable pixel format` (`main6.txt:11990`) gone.

### 2.5 Upstream status

* No upstream issue/PR reports either crash: searching `willfaust/Madeira` for
  `ReadProcessMemory`, `ReadVirtualMemory`, `stack limits`, `no TEB owns`,
  `Arkham Asylum` yields #41, #256, #397, #462 — none matches.
* Fork-local by upstream's own statement: PR #41's body lists what it did *not*
  carry — "… the **ReadProcessMemory no-fault copies**, the unix-call NULL-handle
  path …". The GL route is upstream: #225 (WGL driver on iOS), #353
  (`d3d9 = wined3d` "runs 32-bit D3D9 games" through wined3d/Zink).
* `docs/BUILDING.md:93,100` is the only guard against #2, and it is manual.

## 3. Defence in depth: `bus_handler` and `__TRY` (6 lines)

The mechanism exists and works on the signal path: `handle_syscall_fault()`
(`signal_arm64_ios.c:9758-9782`) sets `x0 = thread_data->jmp_buf`, `x1 = 1`,
`pc = longjmp` and clears `jmp_buf`, so the fault resumes at the `__EXCEPT`
clause. `bus_handler()` (`:13664`; `bus_fatal:` `:14639`; the BUS->AV decision
with `rec = vrec;` at `:14391`) has no such check. Insert the same four
assignments immediately before `rec = vrec;` there, using `bus_ctx`:

```c
    /* madeira: __TRY (thread_ios.c:2772) must be honoured on the BUS path, or a
     * host fault in a unix syscall becomes a guest exception raised on the
     * dispatcher stack — "Exception frame is not in stack limits" (main6.txt:12793). */
    if (ntdll_get_thread_data()->jmp_buf) {
        REGn_sig(0, bus_ctx) = (ULONG_PTR)ntdll_get_thread_data()->jmp_buf;
        REGn_sig(1, bus_ctx) = 1;
        PC_sig(bus_ctx) = (ULONG_PTR)longjmp;
        ntdll_get_thread_data()->jmp_buf = NULL;
        return;                    /* resumes at the __EXCEPT clause */
    }
```

Evidence: `[bus-regs]` followed by the `__EXCEPT` status, instead of
`[exc-disp] raise … c0000005` + `Exception frame is not in stack limits`.

## 4. Next likely blockers (from the logs)

1. **GL must work for D3D9.** `main6.txt:11990-11991` follows directly from
   `MADEIRA_NO_GL=1` (`:56`, `:9474`). `[d3d9-modes] adapter 0 count=21` (`:12041`)
   shows mode enumeration, but `CreateDevice` appears **0 times** in `bm.txt`,
   `main5.txt` and `main6.txt`.
2. **D3D9 frontend.** `d3d9` was "emulated" (`main6.txt:9424`) →
   `d3d9-emulated.dll` → wined3d → GL. `d3d9=native` (DXMT shim on Metal,
   `dxmt/src/d3d9shim/d3d9shim_main.c:95-146`) needs no GL.
3. **UE3 early-init deadlock class**, upstream #446 (Arkham *City*, Crysis 2 hang
   before renderer selection, `[evt-life] NEVER SET BY ANYONE`). Arkham *Asylum*
   has not been observed past its launcher yet.
4. **Not blockers here.** No GFWL/xlive (Steam GOTY, `steam_api.dll`,
   `main6.txt:9097`; no SecuROM). Bink loads (`main6.txt:9296`). PhysX
   (`PhysXExtensions`, `NxCooking`, `APEX_release`) loads from the game folder
   (`bm.txt:9287-9302`); the `[dll-missing] … PhysXLoader.dll c0000135` lines
   (`main6.txt:12195`) belong to Steam's 32-bit webhelper.
5. **Memory:** irrelevant so far — `phys=1770 MB (peak 1938)` at the end of
   `main6.txt`, far below the ~6.1 GB line.

## 5. Actions

### (a) Config-only (no reinstall)

1. Global (`Documents/madeira.cfg`): remove `env.MADEIRA_NO_GL = 1` — it converts
   a load-time crash into a D3D9-without-GL dead end (`ConfigCatalog.generated.swift:363`).
2. This game's own file: `d3d9 = native` (or `env.MADEIRA_D3D9 = native`,
   `ConfigCatalog.generated.swift:14,270`) — 32-bit `d3d9.dll` becomes DXMT's Metal
   shim, so neither `wined3d.dll` nor `opengl32.dll` is needed and both §1's GL
   dependency and §2's crash path are skipped. Keep `""`/`emulated` only to test
   the wined3d/Zink route.
3. Optional, to bypass the crashing launcher before a rebuild: `env.MADEIRA_EXE`
   (`ConfigCatalog.generated.swift:29`) → `Binaries/ShippingPC-BmGame.exe`, the
   pattern the `args`/Stray note describes (`:9`). Steam still waits on the
   launcher it started, so this helps only with a Dock launch.
4. Memory knobs (`ram-reserve-mb`, `swap-mb`, `vram-mb`): nothing to change at
   `phys=1770 MB`.

### (b) Code changes

| # | Where | Change | Expected evidence |
|---|---|---|---|
| 1 | `build/ntdll-unix/virtual_ios.c:34987-35002` + helper above `:34977` | `ios_read_fault_free()`; `STATUS_PARTIAL_COPY` with honest `bytes_read` | no `[store-noalias] addr=0x798468ff6e`, no `BUS #1`/`BUS->AV`/`Exception frame is not in stack limits`/`exit_code=0x1f`; no `abort_process: status=0x1f` for pid 00a4 |
| 2 | apply `patches/wine-opengl-winios.patch`; rebuild `build/ntdll-unix` + `opengl32.dll` (`docs/BUILDING.md:93,100`) | `ios_wow_host_ptr` in `get_teb64` and in every dereferenced `ULongToPtr(params->…)` | no `addr=0x302fdc`, no `loader_init "opengl32.dll" failed`, no `c0000142`; `wined3d_caps_gl_ctx_create` error gone |
| 3 | `wine/dlls/opengl32/unix_wgl.c:2829`, `unix_private.h:88` | hardening: `args` is host; `get_teb64` takes `ULONG_PTR` + `ios_wow_in_window()` | same as 2, and survives a non-4 GB-aligned base |
| 4 | `build/ntdll-unix/signal_arm64_ios.c:14391` | `bus_handler` honours `thread_data->jmp_buf` before BUS->AV | residual host faults land in `__EXCEPT` |
| 5 | `build/ntdll-unix/virtual_ios.c:27356` | `virtual_check_buffer_for_read` probes via `mach_vm_read_overwrite` | bad-source `NtWriteVirtualMemory` → `STATUS_PARTIAL_COPY`, no death |
| 6 | `docs/BUILDING.md:93,100` | build-time `git -C wine apply --reverse --check ../patches/wine-opengl-winios.patch` guard | an unpatched `wine/` tree fails the build, not the device |

Order: 2 (removes the load-time death), then 1 (the launcher), then 3-5; every
claim is anchored to a file:line or a log line, anything else is inference.
