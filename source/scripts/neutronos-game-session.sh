#!/usr/bin/env bash
set -uo pipefail

if [[ "$#" -lt 3 ]]; then
    printf 'Usage: %s STATUS_FILE LOG_FILE COMMAND [ARG ...]\n' "$0" >&2
    exit 64
fi

STATUS_FILE="$1"
LOG_FILE="$2"
shift 2

mkdir -p -- "$(dirname -- "$STATUS_FILE")" "$(dirname -- "$LOG_FILE")"
TMP_STATUS="${STATUS_FILE}.tmp.$$"
rm -f -- "$TMP_STATUS" "$STATUS_FILE"
: > "$LOG_FILE"

finish() {
    local rc="$1"
    printf '%s\n' "$rc" > "$TMP_STATUS"
    mv -f -- "$TMP_STATUS" "$STATUS_FILE"
}

trap 'rc=$?; finish "$rc"' EXIT

"$@" >>"$LOG_FILE" 2>&1
exit $?
