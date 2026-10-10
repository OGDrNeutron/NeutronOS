#!/usr/bin/env bash
set -u
ROOT="$(readlink -f "${1:-$HOME/NeutronOS}")"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$ROOT/state/diagnostics/patch60j-runtime-$STAMP.txt"
mkdir -p "$(dirname "$REPORT")"
{
  echo "NeutronOS Patch 60J Runtime Health"
  echo "Generated: $(date --iso-8601=seconds)"
  echo "Root: $ROOT"
  echo
  echo "== Regression checker =="
  python3 "$ROOT/scripts/neutronos-regression-check.py" "$ROOT" --runtime || true
  echo
  echo "== Service =="
  systemctl --no-pager --full status neutronos.service 2>&1 || true
  echo
  echo "== Recent NeutronOS log =="
  journalctl -u neutronos.service -n 160 --no-pager 2>&1 || true
  echo
  echo "== Browser runtime =="
  tail -160 "$ROOT/state/apps/browser-runtime/last-runtime.log" 2>&1 || true
  echo
  echo "== Throttle/voltage =="
  journalctl -b -k --no-pager 2>&1 | grep -iE 'under.?voltage|voltage|thrott' | tail -80 || true
} | tee "$REPORT"
echo "Runtime health report saved to: $REPORT"
