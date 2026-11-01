# Unix-side `__TRY` is dead on iOS — systemic fix

Why **any** fault taken inside Wine's Unix code by a guest-memory access kills the process on this port, and one fix that restores upstream's contract for every site at once. Point fixes for single syscalls (`docs/fork/research/dx9-batman-fix.md`) are right but leave a landmine per site. Evidence: `/tmp/g2/dev/main6.txt`, `main5.txt` (Batman, `env.MADEIRA_NO_GL=1`), `bm.txt`.

> **Review corrections (2026-11-01).** `STATUS_PARTIAL_COPY` is `0x8000000D`
> (`wine/include/ntstatus.h:232`); `0x8000001A` below is `STATUS_NO_MORE_ENTRIES`.
> The committed probe is `tools/fork/tests/rpm-probe.c` (built by
> `tools/fork/tests/build-rpm-probe.sh`), not `tests/x86/`. Its guard-page case accepts a
> clean read or a clean failure, since Windows' result there is not established. The
> §5.2 sketch writes the guarded page before checking it is armed, which disarms it.
> Line anchors in §2 predate the landed fix (`fa7fb5b`, `2048b62`, `b944af8`).

---

## 0. Verdict

The Unix side of this port has **no working fault-recovery mechanism**. Upstream turns a fault inside a syscall implementation into a `longjmp` to the enclosing Unix-side `__TRY` (`handle_syscall_fault`); on Darwin *every* access violation arrives as **SIGBUS** (`signal_arm64_ios.c:13974`, `:14429`), yet `handle_syscall_fault` is wired only into `segv_handler` (`:12011`). `bus_handler` — the one that actually runs — has neither the `jmp_buf` branch nor the `is_inside_syscall` branch, so the fault falls into `setup_exception()` and becomes a *guest* SEH frame whose `sp` is the **syscall kernel stack**; `call_seh_handlers` rejects it (`main6.txt:12792-12794`) → `NtTerminateProcess(0x1f)`.

Fix = give the BUS path and the Mach delivery path the two branches upstream gives the SEGV path: ~50 lines, no per-syscall work, covering `NtReadVirtualMemory`, `NtWriteVirtualMemory`, both `virtual_check_buffer_for_*`, `NtReadFile`/`NtDeviceIoControlFile` buffer checks, `NtQueryVirtualMemory`, `WM_GETTEXT`, and every future `__TRY`.

---

## 1. How `__TRY` works upstream, and how this port breaks it

### 1.1 The Unix-side mechanism (the one that matters)

Wine has two unrelated `__TRY`s; only the first concerns Unix code.

| | Unix-side (relevant) | PE-side (not this bug) |
|---|---|---|
| macro | `include/wine/unixlib.h:94-116` | `include/wine/exception.h:150-196` |
| save | libc `setjmp(jmp_buf)` | `__wine_setjmpex` → `NTDLL__setjmpex` (`ntdll/signal_arm64.c:860-879`: x19-x28/fp/lr/sp/fpcr/fpsr/d8-d15) |
| record | one `void *`, `ntdll_thread_data.jmp_buf` (`unix/unix_private.h:143`) = `TEB+GdiTebBatch+0xe0` = **TEB+0x3d0** (`unix_private.h:147-155`) | `EXCEPTION_REGISTRATION_RECORD` chain walked by the guest dispatcher |
| arm/disarm | `ntdll_set_exception_jmp_buf()` (`unix/thread.c:1896-1900`), **asserts `!existing`**: one slot per thread | push/pop frame |

Upstream's bridge is `handle_syscall_fault` (`wine/dlls/ntdll/unix/signal_arm64.c:1000-1060`):

```
1005  if (!is_inside_syscall( SP_sig(context) )) return FALSE;
1038      if (ntdll_get_thread_data()->jmp_buf)  /* armed __TRY */
1041          REGn_sig(0,context)=jmp_buf; REGn_sig(1,context)=1; PC_sig(context)=longjmp; jmp_buf=NULL;
1047      else                                   /* no __TRY: fail the syscall */
1050-3    x0=rec->ExceptionCode; sp=frame; pc=__wine_syscall_dispatcher_return;
1063 segv_handler: 1074 if (!virtual_handle_fault(&rec,SP_sig)) return;
                   1075 if (handle_syscall_fault(context,&rec)) return;
                   1076 setup_exception(context,&rec);
1113 bus_handler:   rec = { EXCEPTION_DATATYPE_MISALIGNMENT };
1117               setup_exception(sigcontext,&rec);  /* no jmp_buf, no syscall check */
```

