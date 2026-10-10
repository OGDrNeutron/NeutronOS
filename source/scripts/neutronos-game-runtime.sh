#!/usr/bin/env bash
set -uo pipefail

if [[ "$#" -lt 4 ]]; then
    printf 'Usage: %s STATUS_FILE LOG_FILE PID_FILE COMMAND [ARG ...]\n' "$0" >&2
    exit 64
fi

STATUS_FILE="$1"
LOG_FILE="$2"
PID_FILE="$3"
shift 3

mkdir -p -- "$(dirname -- "$STATUS_FILE")" "$(dirname -- "$LOG_FILE")" "$(dirname -- "$PID_FILE")"
TMP_STATUS="${STATUS_FILE}.tmp.$$"
TMP_PID="${PID_FILE}.tmp.$$"
rm -f -- "$TMP_STATUS" "$TMP_PID" "$STATUS_FILE" "$PID_FILE"
: > "$LOG_FILE"

finish() {
    local rc="$1"
    printf '%s\n' "$rc" > "$TMP_STATUS"
    mv -f -- "$TMP_STATUS" "$STATUS_FILE"
    rm -f -- "$PID_FILE" "$TMP_PID"
}
trap 'rc=$?; finish "$rc"' EXIT

# Give the emulator its own session/process group so the independent
# supervisor can close it cleanly without touching openvt or NeutronOS.
setsid "$@" >>"$LOG_FILE" 2>&1 &
child="$!"
printf '%s\n' "$child" > "$TMP_PID"
mv -f -- "$TMP_PID" "$PID_FILE"

set +e
wait "$child"
rc="$?"
set -e
exit "$rc"
