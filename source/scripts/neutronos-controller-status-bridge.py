#!/usr/bin/env python3
"""Verified USB PlayStation-controller registration plus BlueZ bond/reconnect.

Runs unprivileged as echo. A caller cannot select a MAC address: it is read
from the live USB HID device. Only the locally installed NeutronOS QML calls
POST /register; web page cross-origin requests are not authorized.
"""
from __future__ import annotations

import fcntl
import json
import queue
import shutil
import os
import re
import signal
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

HOST, PORT = '127.0.0.1', 48173
SYS_INPUT = Path('/sys/class/input')
STATE_ROOT = Path('/var/lib/neutronos/controller')
STATE_FILE = STATE_ROOT / 'registered-controller.json'
DIAGNOSTIC_FILE = STATE_ROOT / 'registration-diagnostic.log'
BLUETOOTH_RUNTIME_FILE = STATE_ROOT / 'bluetoothctl-runtime.jsonl'
EVENT = re.compile(r'event[0-9]{1,5}\Z')
MAC = re.compile(r'(?:[0-9A-F]{2}:){5}[0-9A-F]{2}\Z')
# Sony USB PID: DS4 v1/v2, DualSense and DualSense Edge.
REPORTS = {'05c4': (0x12, 16), '09cc': (0x12, 16),
           '0ce6': (0x09, 20), '0df2': (0x09, 20)}
BLUEZ_INFO_FLAGS = ('Paired', 'Trusted', 'Connected')
STATE_LOCK = threading.RLock()
DIAGNOSTIC_LOCK = threading.RLock()
DIAGNOSTIC_LINES: list[str] = []
WAKE = threading.Event()
SAVED: dict = {}
PHASE = 'idle'
MESSAGE = 'Connect a supported PlayStation controller via USB, then select Register.'
REGISTRATION_GENERATION = 0
ACTIVE_PAIRING = False
SCAN_TIMEOUT = 100  # seconds; one explicit registration attempt
DISCONNECT_TIMEOUT = 180  # leave enough time to read and follow the prompt


def _clean_diagnostic(value: object) -> str:
    return re.sub(r'[\r\n\x00-\x1f]+', ' ', str(value)).strip()[:400]


def runtime_diagnostic(name: str, value: object) -> None:
    """Append bounded raw process evidence without changing the command path."""
    try:
        BLUETOOTH_RUNTIME_FILE.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(BLUETOOTH_RUNTIME_FILE,
                             os.O_WRONLY | os.O_APPEND | os.O_CREAT |
                             getattr(os, 'O_CLOEXEC', 0), 0o600)
        try:
            os.fchmod(descriptor, 0o600)
            payload = {
                'timestamp_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                'timestamp_ns': time.time_ns(), 'event': name,
                'value': str(value)[-262144:],
            }
            os.write(descriptor, (json.dumps(payload, sort_keys=True,
                                              separators=(',', ':')) + '\n').encode())
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    except OSError as exc:
        print('CONTROLLER_REGISTRATION RUNTIME_DIAGNOSTIC_ERROR=' +
              _clean_diagnostic(exc), flush=True)


def diagnostic_reset() -> None:
    with DIAGNOSTIC_LOCK:
        DIAGNOSTIC_LINES.clear()
        _write_diagnostic_locked()
    try:
        BLUETOOTH_RUNTIME_FILE.unlink()
    except FileNotFoundError:
        pass
    except OSError as exc:
        print('CONTROLLER_REGISTRATION RUNTIME_RESET_ERROR=' +
              _clean_diagnostic(exc), flush=True)


def _write_diagnostic_locked() -> None:
    """Persist the current attempt atomically; journald receives the same lines."""
    try:
        DIAGNOSTIC_FILE.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary = tempfile.mkstemp(prefix='.registration-', dir=DIAGNOSTIC_FILE.parent)
        try:
            os.fchmod(descriptor, 0o600)
            with os.fdopen(descriptor, 'w', encoding='utf-8', closefd=True) as output:
                output.write('\n'.join(DIAGNOSTIC_LINES) + ('\n' if DIAGNOSTIC_LINES else ''))
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, DIAGNOSTIC_FILE)
        finally:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass
    except OSError as exc:
        print('CONTROLLER_REGISTRATION DIAGNOSTIC_WRITE_ERROR=' + _clean_diagnostic(exc), flush=True)


def diagnostic_event(name: str, value: object | None = None) -> None:
    line = name if value is None else name + '=' + _clean_diagnostic(value)
    with DIAGNOSTIC_LOCK:
        DIAGNOSTIC_LINES.append(line)
        _write_diagnostic_locked()
    print('CONTROLLER_REGISTRATION ' + line, flush=True)


def diagnostic_failure(stage: str, error: object, address: str = '') -> None:
    diagnostic_event('FAILED_STAGE', stage)
    diagnostic_event('ERROR', error)
    diagnostic_event('TARGET_MAC', address if valid_mac(address) else 'unavailable')


def read_file(path: Path) -> str:
    try:
        return path.read_text(encoding='ascii').strip()
    except (OSError, UnicodeError):
        return ''


def valid_mac(value: str) -> bool:
    return bool(MAC.fullmatch(value)) and value not in ('00:00:00:00:00:00', 'FF:FF:FF:FF:FF:FF')