The discriminator is **`sp`, not `pc`**: Unix code always runs on the per-thread kernel stack — both dispatchers switch to it (`signal_arm64.c:1724` `mov sp,x10` in `__wine_unix_call_dispatcher`:1705; same in `__wine_syscall_dispatcher`:1539); `is_inside_syscall()` (`unix_private.h:469-473`) is `sp ∈ [kernel_stack, syscall_frame]`, `kernel_stack_size = 0x100000` (`:181`). Guest code never runs there: `call_user_mode_callback` restores `mov sp,x0` before branching to the guest (`signal_arm64.c:860`,`:871`). Upstream's own BUS path has the same hole; on Linux it is nearly unreachable (an unmapped-page load is `SIGSEGV`/`MAPERR`) — on Darwin it is the main road.

### 1.2 What this port does instead (Batman trace)

1. **Mach handler first**: `ios_mach_exception_thread` (`:2432`) → `:5874-5882` → `ios_mach_deliver_guest_exception_inner` (`:8612`). The TEB is picked by stack containment; the faulting `sp` is the kernel stack, which no TEB owns (`main6.txt:12665` `rev=ml372 … does NOT contain sp=0x12637fbd0`) → ml378 best-effort (`:8833-8850`, `main6.txt:12666`). The host-pc filter then declines: `:9145-9151` claims only pool / `<4GB` / `[0x7000_0000_0000,0x7400_0000_0000)` pcs, and `_platform_memmove` at `0x19f37215c` is none (3 attempts, `main6.txt:12730-12731`, `:12760`).
2. **Kernel converts to `SIGBUS(BUS_ADRERR)`** → **`bus_handler`** (`:13664`, `main6.txt:12776`). Diagnostics (`[bus-rgn]`, `:12777-12782` `VERDICT ANONYMOUS, NEVER RESIDENT`), read probe fails, ml420 `BUS->AV` (`:14392`) sets `rec=c0000005/READ/0x798468ff6e` and `goto bus_fatal` (`:14639`).
3. **No `__TRY` check anywhere**: `bus_handler` never reads `ntdll_get_thread_data()->jmp_buf` nor calls `is_inside_syscall`; the only exit is `setup_exception(sigcontext,&rec)` (`:14844`).
4. **A guest frame is built on the kernel stack**: `setup_exception` (`:8549`) → `setup_raise_exception` (`:8507`) → `virtual_setup_exception(sp&~15,…)` (`virtual_ios.c:26767`). That `sp` is outside every Wine thread stack (`is_inside_thread_stack`, `virtual_ios.c:26465-26485`), so the ml262 "outside thread stack" branch (`:26772-26800`) WARNs (suppressed: the log has **zero** `warn:` lines) and returns a pointer on the kernel stack → `call_seh_handlers invalid frame 12637fbd0 (0000000126388000-0000000126B7FD20)` → `NtRaiseException EXCEPTION_STACK_INVALID` → `NtTerminateProcess(exit_code=0x1f)` (`main6.txt:12792-12794`; identical cascade at `main5.txt:13059`, base `0x12A008000` — two pseudo-processes, one defect).

WoW64 translation was correct: source `0x798468ff6e` = window base `0x7900000000` (`main6.txt:8727`) + guest `0x8468ff6e` (`ios_wow.h:3-18`), reading a `prot=0` anonymous region that never materialises (`main6.txt:12778-12780`). Only the `longjmp` is missing. **Generality**: because *all* Unix code runs on the kernel stack, *every* exception escaping a syscall — with or without `__TRY` — is undeliverable to the guest; issue #397's `call_seh_handlers invalid frame` is the same terminal step from another cause (wrong TEB).

---

## 2. Systemic fix design

Contract to restore, for any fault while `sp` ∈ the thread's kernel stack: armed `__TRY` → `x0=jmp_buf, x1=1, pc=longjmp`, **slot cleared first**; no `__TRY` → dispatcher return (`x0=status, sp=frame, pc=__wine_syscall_dispatcher_return`); never a guest frame.

### 2.1 Two helpers (next to `handle_syscall_fault`, ~`:9790`)

