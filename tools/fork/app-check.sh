#!/usr/bin/env bash
# fork-only: build just the Madeira app target (no signing, no packaging).
# Same xcodebuild invocation as tools/build/package-ipa.sh:31-42, but with a
# per-clone DerivedData dir under /tmp so clones never share build state.
# Machine-wide limit of 2 concurrent runs via two mkdir-atomic lock slots.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if command -v sha1sum >/dev/null 2>&1; then
    HASH="$(printf '%s' "$ROOT" | sha1sum | cut -c1-12)"
else
    HASH="$(printf '%s' "$ROOT" | shasum -a 1 | cut -c1-12)"
fi
DD="/tmp/madeira-dd-$HASH"

LOCK1="/tmp/madeira-app-check.lock.1"
LOCK2="/tmp/madeira-app-check.lock.2"
TAKEN=""

release_lock() {
    if [ -n "$TAKEN" ] && [ -d "$TAKEN" ]; then
        rm -rf "$TAKEN"
    fi
    TAKEN=""
}
trap release_lock EXIT INT TERM

# A lock dir whose PID file names a dead process is stale: remove and retry.
# A lock dir with no PID file at all is left alone unless it is older than
# 30 minutes (crashed between mkdir and pid write), then reaped as well.
reap_if_stale() {
    local lock="$1"
    [ -d "$lock" ] || return 1
    if [ -f "$lock/pid" ]; then
        local pid
        pid="$(cat "$lock/pid" 2>/dev/null || true)"
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            rm -rf "$lock"
            return 0
        fi
    else
        if [ -n "$(find "$lock" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
            rm -rf "$lock"
            return 0
        fi
    fi
    return 1
}

while [ -z "$TAKEN" ]; do
    for lock in "$LOCK1" "$LOCK2"; do
        if mkdir "$lock" 2>/dev/null; then
            echo "$$" > "$lock/pid"
            TAKEN="$lock"
            break
        fi
        reap_if_stale "$lock" || true
    done
    if [ -z "$TAKEN" ]; then
        sleep 10
    fi
done

START="$(date +%s)"
LOG="$(mktemp /tmp/madeira-app-check.log.XXXXXX)"

set +e
xcodebuild \
    -project "$ROOT/app/Madeira.xcodeproj" \
    -scheme Madeira \
    -configuration Debug \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DD" \
    IPHONEOS_DEPLOYMENT_TARGET=18.0 \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    build >"$LOG" 2>&1
RC=$?
set -u

END="$(date +%s)"
ELAPSED="$((END - START))"

if [ "$RC" -ne 0 ]; then
    tail -40 "$LOG"
    echo "app-check: FAIL (exit $RC, ${ELAPSED}s; full log: $LOG)" >&2
else
    echo "app-check: OK (${ELAPSED}s)"
    rm -f "$LOG"
fi
exit "$RC"
