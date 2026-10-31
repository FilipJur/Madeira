/*
 * rpm-probe: regression check for Unix-side guest-memory faults (fork; see
 * docs/fork/research/unix-fault-safety.md §5.2 and dx9-batman-fix.md).
 * Batman: Arkham Asylum died in ReadProcessMemory on its own reserved,
 * uncommitted memory. On Windows every case below fails or succeeds cleanly.
 * Built 32- and 64-bit by build-rpm-probe.sh; run with env.MADEIRA_EXE.
 * Output goes to stderr and OutputDebugString (both reach Madeira's log),
 * prefixed "[rpm-probe]". Exit code = number of failures.
 */
#include <windows.h>
#include <stdio.h>

typedef LONG (WINAPI *pNtVM)(HANDLE, void *, const void *, SIZE_T, SIZE_T *);
static int fails;

static void say(const char *line)
{
    DWORD written;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), line, (DWORD)lstrlenA(line), &written, NULL);
    OutputDebugStringA(line);
}

static void ck(const char *name, int ok, const char *want, unsigned long long got)
{
    char line[160];
    snprintf(line, sizeof line, "[rpm-probe] %-32s %s want=%-18s got=0x%llx\n",
             name, ok ? "PASS" : "FAIL", want, got);
    say(line);
    if (!ok) fails++;
}

int main(void)
{
    SYSTEM_INFO si; MEMORY_BASIC_INFORMATION mbi; SIZE_T page, n; int v = 0x11223344; LONG st;
    HMODULE nt = GetModuleHandleA("ntdll.dll");
    pNtVM rvm = (pNtVM)(void *)GetProcAddress(nt, "NtReadVirtualMemory");
    pNtVM wvm = (pNtVM)(void *)GetProcAddress(nt, "NtWriteVirtualMemory");
    char *res, *nc, *gd, *dst; char line[96];

    GetSystemInfo(&si); page = si.dwPageSize;
    snprintf(line, sizeof line, "[rpm-probe] start: %u-bit, page %lu\n",
             (unsigned)sizeof(void *) * 8, (unsigned long)page);
    say(line);
    res = VirtualAlloc(NULL, 4 * page, MEM_RESERVE, PAGE_NOACCESS);   /* reserved, never committed */
    nc  = VirtualAlloc(NULL, page, MEM_COMMIT, PAGE_NOACCESS);
    gd  = VirtualAlloc(NULL, page, MEM_COMMIT, PAGE_READWRITE);
    dst = VirtualAlloc(NULL, page, MEM_COMMIT, PAGE_READWRITE);
    *(int *)gd = 0x5a5a5a5a; *(int *)dst = 0;
    { DWORD old; VirtualProtect(gd, page, PAGE_READWRITE | PAGE_GUARD, &old); }

    SetLastError(0);
    ck("RPM reserved-uncommitted",
       !ReadProcessMemory(GetCurrentProcess(), res + page, &v, 4, &n) && GetLastError() == ERROR_PARTIAL_COPY,
       "FALSE/299", GetLastError());
    SetLastError(0);
    ck("RPM committed NOACCESS",
       !ReadProcessMemory(GetCurrentProcess(), nc, &v, 4, &n) && GetLastError() == ERROR_PARTIAL_COPY,
       "FALSE/299", GetLastError());
    VirtualQuery(gd, &mbi, sizeof mbi);
    ck("guard armed", (mbi.Protect & PAGE_GUARD) != 0, "PAGE_GUARD", mbi.Protect);
    v = 0;
    ck("RPM guard page", ReadProcessMemory(GetCurrentProcess(), gd, &v, 4, &n) && v == 0x5a5a5a5a,
       "TRUE/value", (unsigned)v);
    VirtualQuery(gd, &mbi, sizeof mbi);
    ck("guard consumed", !(mbi.Protect & PAGE_GUARD), "no PAGE_GUARD", mbi.Protect);
    st = rvm(GetCurrentProcess(), res + page, &v, 4, &n);          /* the Batman call */
    ck("NtReadVirtualMemory reserved", st == (LONG)0x8000000D, "0x8000000d", (unsigned long long)(ULONG)st);
    st = wvm(GetCurrentProcess(), dst, res + page, 4, &n);         /* bad source */
    ck("NtWriteVirtualMemory bad source", st == (LONG)0x8000000D || st == (LONG)0xC0000005,
       "0x8000000d|c0000005", (unsigned long long)(ULONG)st);
    ck("IsBadReadPtr reserved", IsBadReadPtr(res + page, 4) != FALSE, "TRUE", 0);
    mbi.State = 0;
    ck("VirtualQuery reserved", VirtualQuery(res + page, &mbi, sizeof mbi) == sizeof mbi &&
       mbi.State == MEM_RESERVE, "MEM_RESERVE", mbi.State);
    snprintf(line, sizeof line, "[rpm-probe] %d failure(s)\n", fails);
    say(line);
    return fails;
}
