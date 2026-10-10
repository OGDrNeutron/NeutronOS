#!/usr/bin/env bash
set -euo pipefail

SAMPLES="${1:-10}"
DELAY="${2:-2}"

if ! [[ "$SAMPLES" =~ ^[0-9]+$ ]] || [ "$SAMPLES" -lt 1 ]; then
  echo "Usage: $0 [samples] [delay-seconds]" >&2
  exit 2
fi

printf 'NeutronOS memory report (%s samples, %ss apart)\n' "$SAMPLES" "$DELAY"
printf '%-19s %8s %8s %8s %8s\n' "TIME" "USED%" "AVAILMB" "SHELLMB" "SHELL%"

for ((i=0; i<SAMPLES; ++i)); do
  total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  avail_kb=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  used_pct=$(awk -v t="$total_kb" -v a="$avail_kb" 'BEGIN { if (t>0) printf "%.1f", ((t-a)/t)*100; else print "0.0" }')

  shell_rss_kb=0
  shell_pct="0.0"
  shell_pid=$(pgrep -xo NeutronShell || true)
  if [ -n "$shell_pid" ] && [ -r "/proc/$shell_pid/status" ]; then
    shell_rss_kb=$(awk '/^VmRSS:/ {print $2}' "/proc/$shell_pid/status")
    shell_pct=$(awk -v r="$shell_rss_kb" -v t="$total_kb" 'BEGIN { if (t>0) printf "%.1f", (r/t)*100; else print "0.0" }')
  fi

  printf '%-19s %7s%% %8.0f %8.1f %7s%%\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "$used_pct" \
    "$(awk -v a="$avail_kb" 'BEGIN {print a/1024}')" \
    "$(awk -v r="$shell_rss_kb" 'BEGIN {print r/1024}')" \
    "$shell_pct"

  if [ "$i" -lt $((SAMPLES-1)) ]; then
    sleep "$DELAY"
  fi
done

printf '\nLargest resident processes:\n'
ps -eo pid,comm,rss,%mem --sort=-rss | head -12