def transport_for_event(event: str, sys_input: Path = SYS_INPUT) -> str:
    if not EVENT.fullmatch(event):
        return 'unknown'
    bus = read_file(sys_input / event / 'device/id/bustype').lower()
    return {'0003': 'usb', '0005': 'bluetooth'}.get(bus, 'unknown')


def current_usb_device(event: str, sys_input: Path = SYS_INPUT) -> tuple[Path, str, str]:
    if transport_for_event(event, sys_input) != 'usb':
        raise ValueError('Connect the controller with a USB data cable first.')
    device = (sys_input / event / 'device')
    vendor = read_file(device / 'id/vendor').lower().zfill(4)
    product = read_file(device / 'id/product').lower().zfill(4)
    if vendor != '054c' or product not in REPORTS:
        raise ValueError('USB MAC registration supports Sony DualShock 4 and DualSense controllers; this controller is not supported.')
    # The event path is only used under sysfs, never as an arbitrary file path.
    resolved = device.resolve(strict=True)
    if sys_input == SYS_INPUT and not resolved.is_relative_to(Path('/sys')):
        raise ValueError('Invalid controller sysfs path.')
    return resolved, product, read_file(device / 'name')


def get_hid_parent(input_device: Path) -> Path:
    possible_uniq = None
    for ancestor in (input_device, *input_device.parents):
        if ancestor == Path('/sys') or ancestor == Path('/'):
            break
        if (ancestor / 'hidraw').is_dir():
            return ancestor
        if possible_uniq is None and valid_mac(read_file(ancestor / 'uniq').upper()):
            possible_uniq = ancestor
    if possible_uniq is not None:
        return possible_uniq
    raise ValueError('Cannot locate the USB controller HID device.')


def decode_report_address(report: bytes) -> str:
    if len(report) < 7 or report[0] not in (0x09, 0x12, 0x81):
        raise ValueError('Controller returned an invalid USB pairing report.')
    # hid-playstation stores controller addresses in reverse / little-endian order.
    address = ':'.join(f'{byte:02X}' for byte in report[1:7][::-1])
    if not valid_mac(address):
        raise ValueError('Controller supplied an invalid Bluetooth hardware address.')
    return address


def hid_get_feature(node: Path, report_id: int, size: int) -> bytes:
    # _IOC(READ|WRITE, 'H', 0x07, len) = HIDIOCGFEATURE(len) on Linux.
    hid_iocgfeature = 0xC0004807 | (size << 16)
    packet = bytearray(size)
    packet[0] = report_id
    with open(node, 'rb+', buffering=0) as hid:
        count = fcntl.ioctl(hid.fileno(), hid_iocgfeature, packet, True)
    if isinstance(count, int) and count < 7:
        raise OSError('USB feature response was too short.')
    return bytes(packet)


def usb_identity(event: str, sys_input: Path = SYS_INPUT) -> dict:
    input_device, product, name = current_usb_device(event, sys_input)
    hid = get_hid_parent(input_device)
    report_id, report_size = REPORTS[product]
    candidates = sorted((hid / 'hidraw').glob('hidraw*'))
    errors: list[str] = []
    for entry in candidates:
        node = Path('/dev') / entry.name
        formats = [(report_id, report_size)]
        if product in ('05c4', '09cc'):
            # hid-sony uses DS4 GET_REPORT 0x81; hid-playstation uses 0x12.
            formats.append((0x81, 7))
        for chosen_id, chosen_size in formats:
            try:
                data = hid_get_feature(node, chosen_id, chosen_size)
                if data[0] != chosen_id:
                    raise ValueError('Wrong USB feature report.')
                return {'address': decode_report_address(data), 'name': name or 'PlayStation Controller',
                        'event': event, 'device': str(input_device), 'product': product}
            except (OSError, ValueError) as exc:
                errors.append(str(exc))
    # hid-playstation/hid-sony sometimes publish the actual controller address
    # as HID uniq, even if hidraw permissions are unavailable. Only use the uniq
    # from the HID parent of this confirmed physical Sony USB event.
    uniq = read_file(hid / 'uniq').upper()
    if valid_mac(uniq):
        return {'address': uniq, 'name': name or 'PlayStation Controller',
                'event': event, 'device': str(input_device), 'product': product}
    detail = ('; '.join(errors[:2])) if errors else 'no hidraw node or controller MAC available'
    raise ValueError('Cannot read this USB controller Bluetooth MAC: ' + detail)


def busctl_property(name: str, timeout: float = 5) -> str:
    """Read the real hci0 BlueZ D-Bus properties; never invoke bluetoothctl."""
    if name not in ('Address', 'Powered', 'Discovering'):
        raise ValueError('Unsupported adapter property.')
    response = subprocess.run(
        ['/usr/bin/busctl', '--system', '--timeout=4', 'get-property',
         'org.bluez', '/org/bluez/hci0', 'org.bluez.Adapter1', name],
        capture_output=True, text=True, timeout=timeout, check=False)
    if response.returncode != 0:
        detail = (str(command_error) if command_error else (response.stderr or response.stdout or '')).strip().splitlines()
        raise OSError('BlueZ D-Bus ' + name + ' failed' +
                      (': ' + detail[-1][:125] if detail else ' (no result)'))
    return response.stdout.strip()


