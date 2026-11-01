#!/usr/bin/env bash
# Builds the VoidLink touch-profile generator into /tmp and runs it.
#   - compiles the ported ObjC model (app/Madeira/VLTouch/Model/{OSCProfile,OnScreenButtonState}.m)
#     and ProfileFileContainer.swift straight from the app tree (nothing copied),
#   - plus a UIKit shim (shim/) and the tool sources (src/),
#   - reads specs/*.json and writes dist/vltouch-profiles/fork-presets.bin,
#   - reads specs/derived/*.json (bundled templates, edited) and writes dist/vltouch-profiles/fork-derived.bin,
#   - then decodes both files through the app's import path and verifies them.
# macOS only; no Xcode project, no signing, no device.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
BUILD="${VLPROFILES_BUILD:-/tmp/vlprofiles-build}"
OUT="${VLPROFILES_OUT:-$REPO/dist/vltouch-profiles/fork-presets.bin}"
DERIVED_OUT="${VLPROFILES_DERIVED_OUT:-$REPO/dist/vltouch-profiles/fork-derived.bin}"
MODEL="$REPO/app/Madeira/VLTouch/Model"

mkdir -p "$BUILD"
SDK="$(xcrun --show-sdk-path)"

for m in OSCProfile OnScreenButtonState; do
  # -include: the model files call UIKit's NSCoder CGPoint additions without importing anything for them.
  clang -fobjc-arc -fmodules -isysroot "$SDK" -I "$HERE/shim" -I "$MODEL" -include "$HERE/shim/VLCoderShim.h" -c "$MODEL/$m.m" -o "$BUILD/$m.o"
done
clang -fobjc-arc -fmodules -isysroot "$SDK" -I "$HERE/shim" -I "$MODEL" -c "$HERE/shim/VLCoderShim.m" -o "$BUILD/VLCoderShim.o"

swiftc -O -swift-version 5 -sdk "$SDK" -import-objc-header "$HERE/shim/Bridge.h" -Xcc -I -Xcc "$HERE/shim" -Xcc -I -Xcc "$MODEL" \
  "$HERE"/src/*.swift "$MODEL/ProfileFileContainer.swift" \
  "$BUILD/OSCProfile.o" "$BUILD/OnScreenButtonState.o" "$BUILD/VLCoderShim.o" \
  -o "$BUILD/vlprofiles"

"$BUILD/vlprofiles" --repo "$REPO" --specs "$HERE/specs" --out "$OUT" --derived "$HERE/specs/derived" --derived-out "$DERIVED_OUT" "$@"
