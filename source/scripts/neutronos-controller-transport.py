#!/usr/bin/env python3
from __future__ import annotations

import fcntl
import json
import os
import re
import select
import signal
import subprocess
import sys
import tempfile
import time
import stat
from contextlib import contextmanager
from pathlib import Path

RUN_DIR = Path('/run/neutronos')
STATE_PATH = RUN_DIR / 'controller-transport.json'
LOCK_PATH = RUN_DIR / 'controller-transport.lock'

SONY_VENDOR = '054c'
KNOWN_PLAYSTATION_PRODUCTS = {
    '05c4',  # DualShock 4 gen 1
    '09cc',  # DualShock 4 gen 2
    '0ba0',  # DualShock 4 wireless adapter / variants
    '0ce6',  # DualSense
    '0df2',  # DualSense Edge
}

POLL_SECONDS = 0.50
MOTION_STALE_SECONDS = 12.0
RECOVERY_COOLDOWN_SECONDS = 30.0

_STOP = False


def log(message: str) -> None:
    print(f'neutronos-controller-transport: {message}', flush=True)


def run(cmd: list[str], timeout: float = 8.0) -> tuple[int, str, str]:
    try:
        proc = subprocess.run(
            cmd,
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, '', str(exc)


def btctl(*args: str, timeout: float = 8.0) -> tuple[int, str, str]:
    return run(['bluetoothctl', *args], timeout=timeout)


def systemctl(*args: str, timeout: float = 12.0) -> tuple[int, str, str]:
    return run(['systemctl', *args], timeout=timeout)


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors='ignore').strip()
    except OSError:
        return ''


def normalize_mac(value: str) -> str:
    value = value.strip().upper()
    if re.fullmatch(r'(?:[0-9A-F]{2}:){5}[0-9A-F]{2}', value):
        return value
    return ''


def paired_devices() -> list[tuple[str, str]]:
    rc, out, _ = btctl('devices', 'Paired')
    if rc != 0:
        rc, out, _ = btctl('devices')
    devices: list[tuple[str, str]] = []
    for line in out.splitlines():
        match = re.match(r'^Device\s+([0-9A-Fa-f:]{17})\s+(.+)$', line.strip())
        if not match:
            continue
        mac = normalize_mac(match.group(1))
        if mac:
            devices.append((mac, match.group(2).strip()))
    return devices


def bluetooth_info(mac: str) -> str:
    _, out, err = btctl('info', mac)
    return out if out else err


def is_playstation_bluetooth(mac: str, fallback_name: str = '') -> bool:
    info = bluetooth_info(mac)
    blob = f'{fallback_name}\n{info}'.lower()
    sony_modalias = bool(re.search(r'modalias:\s*usb:v054c', blob, re.IGNORECASE))
    playstation_name = any(token in blob for token in (
        'dualshock', 'dualsense', 'playstation', 'wireless controller'
    ))
    gaming_icon = 'icon: input-gaming' in blob
    return sony_modalias or (gaming_icon and playstation_name)


def is_connected(mac: str) -> bool:
    return bool(re.search(r'^\s*Connected:\s*yes\s*$', bluetooth_info(mac), re.MULTILINE | re.IGNORECASE))


def playstation_bluetooth_devices(connected_only: bool = False) -> list[str]:
    result: list[str] = []
    for mac, name in paired_devices():
        if not is_playstation_bluetooth(mac, name):
            continue
        if connected_only and not is_connected(mac):
            continue
        result.append(mac)
    return result


def input_nodes_for_mac(mac: str) -> list[Path]:
    wanted = mac.lower()
    result: list[Path] = []
    for event in Path('/sys/class/input').glob('event*'):
        uniq = read_text(event / 'device' / 'uniq').lower()
        if uniq == wanted:
            result.append(event)
    return result