def diagnostic_bluez_snapshot(address: str = '') -> str:
    """Read-only BlueZ state captured around the unchanged bluetoothctl run."""
    values = {}
    for name in ('Address', 'Powered', 'Discovering', 'Pairable'):
        try:
            values['adapter_' + name.lower()] = busctl_property(name) if name != 'Pairable' else subprocess.run(
                ['/usr/bin/busctl', '--system', '--timeout=4', 'get-property',
                 'org.bluez', '/org/bluez/hci0', 'org.bluez.Adapter1', name],
                capture_output=True, text=True, timeout=5, check=False).stdout.strip()
        except (OSError, subprocess.TimeoutExpired) as exc:
            values['adapter_' + name.lower()] = 'ERROR ' + repr(exc)
    if valid_mac(address):
        device_path = '/org/bluez/hci0/dev_' + address.replace(':', '_')
        values['target_path'] = device_path
        for name in ('Paired', 'Trusted', 'Connected'):
            try:
                result = subprocess.run(
                    ['/usr/bin/busctl', '--system', '--timeout=4', 'get-property',
                     'org.bluez', device_path, 'org.bluez.Device1', name],
                    capture_output=True, text=True, timeout=5, check=False)
                values['target_' + name.lower()] = {
                    'returncode': result.returncode,
                    'stdout': result.stdout.strip(), 'stderr': result.stderr.strip()}
            except (OSError, subprocess.TimeoutExpired) as exc:
                values['target_' + name.lower()] = {'error': repr(exc)}
    return json.dumps(values, sort_keys=True, separators=(',', ':'))


def diagnostic_command(argv: list[str], timeout: float = 10) -> str:
    """Capture bounded post-failure runtime evidence; never influence success."""
    try:
        response = subprocess.run(argv, stdin=subprocess.DEVNULL,
                                  capture_output=True, text=True,
                                  timeout=timeout, check=False)
        return json.dumps({
            'argv': argv, 'returncode': response.returncode,
            'stdout': response.stdout[-131072:],
            'stderr': response.stderr[-131072:],
        }, sort_keys=True, separators=(',', ':'))
    except (OSError, subprocess.TimeoutExpired) as exc:
        return json.dumps({'argv': argv, 'capture_error': repr(exc)},
                          sort_keys=True, separators=(',', ':'))


def adapter_state() -> tuple[str, bool]:
    """Return actual hci0 address and power without the crashing bluetoothctl."""
    try:
        raw = busctl_property('Address')
        match = re.fullmatch(r's\s+"((?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})"', raw)
        if not match or not valid_mac(match.group(1).upper()):
            return '', False
        powered = busctl_property('Powered')
        if powered not in ('b true', 'b false'):
            return '', False
        return match.group(1).upper(), powered == 'b true'
    except (OSError, subprocess.TimeoutExpired):
        return '', False


def adapter_discovering() -> bool:
    try:
        return busctl_property('Discovering', timeout=3) == 'b true'
    except (OSError, subprocess.TimeoutExpired):
        return False


def power_adapter_via_dbus() -> None:
    """Use verified BlueZ Adapter1.Set; unlike bluetoothctl this does not crash."""
    response = subprocess.run(
        ['/usr/bin/busctl', '--system', '--timeout=8', 'set-property',
         'org.bluez', '/org/bluez/hci0', 'org.bluez.Adapter1',
         'Powered', 'b', 'true'], capture_output=True, text=True,
        timeout=10, check=False)
    if response.returncode:
        detail = (str(command_error) if command_error else (response.stderr or response.stdout or '')).strip().splitlines()
        raise ValueError('BlueZ D-Bus refused Bluetooth power on' +
                         (': ' + detail[-1][:125] if detail else '.'))

def local_adapter_address() -> str:
    """Return a real, powered BlueZ adapter address, never a guessed identity."""
    address, powered = adapter_state()
    return address if powered else ''


def bluetooth_rfkill_status() -> tuple[bool, bool]:
    """Read only kernel rfkill indicators for Bluetooth radios."""
    soft, hard = False, False
    for entry in Path('/sys/class/rfkill').glob('rfkill*'):
        if read_file(entry / 'type').lower() != 'bluetooth':
            continue
        soft |= read_file(entry / 'soft') == '1'
        hard |= read_file(entry / 'hard') == '1'
    return soft, hard


def ensure_adapter_powered() -> str:
    """Check rfkill first, then use BlueZ D-Bus to power and verify hci0.

    This bridge runs with NoNewPrivileges=true.  Adapter preparation therefore
    stays inside the already-authorized BlueZ D-Bus path; trying to invoke sudo
    here can never elevate and used to abort registration before the USB MAC was
    persisted.
    """
    soft, hard = bluetooth_rfkill_status()
    if hard:
        raise ValueError('Bluetooth hardware rfkill block detected. A hardware block cannot be cleared in software.')
    if soft:
        raise ValueError('Bluetooth is software-blocked. The NeutronOS Bluetooth startup unit must unblock it; check its status.')
    address, powered = adapter_state()
    if not address:
        if Path('/sys/class/bluetooth/hci0').exists():
            raise ValueError('hci0 exists, but BlueZ D-Bus cannot read its adapter properties. Check bluetooth.service and D-Bus permissions.')
        raise ValueError('Bluetooth hci0 hardware is missing from sysfs.')
    if powered:
        return address
    try:
        power_adapter_via_dbus()
    except (OSError, subprocess.TimeoutExpired, ValueError) as exc:
        raise ValueError('Unable to power Bluetooth through BlueZ D-Bus: ' + str(exc)[:155]) from exc
    for _ in range(12):
        found, ready = adapter_state()
        if found == address and ready and not any(bluetooth_rfkill_status()):
            return address
        time.sleep(0.35)
    raise ValueError('Bluetooth D-Bus power request did not verify Powered=true for the original hci0 adapter.')

