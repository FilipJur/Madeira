#!/usr/bin/env bash
# Microsoft's VC++ 2013 x64 runtime (msvcr120.dll + msvcp120.dll, 12.0.40664) for a game
# folder, app-local. Wine's builtin msvcr120 leaves the ConcRT/PPL task entry points as stubs
# (_AsyncTaskCollection::_NewCollection, _TaskCollection::_Schedule/_RunAndWait/_Cancel, ...);
# a game that uses concurrency::task crashes on the first call. Divinity: Original Sin EE does
# it on every profile/save write (EoCApp.exe+0x123ac5).
#
#   tools/fork/vcredist2013-x64.sh <out-dir>       writes <out-dir>/msvcr120.dll, msvcp120.dll
#
# Copy both next to the game's exe: the loader searches the application directory first, and
# msvcp120 must come from the same runtime as msvcr120. Needs curl and 7zz (brew install sevenzip).
set -euo pipefail
OUT="${1:?usage: $0 <out-dir>}"
URL="https://aka.ms/highdpimfc2013x64enu"   # vcredist_x64.exe 12.0.40664 (Microsoft)
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
curl -fsSL -o "$W/vcredist_x64.exe" "$URL"
# WiX Burn bundle: the payload is an attached cab of MSI cabs; the runtime files are F_CENTRAL_*_x64.
7zz x -t# -o"$W/parts" -y "$W/vcredist_x64.exe" >/dev/null
for c in "$W"/parts/*.cab; do 7zz x -o"$W/c" -y "$c" >/dev/null; done
for c in "$W"/c/*; do 7zz x -o"$W/f" -y "$c" >/dev/null 2>&1 || true; done
mkdir -p "$OUT"
for n in msvcr120 msvcp120; do
    [ -f "$W/f/F_CENTRAL_${n}_x64" ] || { echo "F_CENTRAL_${n}_x64 not in the bundle" >&2; exit 1; }
    cp "$W/f/F_CENTRAL_${n}_x64" "$OUT/$n.dll"
done
shasum -a 256 "$OUT/msvcr120.dll" "$OUT/msvcp120.dll"
