#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
import urllib.request
from pathlib import Path

STATE_DIR = Path('/var/lib/neutronos/time')
LAST_GOOD = STATE_DIR / 'last-known-good-epoch'
LAST_ZONE = STATE_DIR / 'last-known-good-timezone'
AUTO_ZONE_DONE = STATE_DIR / 'auto-timezone-detected-v1'
TIMESYNCD_CLOCK = Path('/var/lib/systemd/timesync/clock')
MIN_VALID_EPOCH = 1735689600


def read_epoch(path: Path) -> int:
    try:
        return int(path.read_text(encoding='utf-8').strip())
    except Exception:
        return 0


def atomic_text(path: Path, value: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(value.rstrip('\n') + '\n', encoding='utf-8')
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def atomic_epoch(path: Path, epoch: int) -> None:
    atomic_text(path, str(int(epoch)), 0o600)


def clock_mtime() -> int:
    try:
        return int(TIMESYNCD_CLOCK.stat().st_mtime)
    except Exception:
        return 0


def valid_timezone(zone: str) -> bool:
    zone = str(zone or '').strip()
    if not zone or zone.startswith('/') or '..' in zone:
        return False
    base = Path('/usr/share/zoneinfo').resolve()
    try:
        candidate = (base / zone).resolve()
        return candidate.is_file() and str(candidate).startswith(str(base) + '/')
    except Exception:
        return False


def current_timezone() -> str:
    try:
        link = Path('/etc/localtime').resolve()
        base = Path('/usr/share/zoneinfo').resolve()
        if str(link).startswith(str(base) + '/'):
            zone = str(link.relative_to(base))
            if valid_timezone(zone):
                return zone
    except Exception:
        pass
    try:
        zone = Path('/etc/timezone').read_text(encoding='utf-8').strip()
        if valid_timezone(zone):
            return zone
    except Exception:
        pass
    return 'UTC'


def set_timezone(zone: str) -> bool:
    if not valid_timezone(zone):
        return False
    result = subprocess.run(
        ['/usr/bin/timedatectl', 'set-timezone', zone],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode == 0:
        atomic_text(LAST_ZONE, zone, 0o600)
        return True
    return False


def detect_network_timezone(timeout: int = 5) -> str:
    endpoints = [
        ('https://worldtimeapi.org/api/ip', 'json'),
        ('https://ipapi.co/timezone/', 'text'),
    ]
    headers = {'User-Agent': 'NeutronOS/1.0 timezone bootstrap'}
    for url, kind in endpoints:
        try:
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read(8192).decode('utf-8', errors='replace').strip()
            if kind == 'json':
                value = json.loads(raw)
                zone = str(value.get('timezone', '')).strip() if isinstance(value, dict) else ''
            else:
                zone = raw.splitlines()[0].strip() if raw else ''
            if valid_timezone(zone):
                return zone
        except Exception:
            continue
    return ''


def restore() -> int:
    saved_zone = ''
    try:
        saved_zone = LAST_ZONE.read_text(encoding='utf-8').strip()
    except Exception:
        pass
    now_zone = current_timezone()
    if saved_zone and valid_timezone(saved_zone) and now_zone in {'UTC', 'Etc/UTC'}:
        set_timezone(saved_zone)

    candidate = max(read_epoch(LAST_GOOD), clock_mtime())
    now = int(time.time())
    if candidate >= MIN_VALID_EPOCH and candidate > now + 2:
        subprocess.run(
            ['/bin/date', '-u', '-s', f'@{candidate}'],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        print(f'NeutronOS time: restored last-known-good UTC epoch {candidate}')
    else:
        print(f'NeutronOS time: no forward restore needed (current={now}, saved={candidate})')
    return 0


def synced() -> bool:
    result = subprocess.run(
        ['/usr/bin/timedatectl', 'show', '-p', 'NTPSynchronized', '--value'],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    return result.stdout.strip().lower() == 'yes'


def capture(timeout: int) -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ['/usr/bin/timedatectl', 'set-ntp', 'true'],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    subprocess.run(
        ['/usr/bin/systemctl', 'restart', 'systemd-timesyncd.service'],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    deadline = time.monotonic() + max(5, timeout)
    while time.monotonic() < deadline:
        if synced():
            epoch = int(time.time())
            if epoch < MIN_VALID_EPOCH:
                raise SystemExit('NTP synchronized but system time failed sanity floor')
            previous = read_epoch(LAST_GOOD)
            if epoch >= previous:
                atomic_epoch(LAST_GOOD, epoch)
            TIMESYNCD_CLOCK.parent.mkdir(parents=True, exist_ok=True)
            TIMESYNCD_CLOCK.touch(exist_ok=True)
            os.utime(TIMESYNCD_CLOCK, (epoch, epoch))

            # First successful network sync also establishes a geographic zone.
            # It runs once; later manual timezone selections remain authoritative.
            if not AUTO_ZONE_DONE.exists():
                zone = detect_network_timezone()
                if zone and set_timezone(zone):
                    atomic_text(AUTO_ZONE_DONE, zone, 0o600)
                    print(f'NeutronOS time: detected network timezone {zone}')
                else:
                    current = current_timezone()
                    if valid_timezone(current) and current not in {'UTC', 'Etc/UTC'}:
                        atomic_text(LAST_ZONE, current, 0o600)
                    print('NeutronOS time: timezone auto-detection deferred')
            else:
                current = current_timezone()
                if valid_timezone(current):
                    atomic_text(LAST_ZONE, current, 0o600)

            subprocess.run(['/bin/sync'], check=False)
            print(f'NeutronOS time: NTP synchronized and persisted epoch {epoch}')
            return 0
        time.sleep(1)
    print('NeutronOS time: network present but NTP did not synchronize before timeout')
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='command', required=True)
    sub.add_parser('restore')
    cap = sub.add_parser('capture')
    cap.add_argument('--timeout', type=int, default=60)
    args = ap.parse_args()
    if args.command == 'restore':
        return restore()
    return capture(args.timeout)


if __name__ == '__main__':
    raise SystemExit(main())