def bluez_command(*args: str, timeout: int = 7, agent: bool = False) -> subprocess.CompletedProcess:
    argv = ['/usr/bin/bluetoothctl']
    if agent:
        argv.extend(['--agent', 'NoInputNoOutput'])
    argv.extend(['--timeout', str(timeout), *args])
    return subprocess.run(argv,
                          capture_output=True, text=True, timeout=timeout + 3, check=False)


def bluetooth_info(address: str) -> dict:
    result = {'address': address, 'known': False, 'paired': False,
              'trusted': False, 'connected': False}
    if not valid_mac(address):
        return result
    try:
        response = bluez_command('info', address, timeout=3)
        if response.returncode != 0:
            return result
        output = response.stdout
        if re.search(r'Device\s+[^\n]+\s+not available', output, re.I):
            return result
        if not re.search(r'^\s*(?:Paired|Name|Alias):', output, re.M):
            return result
        result['known'] = True
        for flag in BLUEZ_INFO_FLAGS:
            result[flag.lower()] = bool(re.search(r'^\s*' + flag + r':\s*yes\s*$', output, re.I | re.M))
    except (OSError, subprocess.TimeoutExpired):
        pass
    return result


def publish(phase: str, message: str) -> None:
    global PHASE, MESSAGE
    with STATE_LOCK:
        PHASE, MESSAGE = phase, message


