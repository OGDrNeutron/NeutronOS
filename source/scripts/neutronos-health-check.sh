#!/usr/bin/env bash
set -u

ROOT="${1:-${NEUTRONOS_ROOT:-$HOME/NeutronOS}}"
AUDIT="$ROOT/scripts/neutronos-qml-audit.py"

echo "NeutronOS release-candidate health check"
echo "Root: $ROOT"
echo

if [[ ! -d "$ROOT" ]]; then
    echo "ERROR: NeutronOS root was not found." >&2
    exit 2
fi

echo "== Service =="
systemctl --no-pager --full is-active neutronos.service 2>/dev/null || true
systemctl --no-pager --full status neutronos.service 2>/dev/null | sed -n '1,28p' || true

echo
echo "== Process usage =="
ps -C NeutronShell -o pid=,etimes=,%cpu=,%mem=,rss=,cmd= 2>/dev/null || echo "NeutronShell is not running."
ps -C bluetoothd -o pid=,etimes=,%cpu=,%mem=,rss=,cmd= 2>/dev/null || true

echo
echo "== Source audit =="
if [[ -x "$AUDIT" ]]; then
    python3 "$AUDIT" "$ROOT/qml" || true
else
    echo "QML audit script not found: $AUDIT"
fi

echo
echo "== Recent shell errors =="
journalctl -u neutronos.service -n 120 --no-pager 2>/dev/null \
    | grep -Ei 'error|failed|warning|qml|segfault|abort' \
    | tail -60 \
    || true

echo
echo "== Runtime state size =="
du -sh /var/lib/neutronos 2>/dev/null || true

echo
echo "Health check complete."