def wait_nodes_gone(mac: str, timeout: float = 4.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not input_nodes_for_mac(mac):
            return True
        time.sleep(0.10)
    return not input_nodes_for_mac(mac)


def wait_gamepad_node(mac: str, timeout: float = 6.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        for event in input_nodes_for_mac(mac):
            name = read_text(event / 'device' / 'name').lower()
            if name and 'motion' not in name and 'touchpad' not in name:
                return True
        time.sleep(0.10)
    return False


def motion_event_for_mac(mac: str) -> str:
    for event in input_nodes_for_mac(mac):
        name = read_text(event / 'device' / 'name').lower()
        if 'motion' in name and 'sensor' in name:
            return f'/dev/input/{event.name}'
    return ''


def clean_reconnect_bluetooth(mac: str, restart_bluez_if_needed: bool = True) -> bool:
    mac = normalize_mac(mac)
    if not mac:
        return False

    log(f'resetting Bluetooth HID session for {mac}')
    btctl('disconnect', mac, timeout=6.0)

    removed = wait_nodes_gone(mac, timeout=4.0)
    if not removed and restart_bluez_if_needed:
        log(f'kernel HID nodes for {mac} survived disconnect; restarting bluetooth.service')
        systemctl('restart', 'bluetooth.service', timeout=15.0)
        wait_nodes_gone(mac, timeout=5.0)
        time.sleep(0.5)

    rc, out, err = btctl('connect', mac, timeout=10.0)
    if rc != 0:
        detail = err or out or f'exit {rc}'
        log(f'Bluetooth reconnect failed for {mac}: {detail}')
        return False

    if wait_gamepad_node(mac, timeout=7.0):
        log(f'Bluetooth HID session healthy for {mac}')
        return True

    log(f'Bluetooth connected but no physical gamepad node appeared for {mac}')
    return False


def usb_playstation_devices() -> list[Path]:
    result: list[Path] = []
    usb_root = Path('/sys/bus/usb/devices')
    if not usb_root.is_dir():
        return result

    for dev in usb_root.iterdir():
        if not dev.is_dir():
            continue
        vendor = read_text(dev / 'idVendor').lower()
        if vendor != SONY_VENDOR:
            continue
        product_id = read_text(dev / 'idProduct').lower()
        product_name = read_text(dev / 'product').lower()
        if product_id in KNOWN_PLAYSTATION_PRODUCTS or any(
            token in product_name for token in ('wireless controller', 'dualsense', 'dualshock')
        ):
            result.append(dev)
    return result


def parse_proc_input_records() -> list[dict[str, str]]:
    try:
        text = Path('/proc/bus/input/devices').read_text(errors='ignore')
    except OSError:
        return []
    records: list[dict[str, str]] = []
    for block in re.split(r'\n\s*\n', text.strip()):
        if not block.strip():
            continue
        rec: dict[str, str] = {'raw': block}
        first = re.search(r'^I:\s+Bus=([0-9A-Fa-f]+)\s+Vendor=([0-9A-Fa-f]+)\s+Product=([0-9A-Fa-f]+)', block, re.MULTILINE)
        if first:
            rec['bus'] = first.group(1).lower()
            rec['vendor'] = first.group(2).lower()
            rec['product'] = first.group(3).lower()
        name = re.search(r'^N:\s+Name="([^"]+)"', block, re.MULTILINE)
        if name:
            rec['name'] = name.group(1)
        uniq = re.search(r'^U:\s+Uniq=(.+)$', block, re.MULTILINE)
        if uniq:
            rec['uniq'] = uniq.group(1).strip()
        handlers = re.search(r'^H:\s+Handlers=(.+)$', block, re.MULTILINE)
        if handlers:
            rec['handlers'] = handlers.group(1).strip()
        records.append(rec)
    return records



def connected_playstation_macs_from_input() -> list[str]:
    result: list[str] = []
    for rec in parse_proc_input_records():
        if rec.get('bus') != '0005' or rec.get('vendor') != SONY_VENDOR:
            continue
        name = rec.get('name', '').lower()
        if 'motion' in name or 'touchpad' in name:
            continue
        mac = normalize_mac(rec.get('uniq', ''))
        if mac and mac not in result:
            result.append(mac)
    return result

def usb_gamepad_present() -> bool:
    for rec in parse_proc_input_records():
        if rec.get('bus') != '0003' or rec.get('vendor') != SONY_VENDOR:
            continue
        name = rec.get('name', '').lower()
        handlers = rec.get('handlers', '')
        if ('js' in handlers and 'event' in handlers) or any(
            token in name for token in ('wireless controller', 'dualsense', 'dualshock')
        ):
            if 'motion' not in name and 'touchpad' not in name:
                return True
    return False


def reauthorize_usb_device(dev: Path) -> bool:
    authorized = dev / 'authorized'
    if not authorized.exists():
        log(f'cannot re-authorize {dev.name}: authorized attribute missing')
        return False
    try:
        authorized.write_text('0')
        time.sleep(0.45)
        authorized.write_text('1')
        log(f're-authorized USB controller at {dev}')
        return True
    except OSError as exc:
        log(f'USB re-authorization failed for {dev}: {exc}')
        return False


def load_state() -> dict:
    try:
        data = json.loads(STATE_PATH.read_text())
        if isinstance(data, dict):
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return {}


def save_state(state: dict) -> None:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.controller-transport.', dir=RUN_DIR)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            handle.write(json.dumps(state, sort_keys=True))
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, STATE_PATH)
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass


@contextmanager
def transport_lock():
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    flags = os.O_RDWR | os.O_CREAT
    if hasattr(os, 'O_NOFOLLOW'):
        flags |= os.O_NOFOLLOW
    fd = os.open(LOCK_PATH, flags, 0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0:
            raise RuntimeError('controller transport lock is not a root-owned regular file')
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def enter_usb_mode(state: dict, usb_devices: list[Path]) -> dict:
    connected = connected_playstation_macs_from_input()
    remembered = [normalize_mac(v) for v in state.get('remembered_macs', []) if normalize_mac(v)]
    for mac in connected:
        if mac not in remembered:
            remembered.append(mac)

    if connected:
        log('USB controller detected; disconnecting duplicate Bluetooth transport')
        for mac in connected:
            btctl('disconnect', mac, timeout=6.0)
            wait_nodes_gone(mac, timeout=3.5)
        time.sleep(0.25)

    if not usb_gamepad_present():
        log('USB controller probe is not bound; forcing clean USB re-probe')
        for dev in usb_devices:
            reauthorize_usb_device(dev)
        deadline = time.monotonic() + 6.0
        while time.monotonic() < deadline and not usb_gamepad_present():
            time.sleep(0.20)

    if usb_gamepad_present():
        log('USB PlayStation controller transport active')
    else:
        log('USB controller is present but hid-playstation has not produced a gamepad node yet')

    state['usb_active'] = True
    state['remembered_macs'] = remembered
    state['last_usb_reprobe'] = time.time()
    save_state(state)
    return state


def leave_usb_mode(state: dict) -> dict:
    remembered = [normalize_mac(v) for v in state.get('remembered_macs', []) if normalize_mac(v)]
    if remembered:
        log('USB controller removed; restoring saved Bluetooth controller')
        for mac in remembered:
            rc, out, err = btctl('connect', mac, timeout=10.0)
            if rc == 0 and wait_gamepad_node(mac, timeout=7.0):
                log(f'Bluetooth controller restored: {mac}')
                break
            detail = err or out or f'exit {rc}'
            log(f'Bluetooth restore failed for {mac}: {detail}')
    state['usb_active'] = False
    state['remembered_macs'] = []
    save_state(state)
    return state


class MotionWatch:
    def __init__(self) -> None:
        self.path = ''
        self.fd: int | None = None
        self.opened_at = 0.0
        self.last_event_at = 0.0

    def close(self) -> None:
        if self.fd is not None:
            try:
                os.close(self.fd)
            except OSError:
                pass
        self.path = ''
        self.fd = None
        self.opened_at = 0.0
        self.last_event_at = 0.0

    def set_path(self, path: str) -> None:
        if path == self.path and self.fd is not None:
            return
        self.close()
        if not path:
            return
        try:
            self.fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError as exc:
            log(f'cannot open motion-health event {path}: {exc}')
            return
        self.path = path
        self.opened_at = time.monotonic()
        self.last_event_at = self.opened_at
        log(f'monitoring Bluetooth HID health through {path}')

    def drain(self) -> bool:
        if self.fd is None:
            return False
        saw = False
        while True:
            try:
                ready, _, _ = select.select([self.fd], [], [], 0)
            except (OSError, ValueError):
                self.close()
                return False
            if not ready:
                break
            try:
                data = os.read(self.fd, 4096)
            except BlockingIOError:
                break
            except OSError:
                self.close()
                return False
            if not data:
                self.close()
                return False
            saw = True
        if saw:
            self.last_event_at = time.monotonic()
        return saw

    def stale(self) -> bool:
        if self.fd is None:
            return False
        return time.monotonic() - self.last_event_at >= MOTION_STALE_SECONDS


def preflight() -> int:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    with transport_lock():
        state = load_state()
        usb = usb_playstation_devices()
        if usb:
            enter_usb_mode(state, usb)
            return 0

        # A shell restart must not inherit a BlueZ session that claims Connected
        # while its UHID input stream is dead. Rebuild only connected PlayStation
        # HID sessions. Paired-but-off controllers are left alone.
        connected = connected_playstation_macs_from_input()
        if not connected:
            # Catch the rarer state where BlueZ says Connected but hid-playstation
            # failed to create input nodes at all. This path runs only at shell
            # startup, not in the daemon hot loop.
            connected = playstation_bluetooth_devices(connected_only=True)
        if not connected:
            log('preflight: no connected PlayStation Bluetooth controller to reset')
            return 0

        for mac in connected:
            clean_reconnect_bluetooth(mac, restart_bluez_if_needed=True)
        return 0


def daemon() -> int:
    global _STOP
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    motion = MotionWatch()
    last_recovery = 0.0

    def stop_handler(_signum, _frame):
        global _STOP
        _STOP = True

    signal.signal(signal.SIGTERM, stop_handler)
    signal.signal(signal.SIGINT, stop_handler)

    log('transport daemon started')

    while not _STOP:
        try:
            with transport_lock():
                state = load_state()
                usb = usb_playstation_devices()

                if usb:
                    motion.close()
                    if not state.get('usb_active'):
                        state = enter_usb_mode(state, usb)
                    elif not usb_gamepad_present():
                        last_reprobe = float(state.get('last_usb_reprobe', 0.0) or 0.0)
                        if time.time() - last_reprobe >= 5.0:
                            state = enter_usb_mode(state, usb)
                else:
                    if state.get('usb_active'):
                        state = leave_usb_mode(state)

                    connected = connected_playstation_macs_from_input()
                    if connected:
                        mac = connected[0]
                        motion.set_path(motion_event_for_mac(mac))
                        motion.drain()

                        # DS4/DualSense motion sensors normally stream continuously.
                        # If BlueZ still says Connected but that stream is silent for
                        # 12 seconds, the UHID session is the same failure mode proven
                        # by the user's isolated raw-input test. Rebuild that single
                        # controller session without restarting NeutronOS.
                        if motion.stale() and time.monotonic() - last_recovery >= RECOVERY_COOLDOWN_SECONDS:
                            log(f'Bluetooth HID stream stale for {mac}; rebuilding session')
                            motion.close()
                            clean_reconnect_bluetooth(mac, restart_bluez_if_needed=True)
                            last_recovery = time.monotonic()
                    else:
                        motion.close()
        except Exception as exc:
            log(f'daemon cycle error: {exc}')

        time.sleep(POLL_SECONDS)

    motion.close()
    log('transport daemon stopped')
    return 0


def status() -> int:
    print(json.dumps({
        'usb_devices': [str(p) for p in usb_playstation_devices()],
        'usb_gamepad_present': usb_gamepad_present(),
        'bluetooth_playstation': playstation_bluetooth_devices(False),
        'bluetooth_connected': playstation_bluetooth_devices(True),
        'state': load_state(),
    }, indent=2, sort_keys=True))
    return 0


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else 'daemon'
    if mode == 'preflight':
        return preflight()
    if mode == 'daemon':
        return daemon()
    if mode == 'status':
        return status()
    print(f'Usage: {sys.argv[0]} [daemon|preflight|status]', file=sys.stderr)
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