def persist_controller(identity: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    content = json.dumps({key: identity[key] for key in
                          ('address', 'name', 'event', 'device', 'product', 'host_associated')},
                         separators=(',', ':')).encode('utf-8')
    fd, tmp = tempfile.mkstemp(prefix='.controller-', dir=STATE_FILE.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'wb') as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.replace(tmp, STATE_FILE)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def load_registered() -> dict:
    try:
        record = json.loads(STATE_FILE.read_text(encoding='utf-8'))
    except (OSError, ValueError, TypeError):
        return {}
    if not isinstance(record, dict) or not valid_mac(str(record.get('address', ''))):
        return {}
    if not EVENT.fullmatch(str(record.get('event', ''))):
        record['event'] = ''
    return record


def usb_still_connected(record: dict) -> bool:
    if not record:
        return False
    event = str(record.get('event', ''))
    if not EVENT.fullmatch(event) or transport_for_event(event) != 'usb':
        return False
    try:
        device, product, _ = current_usb_device(event)
        return str(device) == record.get('device') and product == record.get('product')
    except (OSError, ValueError):
        return False


def attention_for_usb_event(event: str) -> bool:
    """A supported, present USB pad needs attention until its own bond is confirmed.

    Never infer registration from a shared product ID or a reused event path:
    compare its actual HID Bluetooth address with the saved controller.
    """
    try:
        current_usb_device(event)
    except (OSError, ValueError):
        return False
    with STATE_LOCK:
        registered = dict(SAVED)
    if not registered:
        return True
    try:
        device = usb_identity(event)
    except (OSError, ValueError):
        return True  # Cannot verify identity. Do not claim that it is bonded.
    if device['address'] != registered.get('address'):
        return True
    status = bluetooth_info(device['address'])
    return not (status['paired'] and status['trusted'])


def registration_status() -> dict:
    with STATE_LOCK:
        record = dict(SAVED)
        phase, message = PHASE, MESSAGE
    address = record.get('address', '')
    bt = bluetooth_info(address) if address else {'paired': False, 'trusted': False, 'connected': False}
    usb = usb_still_connected(record)
    # Actual BlueZ state is authoritative. Saving an address is not a bond.
    if address and not usb and bt['paired'] and bt['trusted'] and bt['connected']:
        phase = 'connected'
        message = 'Registration complete: Bluetooth paired, trusted and connected. Press PS for future reconnections.'
    return {'bridge_version': '9.0', 'address': address, 'name': record.get('name', ''),
            'phase': phase, 'message': message, 'paired': bt['paired'],
            'trusted': bt['trusted'], 'connected': bt['connected'],
            'usb_present': usb, 'host_associated': False}


def cancel_registration() -> dict:
    """Cancel one in-progress attempt without erasing a verified bond."""
    global SAVED, REGISTRATION_GENERATION
    with STATE_LOCK:
        record = dict(SAVED)
    address = str(record.get('address', ''))
    status = bluetooth_info(address) if valid_mac(address) else {}
    verified = bool(status.get('paired') and status.get('trusted'))
    with STATE_LOCK:
        REGISTRATION_GENERATION += 1
        if not verified:
            SAVED = {}
            try:
                STATE_FILE.unlink()
            except FileNotFoundError:
                pass
        publish('connected' if verified else 'idle',
                'Verified controller bond preserved.' if verified else
                'Registration cancelled. Reconnect USB and select Register to retry.')
    WAKE.set()
    return registration_status()


def register_usb(event: str) -> dict:
    """Stage only the verified USB identity; scan is armed, not started yet."""
    global SAVED, REGISTRATION_GENERATION
    diagnostic_reset()
    try:
        identity = usb_identity(event)  # no caller-supplied MAC accepted
    except (OSError, ValueError) as exc:
        diagnostic_failure('USB_CONTROLLER_IDENTIFIED', exc)
        raise
    diagnostic_event('USB_CONTROLLER_IDENTIFIED')
    diagnostic_event('MAC_CAPTURED', identity['address'])
    diagnostic_event('REGISTRATION_STARTED')
    identity['host_associated'] = False
    if not usb_still_connected(identity):
        error = 'USB controller disconnected during registration. Reconnect and press Register again.'
        diagnostic_failure('USB_CONNECTION_VERIFIED', error, identity['address'])
        raise ValueError(error)
    # Power on BEFORE persisting/prompting; never tell the user to unplug if
    # this bridge cannot make the adapter ready for Bluetooth discovery.
    publish('powering_adapter', 'Checking Bluetooth adapter and enabling it if necessary…')
    try:
        ensure_adapter_powered()
    except ValueError as exc:
        publish('error', str(exc))
        diagnostic_failure('ADAPTER_READY', exc, identity['address'])
        raise
    if not usb_still_connected(identity):
        error = 'USB controller disconnected while enabling Bluetooth. Reconnect and retry Register.'
        publish('error', error)
        diagnostic_failure('USB_CONNECTION_VERIFIED', error, identity['address'])
        raise ValueError(error)
    with STATE_LOCK:
        try:
            persist_controller(identity)
        except OSError as exc:
            diagnostic_failure('STATE_PERSIST', exc, identity['address'])
            raise
        SAVED = identity
        REGISTRATION_GENERATION += 1
        publish('waiting_disconnect',
                'MAC saved. Unplug this controller, then hold SHARE + PS (DualShock 4) or Create + PS (DualSense) until its light flashes. Discovery starts automatically on USB disconnect.')
    WAKE.set()
    return registration_status()


def generation_matches(generation: int) -> bool:
    with STATE_LOCK:
        return generation == REGISTRATION_GENERATION


def wait_for_unplug(record: dict, generation: int, timeout: float = DISCONNECT_TIMEOUT,
                    poll: float = 0.4) -> bool:
    """Track the registered USB input device, never a generic connected flag."""
    end = time.monotonic() + timeout
    while generation_matches(generation) and time.monotonic() < end:
        if not usb_still_connected(record):
            diagnostic_event('USB_DISCONNECTED')
            return True
        time.sleep(poll)
    if generation_matches(generation):
        error = 'Timed out waiting for this USB controller to unplug. Reconnect USB and press Register again.'
        publish('error', error)
        diagnostic_failure('USB_DISCONNECTED', error, str(record.get('address', '')))
    return False


def run_bluez_verified(address: str, verb: str, timeout: float, diagnose: bool = False) -> bool:
    """Poll authoritative BlueZ properties; CLI exit status alone is insufficient."""
    flag = {'pair': 'paired', 'trust': 'trusted', 'connect': 'connected'}[verb]
    stage = verb.upper()
    if diagnose:
        diagnostic_event(stage + '_REQUESTED')
    if bluetooth_info(address)[flag]:
        if diagnose:
            diagnostic_event(stage + '_RESULT', 'success (already verified)')
        return True
    response = None
    command_error = None
    try:
        # Noninteractive pairing uses an explicit agent; existing bonds are NEVER paired again.
        response = bluez_command(verb, address, timeout=int(timeout), agent=(verb == 'pair'))
    except (OSError, subprocess.TimeoutExpired) as exc:
        # A CLI timeout is not proof that BlueZ rejected the operation. Reconcile
        # the exact registered MAC through Device1 before publishing failure.
        command_error = exc
    # bluetoothctl can exit or time out before BlueZ property changes arrive.
    for _ in range(10):
        if bluetooth_info(address)[flag]:
            if diagnose:
                diagnostic_event(stage + '_RESULT', 'success')
            return True
        time.sleep(0.3)
    detail = (str(command_error) if command_error else (response.stderr or response.stdout or '')).strip().splitlines()
    publish('error', 'Bluetooth ' + verb + ' did not verify' +
            (': ' + detail[-1][:125] if detail else '. Check the controller is still in pairing mode.'))
    if diagnose:
        error = detail[-1][:200] if detail else 'BlueZ property did not become ' + flag
        diagnostic_event(stage + '_RESULT', 'failed')
        diagnostic_failure(stage, error, address)
    return False


class ScanSession:
    """Existing bluetoothctl session with temporary evidence capture only."""
    def __init__(self, address: str = ''):
        self.address = address
        self.process = None
        self.lines: queue.Queue = queue.Queue(maxsize=256)
        self.reader = None
        self.recent: list[str] = []
        self.all_output: list[str] = []
        self.exit_recorded = False
        self.start_recorded = False
        self.commands: list[str] = []
        self.before_snapshot = ''

    def __enter__(self):
        argv = ['/usr/bin/bluetoothctl', '--agent', 'NoInputNoOutput']
        # Take the requested adapter snapshot, but defer persistent writes until
        # after the unchanged client launch/command sequence to minimize timing
        # effects on the failing discovery path.
        self.before_snapshot = diagnostic_bluez_snapshot()
        # Invocation, inherited environment and merged stdout/stderr are unchanged.
        self.process = subprocess.Popen(
            argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1)
        def read_output():
            for line in self.process.stdout:
                self.all_output.append(line)
                if sum(map(len, self.all_output)) > 262144:
                    self.all_output = self.all_output[-128:]
                clean = _clean_diagnostic(line)
                if clean:
                    self.recent.append(clean)
                    del self.recent[:-40]
                try:
                    self.lines.put_nowait(line)
                except queue.Full:
                    try:
                        self.lines.get_nowait()
                        self.lines.put_nowait(line)
                    except queue.Empty:
                        pass
        self.reader = threading.Thread(target=read_output,
                                       name='bluetooth-discovery-output', daemon=True)
        self.reader.start()
        self.send('agent NoInputNoOutput')
        self.send('default-agent')
        self.send('pairable on')
        self.send('scan on')
        self._record_start()
        return self

    def send(self, command: str):
        self.commands.append(command)
        if not self.process or self.process.poll() is not None:
            self._record_start()
            self._record_exit()
            raise OSError('bluetoothctl exited while starting discovery: ' + self.last_result())
        self.process.stdin.write(command + '\n')
        self.process.stdin.flush()

    def _record_start(self):
        if self.start_recorded or self.process is None:
            return
        self.start_recorded = True
        diagnostic_event('BLUETOOTHCTL_PID', self.process.pid)
        runtime_diagnostic('BLUETOOTHCTL_COMMAND', json.dumps(
            ['/usr/bin/bluetoothctl', '--agent', 'NoInputNoOutput']))
        runtime_diagnostic('BLUEZ_BEFORE', self.before_snapshot)
        runtime_diagnostic('BLUETOOTHCTL_PID', self.process.pid)
        runtime_diagnostic('BLUETOOTHCTL_STDIN_SEQUENCE', json.dumps(self.commands))
        runtime_diagnostic('BLUETOOTHCTL_ENVIRONMENT',
                           json.dumps(dict(sorted(os.environ.items())), sort_keys=True))
        try:
            runtime_diagnostic('BLUETOOTHCTL_PROC_STATUS',
                               Path(f'/proc/{self.process.pid}/status').read_text(errors='replace'))
            runtime_diagnostic('BLUETOOTHCTL_PROC_MAPS',
                               Path(f'/proc/{self.process.pid}/maps').read_text(errors='replace'))
        except OSError as exc:
            runtime_diagnostic('BLUETOOTHCTL_PROC_CAPTURE_ERROR', repr(exc))

    def _record_exit(self):
        if self.exit_recorded or self.process is None:
            return
        self._record_start()
        status = self.process.poll()
        if status is None:
            return
        self.exit_recorded = True
        signal_number = -status if status < 0 else 0
        signal_name = ''
        if signal_number:
            try:
                signal_name = signal.Signals(signal_number).name
            except ValueError:
                signal_name = 'UNKNOWN'
        diagnostic_event('BLUETOOTHCTL_EXIT_CODE', status)
        diagnostic_event('BLUETOOTHCTL_TERMINATING_SIGNAL',
                         f'{signal_number} {signal_name}' if signal_number else 'none')
        runtime_diagnostic('BLUETOOTHCTL_RESULT', json.dumps({
            'returncode': status, 'exit_code': status if status >= 0 else None,
            'terminating_signal': signal_number or None, 'signal_name': signal_name,
        }, sort_keys=True))
        runtime_diagnostic('BLUETOOTHCTL_STDOUT_STDERR_COMBINED', ''.join(self.all_output))
        runtime_diagnostic('BLUEZ_AFTER', diagnostic_bluez_snapshot(self.address))
        runtime_diagnostic('BLUETOOTH_SERVICE_AFTER', diagnostic_command([
            '/usr/bin/systemctl', 'show', 'bluetooth.service',
            '-p', 'ActiveState', '-p', 'SubState', '-p', 'Result',
            '-p', 'ExecMainCode', '-p', 'ExecMainStatus', '-p', 'MainPID']))
        runtime_diagnostic('BLUETOOTH_JOURNAL_AFTER', diagnostic_command([
            '/usr/bin/journalctl', '-b', '-u', 'bluetooth.service', '--no-pager',
            '--output=short-precise', '-n', '300'], timeout=15))
        runtime_diagnostic('KERNEL_JOURNAL_AFTER', diagnostic_command([
            '/usr/bin/journalctl', '-b', '-k', '--no-pager',
            '--output=short-precise', '-n', '500'], timeout=15))
        runtime_diagnostic('MEMINFO_AFTER', read_file(Path('/proc/meminfo')))

    def last_result(self) -> str:
        status = self.process.poll() if self.process is not None else None
        if status is not None:
            self._record_exit()
        detail = self.recent[-1] if self.recent else 'no BlueZ response'
        return f'exit={status}: {detail}' if status is not None else detail

    def __exit__(self, *_):
        if self.process is None:
            return
        if self.process.poll() is None:
            try:
                self.send('scan off')
                self.send('quit')
                self.process.stdin.close()
                self.process.wait(timeout=3)
            except (OSError, ValueError, subprocess.TimeoutExpired):
                self.process.terminate()
                try:
                    self.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=3)
        if self.reader:
            self.reader.join(timeout=0.5)
        self._record_exit()
        if self.process.stdout:
            self.process.stdout.close()