```c
/* the pc test the fork already uses at :9145-9151, plus the WoW windows it misses (0x79…). */
static inline BOOL ios_pc_is_guest( uintptr_t pc )
{
    extern void *ios_jit_rx_base_global; extern size_t ios_jit_pool_size_global;
    extern ULONG_PTR ios_wow_base( void ) __attribute__((weak));
    uintptr_t rx = (uintptr_t)ios_jit_rx_base_global, wb = ios_wow_base ? ios_wow_base() : 0;
    return (rx && pc >= rx && pc < rx + ios_jit_pool_size_global) || ios_jit_low_contains( pc ) ||
           pc < 0x100000000ULL || (pc >= 0x7000000000ULL && pc < 0x7400000000ULL) ||
           (wb && pc >= wb && pc < wb + ((uintptr_t)1 << 32));
}

static BOOL ios_unix_try_resume( ucontext_t *context, uintptr_t pc, int is_data_fault )
{
    struct ntdll_thread_data *td; void *jmp;
    if (!is_data_fault || ios_pc_is_guest( pc )) return FALSE;
    if (!is_inside_syscall( SP_sig( context ) )) return FALSE;   /* not unix code */
    if (!NtCurrentTeb()) return FALSE;
    td = ntdll_get_thread_data();
    if (!(jmp = td->jmp_buf)) return FALSE;
    td->jmp_buf = NULL;                    /* MANDATORY: thread.c:1898 asserts */
    REGn_sig(0,context) = (ULONG_PTR)jmp; REGn_sig(1,context) = 1;
    PC_sig(context)     = (ULONG_PTR)longjmp;
    return TRUE;
}
```

`ntdll_get_thread_data()` is `NtCurrentTeb()+GdiTebBatch` (`unix_private.h:157`), and the Unix-side `NtCurrentTeb()` is the TLS lookup built for signal context (`wine/dlls/ntdll/unix/thread.c:1634`, `pthread_getspecific(teb_key)`) — **not** x18 — so the resumed Unix code needs no x18 restoration; `ios_fixup_x18_for_return` (`:9806-9819`) only rewrites pool pcs and never fires on a `longjmp` pc.

### 2.2 Insertion A — `bus_handler` (the fix that would have saved Batman)

`signal_arm64_ios.c:13664`; insert right after `pc`/`is_exec_fault` are computed (`:13737-13739`), **before** the store emulator and the ml420 conversion:

```c
    /* madeira-unix-fault: a data fault taken by UNIX code is never a guest exception.
     * Batman died here (main6.txt:12776-12794): memmove on a never-materialised page. */
    if (!is_exec_fault && ios_unix_try_resume( bus_ctx, (uintptr_t)pc, TRUE ))
    {
        static unsigned long n;
        if (ios_sig_storm_gate( &n )) ERR( "[unix-try] signal tid=%04x pc=%p addr=%p -> longjmp\n",
                                          (unsigned)GetCurrentThreadId(), pc, siginfo->si_addr );
        return;
    }
    if (!is_exec_fault && !ios_pc_is_guest( (uintptr_t)pc ))
    {
        EXCEPTION_RECORD u = { EXCEPTION_ACCESS_VIOLATION, 0, NULL, pc, 2,
                               { EXCEPTION_READ_FAULT, (ULONG_PTR)siginfo->si_addr } };
        if (handle_syscall_fault( bus_ctx, &u ))      /* upstream's no-__TRY branch */
        {
            static unsigned long n;
            if (ios_sig_storm_gate( &n )) ERR( "[unix-fault] signal tid=%04x pc=%p addr=%p -> return\n",
                                              (unsigned)GetCurrentThreadId(), pc, siginfo->si_addr );
            return;
        }
    }
```

`handle_syscall_fault` re-checks `is_inside_syscall`; with the slot cleared, `:9773` takes the else branch. Use the ESR WnR bit (`get_fault_esr`) for `EXCEPTION_WRITE_FAULT` if preferred.

### 2.3 Insertion B — Mach delivery path (the route that fires under a debugger)

`ios_mach_deliver_guest_exception_inner` runs on the exception-server thread: read the faulting thread's data with `mach_vm_read_overwrite`, write back through `*state` (the caller does `thread_set_state` and replies `KERN_SUCCESS` on return 1 — `:5874-5887`). Insert after the alignment emulation and the `virtual_handle_fault` page service (`:9130`), **before** the host-pc filter (`:9145`):

