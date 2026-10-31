#!/bin/bash
# Builds tools/fork/tests/rpm-probe.c as a 32-bit and a 64-bit Windows program
# and copies them into the bundle farms (i386-windows, arm64ec-windows) so the
# next package-ipa.sh ships them. Run one with env.MADEIRA_EXE = rpm-probe-32.exe
# (or rpm-probe-64.exe) in madeira.cfg; its "[rpm-probe]" lines land in the log.
set -euo pipefail
R="$(cd "$(dirname "$0")/../../.." && pwd)"
TC="$R/toolchains/llvm-mingw-20260421-ucrt-macos-universal/bin"
OUT="${TMPDIR:-/tmp}/rpm-probe"
mkdir -p "$OUT"
"$TC/i686-w64-mingw32-clang"   -O2 -o "$OUT/rpm-probe-32.exe" "$R/tools/fork/tests/rpm-probe.c" -lkernel32
"$TC/x86_64-w64-mingw32-clang" -O2 -o "$OUT/rpm-probe-64.exe" "$R/tools/fork/tests/rpm-probe.c" -lkernel32
cp "$OUT/rpm-probe-32.exe" "$R/app/Madeira/i386-windows/"
cp "$OUT/rpm-probe-64.exe" "$R/app/Madeira/arm64ec-windows/"
ls -l "$R/app/Madeira/i386-windows/rpm-probe-32.exe" "$R/app/Madeira/arm64ec-windows/rpm-probe-64.exe"