def scanned_exact_mac(line: str, address: str) -> bool:
    """Only [NEW]/[CHG] device observations from the live discovery stream count."""
    clean = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', line)
    pattern = r'\[(?:NEW|CHG)\]\s+Device\s+' + re.escape(address) + r'(?=\s|$)'
    return bool(re.search(pattern, clean, re.I))


def bond_trust_connect(address: str, generation: int, scanner: ScanSession) -> bool:
    """Restore v9: pair through the same live discovery session and agent."""
    if not generation_matches(generation):
        return False
    info = bluetooth_info(address)
    diagnostic_event('PAIR_REQUESTED')
    if not info['paired']:
        publish('bonding', 'Exact registered controller discovered. Creating the first Bluetooth bond…')
        try:
            scanner.send('pair ' + address)
        except OSError as exc:
            diagnostic_event('PAIR_RESULT', 'failed')
            diagnostic_failure('PAIR', exc, address)
            publish('error', 'BlueZ pairing client exited before the bond could be requested.')
            return False
        end = time.monotonic() + 32
        while generation_matches(generation) and time.monotonic() < end:
            if bluetooth_info(address)['paired']:
                break
            if scanner.process.poll() is not None:
                break
            time.sleep(0.4)
        if not bluetooth_info(address)['paired']:
            diagnostic_event('PAIR_RESULT', 'failed')
            diagnostic_failure('PAIR', 'BlueZ Device1.Paired did not become true; ' + scanner.last_result(), address)
            publish('error', 'Exact controller appeared, but BlueZ did not confirm pairing. Keep SHARE + PS / Create + PS held until flashing and retry Register.')
            return False
        diagnostic_event('PAIR_RESULT', 'success')
    else:
        diagnostic_event('PAIR_RESULT', 'success (already verified)')
    if not generation_matches(generation):
        return False
    publish('trusting', 'Bluetooth bond confirmed. Trusting the saved controller…')
    if not run_bluez_verified(address, 'trust', 8, diagnose=True):
        return False
    publish('connecting', 'Bluetooth bond and trust confirmed. Connecting…')
    if not run_bluez_verified(address, 'connect', 14, diagnose=True):
        return False
    verified = bluetooth_info(address)
    if not verified['connected']:
        diagnostic_failure('CONNECTED_VERIFIED', 'BlueZ Connected property is false after connect', address)
        publish('error', 'Controller connection was not verified by BlueZ; retry registration.')
        return False
    diagnostic_event('CONNECTED_VERIFIED')
    if not (verified['paired'] and verified['trusted']):
        diagnostic_failure('BONDED_VERIFIED', 'BlueZ Paired/Trusted properties are not both true', address)
        publish('error', 'Controller bond was not fully verified by BlueZ; retry registration.')
        return False
    diagnostic_event('BONDED_VERIFIED')
    publish('connected', 'Registration complete: Bluetooth paired, trusted and connected. Press PS for future reconnections.')
    diagnostic_event('SUCCESS')
    return True