```c
static int ios_mach_unix_try_resume( arm_thread_state64_t *state, uintptr_t teb, uintptr_t pc )
{
    enum { OFF_KSTACK = offsetof(TEB,GdiTebBatch)+offsetof(struct ntdll_thread_data,kernel_stack), /*0x3a8*/
           OFF_JMP    = offsetof(TEB,GdiTebBatch)+offsetof(struct ntdll_thread_data,jmp_buf) };    /*0x3d0*/
    uint64_t kstack = 0, jmp = 0, sp = arm_thread_state64_get_sp( *state );
    mach_vm_size_t got = 0;
    if (!teb || ios_pc_is_guest( pc )) return 0;
    if (mach_vm_read_overwrite( mach_task_self(), teb+OFF_KSTACK, 8,
                                (mach_vm_address_t)&kstack, &got ) != KERN_SUCCESS || got != 8) return 0;
    /* proves BOTH that this TEB is this thread's (issue #397's slot-0 fallback is not
     * evidence) AND that the fault is in unix code: the Mach-side is_inside_syscall */
    if (!kstack || sp < kstack || sp >= kstack + 0x100000) return 0;
    if (mach_vm_read_overwrite( mach_task_self(), teb+OFF_JMP, 8,
                                (mach_vm_address_t)&jmp, &got ) != KERN_SUCCESS || got != 8 || !jmp) return 0;
    { uint64_t zero = 0; mach_vm_write( mach_task_self(), teb+OFF_JMP, (vm_offset_t)&zero, 8 ); }
    arm_thread_state64_set_pc_fptr( *state, (void *)longjmp );
    state->__x[0] = jmp; state->__x[1] = 1; state->__x[18] = teb;
    return 1;
}
...
    if (exception != EXC_BAD_INSTRUCTION &&
        ios_mach_unix_try_resume( state, thread_teb, (uintptr_t)pc )) return 1;
```

### 2.4 Insertion C (SHOULD) and D (after A+B)

**C — `setup_exception` backstop.** `:8549`, before `save_context()`: if `is_inside_syscall(SP_sig(sigcontext))` and the record is an access violation/misalignment, try `ios_unix_try_resume()`, else log `ERR("[unix-fault] … kernel-stack sp with no __TRY")` and `abort_thread(1)` instead of handing the guest a frame it must reject. Defence-in-depth for `ill_handler`/`trap_handler`; not a substitute for A/B, which run before the store emulator rewrites the record.

**D — retire the per-site workarounds.** `ios_ec_hook_peek` (`virtual_ios.c:32402-32408`) exists **only** because of this defect, and its comment records the failure: *“read directly, a protector's packed section (PlayGTAV.exe … Ghost of Tsushima's steam_api64.dll …) raised a SIGBUS that bus_handler hands to the guest without honouring the `__TRY`; the next `__TRY` then asserted (0x80000101) and the game ended at start”* (`:32398-32401`, commit `0d41403`). The other check-then-copy helpers (`ios_reply_host_writable`, `server_ios.c:671-688`; `ios_range_writable`, `virtual_ios.c:26742`) are TOCTOU-prone against a concurrent `mprotect` — the `[bus-reheal]` family — so they should become fast paths in front of a `__TRY`.

### 2.5 Risks

