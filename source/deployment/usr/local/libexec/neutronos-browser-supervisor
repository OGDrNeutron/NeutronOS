#!/usr/bin/env python3
"""Trusted root supervisor for the isolated NeutronOS Browser VT."""
from __future__ import annotations

import json
import os
import pwd
import re
import stat
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path('/opt/neutronos')
RUN_USER = 'neutronos'
RUNTIME_ROOT = Path('/var/lib/neutronos/apps/browser-runtime')
EXPECTED_SPEC = RUNTIME_ROOT / 'launch.json'
STATUS_PATH = RUNTIME_ROOT / 'status.json'
RETURN_PATH = RUNTIME_ROOT / 'return-session.json'
LOG_PATH = RUNTIME_ROOT / 'last-runtime.log'
EXIT_PATH = RUNTIME_ROOT / 'last-exit-code'
RUNTIME_HELPER = Path('/usr/local/libexec/neutronos-browser-runtime')
BROWSER_EXECUTABLE = Path('/usr/local/bin/NeutronBrowser')
SESSION_PATTERN = re.compile(r'^[0-9]{10,20}-[0-9]{1,10}$')

ACCOUNT = pwd.getpwnam(RUN_USER)
RUN_UID = ACCOUNT.pw_uid
RUN_GID = ACCOUNT.pw_gid


def trusted_root_executable(path: Path) -> bool:
    try:
        info = path.lstat()
    except OSError:
        return False
    return (stat.S_ISREG(info.st_mode) and not stat.S_ISLNK(info.st_mode)
            and info.st_uid == 0 and not (info.st_mode & 0o022)
            and os.access(path, os.X_OK))


def verified_human(username: str, home: str) -> pwd.struct_passwd:
    if not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', username):
        raise ValueError('invalid human identity')
    human = pwd.getpwnam(username)
    expected = Path('/NeutronOS') / username
    if (human.pw_uid < 1000 or human.pw_dir != str(expected) or home != str(expected) or
            human.pw_shell.endswith(('nologin', 'false')) or not os.path.ismount('/NeutronOS') or
            expected.is_symlink() or not expected.is_dir()):
        raise ValueError('human DATA identity is invalid')
    shell_pid = subprocess.run(['/usr/bin/systemctl', 'show', 'neutronos.service', '-p', 'MainPID', '--value'],
                               capture_output=True, text=True, timeout=4, check=True).stdout.strip()
    if not shell_pid.isdigit() or int(shell_pid) < 2:
        raise ValueError('authenticated shell is unavailable')
    if os.readlink('/proc/' + shell_pid + '/exe') != '/opt/neutronos/build/NeutronShell':
        raise ValueError('unexpected shell executable')
    # The authoritative shell authenticates the selected human in process.
    # Trust its service-owned request only while the expected binary is MainPID.
    if os.stat('/proc/' + shell_pid).st_uid != pwd.getpwnam('neutronos').pw_uid:
        raise ValueError('unexpected shell peer identity')
    groups = Path('/proc/' + shell_pid + '/cgroup').read_text()
    if '/system.slice/neutronos.service' not in groups:
        raise ValueError('unexpected shell service ancestry')
    return human


def validate_spec(path: Path) -> dict[str, Any]:
    if path != EXPECTED_SPEC:
        raise ValueError('unexpected launch specification path')
    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, 'O_NOFOLLOW'):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    with os.fdopen(descriptor, 'r', encoding='utf-8') as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise ValueError('launch specification is not a regular file')
        if info.st_uid != RUN_UID or info.st_mode & 0o077:
            raise ValueError('launch specification ownership or mode is unsafe')
        if info.st_size <= 0 or info.st_size > 4096:
            raise ValueError('launch specification size is invalid')
        value = json.load(handle)
    if not isinstance(value, dict) or set(value) != {
        'version', 'sessionId', 'user', 'shellVt', 'browserVt', 'humanUser', 'humanHome'
    }:
        raise ValueError('launch specification fields are invalid')
    if value['version'] != 1 or value['user'] != RUN_USER:
        raise ValueError('launch specification identity is invalid')
    verified_human(str(value['humanUser']), str(value['humanHome']))
    session = str(value['sessionId'])
    if not SESSION_PATTERN.fullmatch(session):
        raise ValueError('launch session identifier is invalid')
    if isinstance(value['shellVt'], bool) or isinstance(value['browserVt'], bool):
        raise ValueError('launch virtual terminals are invalid')
    shell_vt = int(value['shellVt'])
    browser_vt = int(value['browserVt'])
    if not 1 <= shell_vt <= 12 or not 1 <= browser_vt <= 12 or shell_vt == browser_vt:
        raise ValueError('launch virtual terminals are invalid')
    return {'sessionId': session, 'shellVt': shell_vt, 'browserVt': browser_vt, 'humanUser': str(value['humanUser']), 'humanHome': str(value['humanHome'])}