def scan_pair_exact(address: str, generation: int, timeout: float = SCAN_TIMEOUT) -> bool:
    """Start scanning ONLY after unplug; accept no unrelated or cached devices."""
    if not generation_matches(generation):
        return False
    # Another settings action may have powered Bluetooth off while USB was
    # still connected. Re-enable it before beginning the post-unplug scan.
    publish('powering_adapter', 'USB disconnect detected. Ensuring Bluetooth is powered before scanning…')
    try:
        ensure_adapter_powered()
    except ValueError as exc:
        publish('error', str(exc))
        diagnostic_failure('ADAPTER_READY_AFTER_USB_DISCONNECT', exc, address)
        return False
    publish('scanning', 'USB disconnect detected. Scanning for your saved MAC only. Hold SHARE + PS / Create + PS until the light flashes.')
    try:
        with ScanSession(address) as scanner:
            diagnostic_event('DISCOVERY_STARTED')
            end = time.monotonic() + timeout
            while time.monotonic() < end and generation_matches(generation):
                if scanner.process.poll() is not None:
                    error = 'Bluetooth discovery exited: ' + scanner.last_result()
                    publish('error', 'Bluetooth discovery exited. Check that the Bluetooth adapter is powered and usable.')
                    diagnostic_failure('DISCOVERY_STARTED', error, address)
                    return False
                try:
                    line = scanner.lines.get(timeout=0.5)
                except queue.Empty:
                    continue
                if scanned_exact_mac(line, address):
                    diagnostic_event('TARGET_SEEN', address)
                    return bond_trust_connect(address, generation, scanner)
    except (OSError, subprocess.TimeoutExpired) as exc:
        publish('error', 'Bluetooth scan failed: ' + str(exc)[:145])
        diagnostic_failure('DISCOVERY_STARTED', exc, address)
        return False
    if generation_matches(generation):
        error = 'Scan timed out: saved controller MAC was not seen.'
        publish('error', error + ' Reconnect USB, press Register, then enter pairing mode after unplugging.')
        diagnostic_failure('TARGET_SEEN', error, address)
    return False


def reconnect_bond(address: str) -> bool:
    """For later PS presses, connect existing bond without destroying it."""
    info = bluetooth_info(address)
    if not info['paired']:
        return False
    if not info['trusted'] and not run_bluez_verified(address, 'trust', 8):
        return False
    if bluetooth_info(address)['connected']:
        return True
    return run_bluez_verified(address, 'connect', 10)