| Risk | Why it bites | Mitigation |
|---|---|---|
| Signal-safety on the faulting thread | handler must not alloc/lock | only `pthread_getspecific` (already used, `:9907`) + `dprintf`; `longjmp` is entered via sigreturn |
| Mach-side TEB is the wrong thread | registry slot-0 fallback (issue #397) would jump *this* thread into *another* thread's stack | kernel-stack containment test (`sp ∈ [teb->kernel_stack,+1MB)`), reject otherwise |
| Slot not cleared | `ntdll_set_exception_jmp_buf` asserts (`thread.c:1898`); next `__TRY` dies `0x80000101` (documented `virtual_ios.c:32398`) | clear before resuming, both paths |
| Re-fault in the `__EXCEPT` body | slot already NULL | degrades to today's behaviour; no loop |
| Guest code that must keep SEH | stealing a guest fault breaks FEX/guest handlers | `ios_pc_is_guest()` gate |
| FEX host-dylib fault while `__TRY` armed | longjmps out of FEX, leaking `CpuStateFrame` | add the ml413 guard already read at `:8877-8891` (`TEB+0x16f8` read-lock) |
| No-`__TRY` fault becomes a silent syscall error | behaviour change vs today's loud death | that *is* upstream (`:1047-1053`); log once per thread |
| Host-code alignment fault | `BUS_ADRALN` in libsystem | emulators at `:14583-14620` run first; only unhandled ones reach A |

**Do not** fix this by probing wine's page bookkeeping before each copy (`virtual_uninterrupted_read_memory`, `virtual.c:4890`): on iOS host protection legitimately diverges from the vprot (`[bus-reheal]`, `main6.txt:12778`, `:14355-14375`), so the probe passes and the load still faults.

---

## 3. Blast radius — Unix-side sites a 32-bit game can reach

Compiled set: `build/ntdll-unix/build.sh:236-290` builds **all** `wine/dlls/ntdll/unix/*.c` with fork overrides (`virtual`→`virtual_ios.c`, `signal_arm64`→`signal_arm64_ios.c`, `server`→`server_ios.c`, …), plus win32u's unix driver (`build/win32u-unix/`).

| # | Site | Guard today | 32-bit guest reaches it via | Today |
|---|---|---|---|---|
| 1 | `NtReadVirtualMemory` current-process `memmove` — `virtual.c:6742` = `virtual_ios.c:34989` | `__TRY` (**dead**) | `ReadProcessMemory(self,…)`, UE3/launcher probes, Steam DRM | fatal — observed (Batman) |
| 2 | `virtual_check_buffer_for_write` — `virtual.c:4856` = `virtual_ios.c:27395` | `__TRY` (**dead**) | `NtReadVirtualMemory:6735`, `NtReadFile` `file.c:7030`, `NtDeviceIoControlFile` `file.c:8081`, socket iov `socket.c:1426` | fatal |
| 3 | `virtual_check_buffer_for_read` — `virtual.c:4822` = `virtual_ios.c:27361` | `__TRY` (**dead**) | `NtWriteVirtualMemory:6779`, `NtWow64WriteVirtualMemory64:7155`, `NtReadFile:7592` | fatal |
| 4 | `NtWriteVirtualMemory` — `virtual.c:6779` | probe #3 + server copy | `WriteProcessMemory` (bad *source*) | fatal |
| 5 | `NtQueryVirtualMemory` `memcpy(buffer,…)` — `virtual.c:6158` | none in the syscall | `VirtualQuery` on reserved/guard edges | fatal if the kernel32 probe misses |
| 6 | `NtWow64ReadVirtualMemory64` — `virtual.c:7123` | probe #2 | wow64 thunks; not 32-bit reachable | — |
| 7 | reply copy `read()` — `server.c:279` → `server_ios.c:690-780` | kernel EFAULT + bounce + `ios_reply_host_writable` | every `NtQuery*` | safe (TOCTOU only) |
| 8 | direct server `memcpy((char*)data+done, vec[i].iov_base,…)` — `build/wineserver/request_ios.c:658`, reply `:620` | **none** | any syscall when `env.MADEIRA_SRV_DIRECT` (off by default) | fatal |
| 9 | `WM_GETTEXT` into a guest buffer — `build/win32u-unix/defwnd_ios.c:2682` | `__TRY` (**dead**) | `GetWindowText` on a default-proc window | fatal |
| 10 | `virtual_uninterrupted_read/write_memory` — `virtual.c:4890,4938` | vprot probe | only `signal_i386.c`/`signal_x86_64.c`, **not compiled here** | not reachable |
| 11 | `KeUserModeCallback` `memcpy(stack->args_data,…)` — `signal_arm64.c:989` | none | `NtUser*` callbacks, unix-owned buffer | not guest-controlled |
| 12 | request iovecs — `server_ios.c:526-588` `writev` | kernel EFAULT → `STATUS_ACCESS_VIOLATION` (`:586`) | `NtWriteFile`, `NtSetInformation*` | safe |

A 32-bit game hits **1, 2, 3, 4, 5** (and 8/9 by config) with ordinary Win32 calls — every `ReadProcessMemory` / `WriteProcessMemory` / `ReadFile`-into-a-lazy-page pattern.

---

## 4. Upstream (willfaust/Madeira) search

`gh` as `FilipJur`, issues + PRs + commits:

| Query | Result |
|---|---|
| `Exception frame is not in stack limits`, `unable to dispatch exception` | **#397** (open) — WoW64 registry exhaustion; same terminal pair `call_seh_handlers invalid frame` / `NtRaiseException …`, different cause (wrong TEB) |
| `BUS->AV`, `NtReadVirtualMemory`, `ReadProcessMemory`, `__TRY`, `check_buffer`, `bus_handler`, `IsBadReadPtr`, `second chance` | **no issues, no PRs** — never filed |
| `SIGBUS` | #329 (Nexon 64 GB reserve), #423 (x18 TEB access) — neighbours |
| `virtual_handle_fault` | #335 (Risk of Rain 2; 2000 identical redeliveries — a *guest* fault) |
| commit `0d41403` (`[ec-hook]`) | names two victims of exactly this defect: **GTA V `PlayGTAV.exe`** (build 451), **Ghost of Tsushima `steam_api64.dll`** (build 515) |
| commit `a2c9a2a` | earlier classification work on the same delivery code (alignment) |

Games with evidence: **Batman: Arkham Asylum** (`main5`/`main6`, `0x1f`), **GTA V / PlayGTAV**, **Ghost of Tsushima**, plus the `0x80000101` `__TRY` assert for any title arming a second `__TRY` after a stolen fault (UE3/SteamStub launchers).

---

## 5. Verification without a device harness

### 5.1 Log signatures

Baseline (`main6.txt:12776-12794`): `err:seh:bus_handler BUS #1 …` → `[bus-rgn] VERDICT ANONYMOUS, NEVER RESIDENT` → `BUS->AV … rev=ml420` → `[exc-disp] raise … code=c0000005` → `call_seh_handlers invalid frame …` → `NtRaiseException Exception frame is not in stack limits` → `NtTerminateProcess … exit_code=0x1f`.

| Fix | Proof line | Must be absent |
|---|---|---|
| A | `[unix-try] signal tid=… pc=… addr=… -> longjmp` | `BUS->AV`, `[exc-disp] raise`, `invalid frame`, `exit_code=0x1f` |
| B | `[unix-try] mach pc=… addr=… -> longjmp` | `[mach-deliver] … DECLINE`, `[fault-stuck]` |
| C | `[unix-fault] tid=… pc=… kernel-stack sp with no __TRY` | `invalid frame` |
| health | `[unix-try] census sig=N mach=M fallback=K` (expect N=2-3 per launcher start, K=0) | growth of N per frame |

Functional proof, same run: the launcher passes the probe (the address now returns `STATUS_PARTIAL_COPY`) and the log continues into D3D9 init instead of `[srv-kill]`.

### 5.2 Regression program (run under Madeira)

`tests/x86/rpm-probe.c`, one source for both bitnesses; exit code = failures; cases: reserved-uncommitted, committed `PAGE_NOACCESS`, `PAGE_GUARD` consume, good page, `IsBadReadPtr`, `VirtualQuery`, raw `NtReadVirtualMemory`, and `WriteProcessMemory` from a bad *source* (probe #3).

```c
#include <windows.h>
#include <stdio.h>
typedef LONG (WINAPI *pNtVM)(HANDLE,void *,const void *,SIZE_T,SIZE_T *);
static int fails;
static void ck(const char *n, int ok, const char *want, unsigned long long got)
{ printf("%-32s %s  want=%-20s got=0x%llx\n", n, ok?"PASS":"FAIL", want, got); if (!ok) fails++; }
int main(void)
{
    SYSTEM_INFO si; MEMORY_BASIC_INFORMATION mbi; SIZE_T page, n; int v = 0x11223344; LONG st;
    HMODULE nt = GetModuleHandleA("ntdll.dll");
    pNtVM rvm = (pNtVM)(void *)GetProcAddress(nt, "NtReadVirtualMemory");
    pNtVM wvm = (pNtVM)(void *)GetProcAddress(nt, "NtWriteVirtualMemory");
    void *res, *nc, *gd, *dst;
    GetSystemInfo(&si); page = si.dwPageSize;
    printf("guest ptr=%u bytes page=%lu\n", (unsigned)sizeof(void *), (unsigned long)page);
    res = VirtualAlloc(NULL, 4*page, MEM_RESERVE, PAGE_NOACCESS);   /* mapped, never committed */
    nc  = VirtualAlloc(NULL, page, MEM_COMMIT, PAGE_NOACCESS);
    gd  = VirtualAlloc(NULL, page, MEM_COMMIT, PAGE_READWRITE | PAGE_GUARD);
    dst = VirtualAlloc(NULL, page, MEM_COMMIT, PAGE_READWRITE);
    *(int *)gd = 0x5a5a5a5a; *(int *)dst = 0;
    SetLastError(0);
    ck("RPM reserved-uncommitted",
       !ReadProcessMemory(GetCurrentProcess(), (char *)res+page, &v, 4, &n) && GetLastError()==299,
       "FALSE/299", GetLastError());
    SetLastError(0);
    ck("RPM committed NOACCESS",
       !ReadProcessMemory(GetCurrentProcess(), nc, &v, 4, &n) && GetLastError()==299, "FALSE/299", GetLastError());
    VirtualQuery(gd, &mbi, sizeof mbi);
    ck("guard armed", (mbi.Protect & PAGE_GUARD) != 0, "PAGE_GUARD", mbi.Protect);
    ck("RPM guard page", ReadProcessMemory(GetCurrentProcess(), gd, &v, 4, &n) && v == 0x5a5a5a5a,
       "TRUE/value", (unsigned)v);
    VirtualQuery(gd, &mbi, sizeof mbi);
    ck("guard consumed", !(mbi.Protect & PAGE_GUARD), "no PAGE_GUARD", mbi.Protect);
    st = rvm(GetCurrentProcess(), (char *)res+page, &v, 4, &n);            /* the Batman call */
    ck("NtReadVirtualMemory reserved", st == (LONG)0x8000001A, "0x8000001a", (unsigned long long)(ULONG)st);
    st = wvm(GetCurrentProcess(), dst, (char *)res+page, 4, &n);           /* probe #3 */
    ck("NtWriteVirtualMemory bad source", st == (LONG)0x8000001A, "0x8000001a", (unsigned long long)(ULONG)st);
    ck("IsBadReadPtr reserved", IsBadReadPtr((char *)res+page, 4) != FALSE, "TRUE", 0);
    mbi.State = 0;
    ck("VirtualQuery reserved", VirtualQuery((char *)res+page, &mbi, sizeof mbi) == sizeof mbi &&
       mbi.State == MEM_RESERVE && mbi.Protect == PAGE_NOACCESS, "RESERVE/NOACCESS", mbi.State);
    printf("%d failure(s)\n", fails);
    return fails;
}
```

Build with the repo toolchain, then drop the binaries where the repo's own tests read them:

```bash
TC=toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin
$TC/i686-w64-mingw32-clang   -O2 -g -o tests/x86/rpm-probe-32.exe tests/x86/rpm-probe.c -lkernel32
$TC/x86_64-w64-mingw32-clang -O2 -g -o tests/x86/rpm-probe-64.exe tests/x86/rpm-probe.c -lkernel32
cp tests/x86/rpm-probe-32.exe app/Madeira/i386-windows/     # dir used by tests/x86/build.sh:29
cp tests/x86/rpm-probe-64.exe app/Madeira/arm64ec-windows/  # dir used by tests/x64/build.sh:8
```

Run with `env.MADEIRA_EXE = rpm-probe-32.exe` in `madeira.cfg` (direct-launch hook per `tests/x86/build.sh:6-10`), then the 64-bit binary. Expect `0 failure(s)`, exactly two `[unix-try]` lines (cases 1 and 5), and **no** `BUS->AV` / `invalid frame`. Without the fix the 32-bit run dies inside case 1 with the `main6.txt:12776-12794` sequence; the 64-bit run also drives case 4 through the native path (`virtual_ios.c:34989`). Keep the pre-fix binary as the negative baseline; a `tests/host/check-*.py`-style checker can assert the pattern from `madeira-log.txt`.

---

## 6. Change in one line

`bus_handler` and `ios_mach_deliver_guest_exception_inner` learn upstream's two branches (`jmp_buf` → `longjmp`, cleared first; else → dispatcher return), gated on `is_inside_syscall(sp)` **and** `!ios_pc_is_guest(pc)` — restoring `__TRY` for every site in §3, keeping guest/FEX faults on SEH, and turning the `EXCEPTION_STACK_INVALID` cascade into a `STATUS_PARTIAL_COPY`.