def quiet(*args: str, timeout: float = 30.0) -> int:
    try:
        return subprocess.run(
            list(args), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, timeout=timeout, check=False
        ).returncode
    except (OSError, subprocess.TimeoutExpired):
        return 1


def write_json_as_user(path: Path, value: dict[str, Any]) -> None:
    payload = json.dumps(value, indent=2, sort_keys=True) + '\n'
    helper = r'''
import os, sys, tempfile
from pathlib import Path
path = Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as handle:
        handle.write(sys.stdin.read())
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
finally:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
'''
    result = subprocess.run(
        ['/usr/sbin/runuser', '-u', RUN_USER, '--', '/usr/bin/python3',
         '-c', helper, str(path)], input=payload, text=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        timeout=10.0, check=False
    )
    if result.returncode != 0:
        raise OSError(result.stderr.strip() or f'could not write {path}')


def append_log(message: str) -> None:
    result = subprocess.run(
        ['/usr/sbin/runuser', '-u', RUN_USER, '--', '/bin/bash', '-c',
         'set -e; umask 077; mkdir -p -- "$(dirname -- "$1")"; '
         'printf "%s\\n" "$2" >> "$1"',
         'browser-log', str(LOG_PATH), message.rstrip()],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        timeout=10.0, check=False
    )
    if result.returncode != 0:
        print(message.rstrip(), file=sys.stderr)