def auto_connect_loop() -> None:
    """Explicit registration is a staged transaction; later bonded reconnection is separate."""
    active_generation = -1
    while True:
        WAKE.wait(timeout=5)
        WAKE.clear()
        with STATE_LOCK:
            record = dict(SAVED)
            generation = REGISTRATION_GENERATION
            phase = PHASE
        if not record:
            continue
        address = record['address']
        try:
            if generation != active_generation and phase == 'waiting_disconnect':
                active_generation = generation
                if not wait_for_unplug(record, generation):
                    continue
                if not generation_matches(generation):
                    continue
                if scan_pair_exact(address, generation):
                    continue
                continue
            if usb_still_connected(record):
                continue
            bt = bluetooth_info(address)
            if bt['paired'] and bt['trusted'] and bt['connected']:
                if phase != 'connected':
                    publish('connected', 'Bluetooth connection verified. Press PS to reconnect next time.')
                continue
            if bt['paired'] and phase != 'waiting_disconnect':
                reconnect_bond(address)
        except Exception as exc:
            publish('error', 'Controller registration failed: ' + str(exc)[:160])
            diagnostic_failure('UNHANDLED', exc, address)


class Handler(BaseHTTPRequestHandler):
    server_version = 'NeutronControllerRegistration/9.0'

    def json_response(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, separators=(',', ':')).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == '/live':
            # Lightweight real transport: never wait for ControllerManager's
            # delayed update or run the registration/scan state machine.
            with STATE_LOCK:
                record = dict(SAVED)
            usb = usb_still_connected(record)
            address = str(record.get('address', ''))
            # USB input event numbers may change after a reconnect. Verify a
            # fresh Sony USB event against the saved Bluetooth identity instead
            # of assuming the old event number still refers to this controller.
            if not usb and valid_mac(address):
                for entry in SYS_INPUT.glob('event*'):
                    event = entry.name
                    if not EVENT.fullmatch(event):
                        continue
                    if transport_for_event(event) != 'usb':
                        continue
                    device = entry / 'device'
                    if read_file(device / 'id/vendor').lower().zfill(4) != '054c':
                        continue
                    if read_file(device / 'id/product').lower().zfill(4) not in REPORTS:
                        continue
                    try:
                        if usb_identity(event)['address'] == address:
                            usb = True
                            break
                    except (OSError, ValueError):
                        continue
            bt_connected = False
            if valid_mac(address) and not usb:
                # A live BlueZ Device1 property, not battery charging status.
                object_path = '/org/bluez/hci0/dev_' + address.replace(':', '_')
                try:
                    query = subprocess.run(
                        ['/usr/bin/busctl', '--system', '--timeout=2',
                         'get-property', 'org.bluez', object_path,
                         'org.bluez.Device1', 'Connected'],
                        capture_output=True, text=True, timeout=2.5, check=False)
                    bt_connected = query.returncode == 0 and query.stdout.strip() == 'b true'
                except (OSError, subprocess.TimeoutExpired):
                    pass
            info = bluetooth_info(address) if valid_mac(address) else {}
            registered = bool(info.get('paired') and info.get('trusted'))
            self.json_response(200, {'registered': registered,
                                     'transport': 'usb' if usb else 'bluetooth' if bt_connected else 'offline',
                                     'connected': usb or bt_connected})
            return
        if url.path == '/registration':
            self.json_response(200, registration_status())
            return
        if url.path != '/status':
            self.send_error(404)
            return
        event = parse_qs(url.query).get('device', [''])[0]
        if len(event) > 12:
            self.send_error(400)
            return
        transport = transport_for_event(event)
        self.json_response(200, {'transport': transport,
                                 'device': event if EVENT.fullmatch(event) else '',
                                 'devices': [],
                                 'registration_needed': attention_for_usb_event(event) if transport == 'usb' else False})

    def do_POST(self):
        request_path = urlsplit(self.path).path
        if request_path not in ('/register', '/cancel'):
            self.send_error(404)
            return
        # Prevent simple web-form CSRF; web XHR custom headers require a blocked
        # CORS preflight. A MAC supplied by the request is NEVER accepted.
        if self.headers.get('X-Neutron-Controller') != 'register-usb-v1':
            self.send_error(403)
            return
        origin = self.headers.get('Origin', '')
        if origin not in ('', 'null'):
            self.send_error(403)
            return
        if self.headers.get('Content-Type', '').split(';')[0].strip() != 'application/json':
            self.send_error(415)
            return
        try:
            declared_size = int(self.headers.get('Content-Length', '0'))
            if not 1 <= declared_size <= 128:
                raise ValueError('Invalid JSON body length.')
        except ValueError:
            self.send_error(400)
            return
        try:
            data = json.loads(self.rfile.read(declared_size))
            if request_path == '/cancel':
                if not isinstance(data, dict) or data:
                    raise ValueError('Invalid cancellation request.')
                payload = cancel_registration()
            else:
                if not isinstance(data, dict) or set(data) != {'event'}:
                    raise ValueError('Invalid registration request.')
                event = data['event']
                if not isinstance(event, str) or not EVENT.fullmatch(event):
                    raise ValueError('Invalid controller event.')
                payload = register_usb(event)
            self.json_response(200, payload)
        except (ValueError, OSError, UnicodeError, TypeError) as exc:
            self.json_response(409, {'error': str(exc)[:240]})

    def do_OPTIONS(self):
        self.send_error(405)

    def log_message(self, format, *args):
        return  # no MAC addresses in query strings or journals


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == '__main__':
    with STATE_LOCK:
        SAVED = load_registered()
        if SAVED:
            PHASE = 'idle'
            MESSAGE = 'Saved USB controller loaded. Reconnect USB and press Register to begin pairing, or press PS if already bonded.'
    threading.Thread(target=auto_connect_loop, name='controller-reconnect', daemon=True).start()
    Server((HOST, PORT), Handler).serve_forever(poll_interval=0.5)
