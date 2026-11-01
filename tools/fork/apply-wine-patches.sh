#!/bin/bash
# Idempotently apply the fork's Wine source patches to the wine/ working tree.
# Called at the start of build/ntdll-unix/build.sh, build/wine-i386/build.sh
# and build/wine-pe/build-modules.sh (before anything compiles Wine sources),
# so an unpatched tree is patched first, and a tree the patch neither applies
# to nor is already in fails the build, instead of producing a broken 32-bit
# opengl32 on device (docs/fork/research/dx9-batman-fix.md section 2: the
# wow64 thunks must convert embedded guest pointers with ios_wow_host_ptr()).
set -eu
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WINE="$R/wine"
PATCH="$R/patches/wine-opengl-winios.patch"

[ -f "$PATCH" ] || { echo "apply-wine-patches: patch not found: $PATCH" >&2; exit 1; }
[ -d "$WINE" ] || { echo "apply-wine-patches: wine tree not found: $WINE" >&2; exit 1; }

if git -C "$WINE" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "apply-wine-patches: $(basename "$PATCH") already applied, skipping"
    exit 0
fi
if ! git -C "$WINE" apply --check "$PATCH" >/dev/null 2>&1; then
    echo "apply-wine-patches: $PATCH does not apply (check 'git -C wine status' for conflicts)" >&2
    exit 1
fi
git -C "$WINE" apply "$PATCH"
echo "apply-wine-patches: applied $(basename "$PATCH")"