def read_exit_code_as_user() -> int | None:
    result = subprocess.run(
        ['/usr/sbin/runuser', '-u', RUN_USER, '--', '/bin/cat', str(EXIT_PATH)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        timeout=5.0, check=False
    )
    value = result.stdout.strip()
    if result.returncode != 0 or not re.fullmatch(r'[0-9]{1,3}', value):
        return None
    code = int(value)
    return code if 0 <= code <= 255 else None


def write_status(session: str, active: bool, phase: str,
                 message: str, exit_code: int | None = None) -> None:
    value: dict[str, Any] = {
        'version': 1,
        'sessionId': session,
        'active': active,
        'phase': phase,
        'message': message,
        'updatedUtc': time.time(),
    }
    if exit_code is not None:
        value['exitCode'] = exit_code
        value['cleanExit'] = exit_code == 0
    write_json_as_user(STATUS_PATH, value)


def stop_shell() -> bool:
    if quiet('/usr/bin/systemctl', 'stop', 'neutronos.service', timeout=35.0) != 0:
        return False
    deadline = time.monotonic() + 15.0
    while time.monotonic() < deadline:
        if quiet('/usr/bin/systemctl', 'is-active', '--quiet',
                 'neutronos.service', timeout=2.0) != 0:
            time.sleep(0.6)
            return True
        time.sleep(0.15)
    return False


def active_vt() -> int:
    try:
        result = subprocess.run(
            ['/usr/bin/fgconsole'], stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, timeout=3.0, check=False)
        value = int(result.stdout.strip())
        return value if 1 <= value <= 12 else 0
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return 0


def park_shell(shell_vt: int, browser_vt: int) -> bool:
    """Park the shell while Weston retains DRM and focuses the browser surface."""
    return quiet('/usr/bin/systemctl', 'kill', '--kill-whom=main',
                 '--signal=SIGSTOP', 'neutronos.service', timeout=5.0) == 0


def resume_parked_shell(shell_vt: int) -> bool:
    resumed = quiet('/usr/bin/systemctl', 'kill', '--kill-whom=main',
                    '--signal=SIGCONT', 'neutronos.service', timeout=5.0) == 0
    return resumed and quiet(
        '/usr/bin/systemctl', 'is-active', '--quiet',
        'neutronos.service', timeout=3.0) == 0


def start_shell(shell_vt: int) -> bool:
    # Keep the Browser's branded return frame on its VT while NeutronShell
    # initializes off-screen. Switch only after Main.qml has swapped a real
    # frame containing the opaque return overlay/Console path.
    frame_ready = Path('/run/neutronos/shell-frame-ready')
    try:
        frame_ready.unlink()
    except FileNotFoundError:
        pass
    started = quiet('/usr/bin/systemctl', 'start',
                    'neutronos.service', timeout=35.0) == 0
    if not started:
        return False
    deadline = time.monotonic() + 35.0
    while time.monotonic() < deadline:
        if frame_ready.is_file():
            break
        time.sleep(0.08)
    return frame_ready.is_file()


def set_getty_state(browser_vt: int, stop: bool) -> bool:
    return False


def restore_getty(browser_vt: int, was_active: bool) -> None:
    pass


def clear_vt(vt: int) -> None:
    pass


def remove_runtime_files() -> None:
    result = subprocess.run(
        ['/usr/sbin/runuser', '-u', RUN_USER, '--', '/bin/bash', '-c',
         'set -e; for path do rm -f -- "$path"; done',
         'browser-cleanup', str(LOG_PATH), str(EXIT_PATH), str(RETURN_PATH)],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        timeout=10.0, check=False
    )
    if result.returncode != 0:
        append_log(result.stderr.strip() or 'Could not clear stale browser state')


def main() -> int:
    if os.geteuid() != 0 or len(sys.argv) != 2:
        return 64
    if Path(sys.argv[1]) != EXPECTED_SPEC:
        return 64
    for executable in (RUNTIME_HELPER, BROWSER_EXECUTABLE):
        if not trusted_root_executable(executable):
            print(f'Untrusted or missing browser component: {executable}', file=sys.stderr)
            return 69

    try:
        spec = validate_spec(EXPECTED_SPEC)
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(f'Rejected browser launch request: {error}', file=sys.stderr)
        return 65
    finally:
        quiet('/usr/sbin/runuser', '-u', RUN_USER, '--',
              '/bin/rm', '-f', '--', str(EXPECTED_SPEC), timeout=5.0)

    session = spec['sessionId']
    shell_vt = spec['shellVt']
    browser_vt = spec['browserVt']
    remove_runtime_files()

    browser_code = 1
    shell_released = False
    shell_parked = False
    getty_was_active = False
    message = 'Browser did not start'
    try:
        write_status(session, True, 'handoff', 'Preparing NeutronOS Browser')
        getty_was_active = set_getty_state(browser_vt, True)
        clear_vt(browser_vt)
        # Preserve the rendered shell while the browser becomes the newest
        # fullscreen Wayland surface. Weston retains DRM throughout.
        clear_vt(shell_vt)
        shell_parked = park_shell(shell_vt, browser_vt)
        if not shell_parked:
            raise RuntimeError('NeutronOS display could not be released safely')
        shell_released = True
        write_status(session, True, 'browser', 'NeutronOS Browser is loading')

        command = [str(RUNTIME_HELPER), session, spec['humanUser']]
        try:
            runtime_code = subprocess.run(
                command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, check=False
            ).returncode
        except OSError as error:
            runtime_code = 1
            append_log(f'Unable to start browser runtime: {error}')

        recorded_code = read_exit_code_as_user()
        browser_code = recorded_code if recorded_code is not None else runtime_code
        clear_vt(browser_vt)
        message = (
            'Browser closed normally' if browser_code == 0 else
            f'Browser failed with error {browser_code}. Runtime details were saved to {LOG_PATH}.'
        )
    except Exception as error:
        browser_code = 1
        message = f'Browser handoff failed: {error}'
        append_log(message)
    finally:
        try:
            write_status(session, False, 'restoring',
                         'Returning directly to NeutronOS Console', browser_code)
            if not shell_parked:
                write_json_as_user(RETURN_PATH, {
                    'version': 1,
                    'sessionId': session,
                    'userName': RUN_USER,
                    'pending': True,
                    'cleanExit': browser_code == 0,
                    'exitCode': browser_code,
                    'message': message,
                    'logPath': str(LOG_PATH),
                    'returnedUtc': time.time(),
                })
        except Exception as error:
            append_log(f'Could not write browser return state: {error}')

        restored = (resume_parked_shell(shell_vt) if shell_parked
                    else start_shell(shell_vt))
        if shell_parked:
            quiet('/usr/sbin/runuser', '-u', RUN_USER, '--',
                  '/bin/rm', '-f', '--', str(RETURN_PATH), timeout=5.0)
        restore_getty(browser_vt, getty_was_active)
        if not restored:
            append_log('CRITICAL: NeutronOS shell could not be restarted after Browser')
        try:
            write_status(session, False, 'idle', message, browser_code)
        except Exception as error:
            append_log(f'Could not write final browser state: {error}')

    return 0 if shell_released and browser_code == 0 else browser_code or 1


if __name__ == '__main__':
    raise SystemExit(main())
