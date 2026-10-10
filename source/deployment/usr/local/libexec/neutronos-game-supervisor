#!/usr/bin/env python3
"""NeutronOS isolated game display supervisor.

Weston retains DRM while NeutronShell and emulators use fullscreen Wayland.
This supervisor parks the shell, starts the emulator without root privileges,
and resumes the same shell after the game exits.
"""

from __future__ import annotations

import fcntl
import glob
import json
import os
import pwd
import grp
import re
import stat
from contextlib import contextmanager
import selectors
import signal
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

BTN_START = 315
EV_KEY = 0x01
EVENT = struct.Struct("llHHI")
HOLD_SECONDS = 3.0


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


SERVICE = pwd.getpwnam('neutronos')

@contextmanager
def user_io():
    previous_uid, previous_gid = os.geteuid(), os.getegid()
    previous_groups = os.getgroups()
    os.setgroups([SERVICE.pw_gid] + [g.gr_gid for g in grp.getgrall() if SERVICE.pw_name in g.gr_mem])
    os.setegid(SERVICE.pw_gid)
    os.seteuid(SERVICE.pw_uid)
    try:
        yield
    finally:
        os.seteuid(previous_uid)
        os.setegid(previous_gid)
        os.setgroups(previous_groups)

def personal_io(function):
    def wrapped(*args, **kwargs):
        with user_io():
            return function(*args, **kwargs)
    return wrapped


@personal_io
def atomic_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


@personal_io
def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError):
        return {}


def run_quiet(*args: str, timeout: float = 20.0) -> int:
    try:
        return subprocess.run(
            list(args),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
            check=False,
        ).returncode
    except (OSError, subprocess.TimeoutExpired):
        return 1


def stop_shell() -> None:
    if run_quiet('/usr/bin/systemctl', 'kill', '--kill-whom=main', '--signal=SIGSTOP', 'neutronos.service') != 0:
        raise RuntimeError('NeutronOS shell could not be parked')


def start_shell(shell_vt: int) -> None:
    run_quiet('/usr/bin/systemctl', 'kill', '--kill-whom=main', '--signal=SIGCONT', 'neutronos.service')



class StartHoldMonitor:
    def __init__(self) -> None:
        self.selector = selectors.DefaultSelector()
        self.devices: dict[int, Any] = {}
        self.pressed_at: dict[int, float] = {}
        self.last_scan = 0.0
        self.triggered = False
        self.scan()

    def close(self) -> None:
        for file in list(self.devices.values()):
            try:
                self.selector.unregister(file)
            except Exception:
                pass
            try:
                file.close()
            except Exception:
                pass
        self.devices.clear()

    def scan(self) -> None:
        self.last_scan = time.monotonic()
        known_paths = {getattr(file, "name", "") for file in self.devices.values()}
        for name in glob.glob("/dev/input/event*"):
            if name in known_paths:
                continue
            try:
                file = open(name, "rb", buffering=0)
                flags = fcntl.fcntl(file.fileno(), fcntl.F_GETFL)
                fcntl.fcntl(file.fileno(), fcntl.F_SETFL, flags | os.O_NONBLOCK)
                self.selector.register(file, selectors.EVENT_READ)
                self.devices[file.fileno()] = file
            except OSError:
                continue

    def poll(self) -> bool:
        now = time.monotonic()
        if now - self.last_scan >= 2.0:
            self.scan()
        for key, _ in self.selector.select(timeout=0):
            file = key.fileobj
            try:
                payload = file.read(EVENT.size * 32)
            except OSError:
                payload = b""
            if not payload:
                continue
            for offset in range(0, len(payload) - EVENT.size + 1, EVENT.size):
                _, _, event_type, code, value = EVENT.unpack_from(payload, offset)
                if event_type != EV_KEY or code != BTN_START:
                    continue
                fd = file.fileno()
                if value == 1:
                    self.pressed_at[fd] = now
                    self.triggered = False
                elif value == 0:
                    self.pressed_at.pop(fd, None)
                    if not self.pressed_at:
                        self.triggered = False
        if not self.triggered and any(now - started >= HOLD_SECONDS for started in self.pressed_at.values()):
            self.triggered = True
            return True
        return False



@personal_io
def append_video_mode(config_path: Path, mode: str) -> None:
    try:
        original = config_path.read_text(encoding="utf-8")
    except OSError:
        original = ""
    kept = []
    for line in original.splitlines():
        stripped = line.strip()
        if stripped.startswith("video_driver =") or stripped.startswith("video_context_driver =") or stripped.startswith("audio_driver ="):
            continue
        kept.append(line)
    if mode == "wayland":
        kept.extend([
            'video_driver = "gl"',
            'video_context_driver = "wayland"',
        ])
    else:
        kept.extend([
            'video_driver = "sdl2"',
            'video_context_driver = ""',
        ])
    kept.append('audio_driver = "pulse"')
    config_path.write_text("\n".join(kept) + "\n", encoding="utf-8")


def find_append_config(arguments: list[str]) -> Path | None:
    try:
        index = arguments.index("--appendconfig")
        return Path(arguments[index + 1])
    except (ValueError, IndexError):
        return None


@personal_io
def read_exit_code(path: Path) -> int | None:
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        return None


@personal_io
def read_pid(path: Path) -> int | None:
    try:
        value = int(path.read_text(encoding="utf-8").strip())
        return value if value > 1 else None
    except (OSError, ValueError):
        return None


def terminate_runtime(pid_path: Path, interrupt: bool = True) -> None:
    pid = read_pid(pid_path)
    if pid is None:
        return
    try:
        if os.stat('/proc/' + str(pid)).st_uid != SERVICE.pw_uid:
            return
        if Path('/proc/' + str(pid) + '/cgroup').read_text() != Path('/proc/self/cgroup').read_text():
            return
    except OSError:
        return
    first = signal.SIGINT if interrupt else signal.SIGTERM
    try:
        os.killpg(pid, first)
    except ProcessLookupError:
        return
    except OSError:
        try:
            os.kill(pid, first)
        except OSError:
            return
    deadline = time.monotonic() + 5.0
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except OSError:
            return
        time.sleep(0.1)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(pid, sig)
        except OSError:
            try:
                os.kill(pid, sig)
            except OSError:
                return
        time.sleep(0.8)


@personal_io
def video_failure(log_path: Path) -> bool:
    try:
        tail = log_path.read_text(encoding="utf-8", errors="replace")[-12000:].lower()
    except OSError:
        return False
    markers = (
        "video_driver_init_internal",
        "fatal error received in video_driver_init_internal",
        "fatal error in video driver init",
        "failed to initialize video driver",
        "egl driver exiting",
    )
    return any(marker in tail for marker in markers)


def wait_for_command(command_path: Path, session_id: str) -> str:
    while True:
        command = load_json(command_path)
        if command.get("sessionId") == session_id and command.get("action") in {"resume", "exit"}:
            try:
                with user_io():
                    command_path.unlink()
            except FileNotFoundError:
                pass
            return str(command["action"])
        time.sleep(0.2)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: neutronos-game-supervisor.py SPEC.json", file=sys.stderr)
        return 64

    spec_path = Path(sys.argv[1])
    # Runtime metadata is service-owned and no arbitrary root destination is accepted.
    try:
        info = spec_path.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != SERVICE.pw_uid or info.st_mode & 0o077:
            return 65
        spec = load_json(spec_path)
        human = verified_human(str(spec.get('humanUser') or ''), str(spec.get('humanHome') or ''))
        runtime = Path(human.pw_dir) / 'apps/games/runtime'
        if spec_path != runtime / 'external-launch.json' or spec_path.is_symlink():
            return 65
        for key, leaf in (('statePath','external-session.json'), ('commandPath','external-command.json'),
                          ('logPath','last-runtime.log'), ('exitCodePath','last-exit-code'), ('pidPath','runtime.pid')):
            if Path(str(spec.get(key) or '')) != runtime / leaf:
                return 65
        if spec.get('runtimeHelper') != '/opt/neutronos/scripts/neutronos-game-runtime.sh':
            return 65
        program_path = Path(str(spec.get('program') or ''))
        program_info = program_path.stat()
        if (not program_path.is_absolute() or not str(program_path.resolve()).startswith(('/usr/bin/', '/usr/local/bin/')) or
                not stat.S_ISREG(program_info.st_mode) or program_info.st_uid != 0 or program_info.st_mode & 0o022):
            return 65
    except (KeyError, OSError, ValueError, subprocess.SubprocessError):
        return 65
    required = ("sessionId", "gameId", "title", "program", "statePath", "commandPath", "runtimeHelper")
    if any(not spec.get(key) for key in required):
        return 65

    state_path = Path(spec["statePath"])
    command_path = Path(spec["commandPath"])
    log_path = Path(spec["logPath"])
    status_path = Path(spec["exitCodePath"])
    pid_path = Path(spec["pidPath"])
    helper = Path(spec["runtimeHelper"])
    session_id = str(spec["sessionId"])
    shell_vt = int(spec.get("shellVt", 1))
    game_vt = int(spec.get("gameVt", 2))
    program = str(spec["program"])
    arguments = [str(value) for value in spec.get("arguments", [])]
    working_directory = str(spec.get("workingDirectory") or "/")
    environment = {str(k): str(v) for k, v in dict(spec.get("environment", {})).items()}
    environment.pop("QT_QPA_PLATFORM", None)
    environment["HOME"] = human.pw_dir
    environment["NEUTRONOS_HUMAN_USER"] = human.pw_name
    environment["XDG_RUNTIME_DIR"] = "/run/neutronos-compositor"
    environment["WAYLAND_DISPLAY"] = "wayland-0"
    environment["XDG_SESSION_TYPE"] = "wayland"
    environment["SDL_VIDEODRIVER"] = "wayland"
    environment["SDL_AUDIODRIVER"] = "pulseaudio"
    environment["PIPEWIRE_RUNTIME_DIR"] = "/run/user/" + str(SERVICE.pw_uid)
    environment["PULSE_SERVER"] = "unix:/run/user/" + str(SERVICE.pw_uid) + "/pulse/native"
    environment["DBUS_SESSION_BUS_ADDRESS"] = "unix:path=/run/user/" + str(SERVICE.pw_uid) + "/bus"
    kind = str(spec.get("kind", ""))
    user = spec.get("user") if isinstance(spec.get("user"), dict) else {}

    base_state: dict[str, Any] = {
        "version": 1,
        "sessionId": session_id,
        "gameId": str(spec["gameId"]),
        "title": str(spec["title"]),
        "user": user,
        "active": True,
        "paused": False,
        "returnPending": False,
        "cleanExit": False,
        "phase": "launching",
        "message": f"Preparing {spec['title']}…",
    }
    atomic_json(state_path, base_state)
    try:
        with user_io():
            command_path.unlink()
    except FileNotFoundError:
        pass

    config_path = find_append_config(arguments) if kind == "retroarch" else None
    modes = ["default"]
    if kind == "retroarch" and config_path is not None:
        # Try native Wayland OpenGL, then SDL through the same compositor.
        modes = ["wayland", "sdl"]

    shell_released = False
    stop_shell()
    shell_released = True
    monitor = StartHoldMonitor()
    try:
        while True:
            paused_by_hold = False
            final_rc: int | None = None
            final_runtime_rc = 1

            for mode_index, mode in enumerate(modes):
                if config_path is not None and mode in {"wayland", "sdl"}:
                    append_video_mode(config_path, mode)
                if mode == "sdl":
                    environment["SDL_VIDEODRIVER"] = "wayland"
                    environment["SDL_AUDIODRIVER"] = "pulseaudio"
                with user_io():
                    status_path.unlink(missing_ok=True)
                with user_io():
                    pid_path.unlink(missing_ok=True)
                if mode_index == 0:
                    with user_io():
                        log_path.write_text("", encoding="utf-8")
                else:
                    with user_io():
                        with log_path.open("a", encoding="utf-8") as handle:
                            handle.write(f"\n[NeutronOS] Retrying RetroArch with {mode.upper()} video mode.\n")

                state = dict(base_state)
                state.update({
                    "phase": "running",
                    "active": True,
                    "paused": False,
                    "returnPending": False,
                    "message": f"{spec['title']} is running. Hold Settings for 3 seconds to return.",
                    "videoMode": mode,
                })
                atomic_json(state_path, state)

                command = [
                    "/usr/sbin/runuser", "-u", "neutronos", "--", "/usr/bin/env", "-i",
                    *[f"{key}={value}" for key,value in environment.items()],
                    str(helper), str(status_path), str(log_path), str(pid_path), program, *arguments,
                ]
                process = subprocess.Popen(
                    command,
                    cwd=working_directory,
                    env={"PATH":"/usr/local/bin:/usr/bin:/bin","LANG":"C.UTF-8"},
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                )

                while process.poll() is None:
                    if monitor.poll():
                        paused_by_hold = True
                        terminate_runtime(pid_path, interrupt=True)
                        break
                    time.sleep(0.04)

                try:
                    output, _ = process.communicate(timeout=8.0)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    output, _ = process.communicate(timeout=3.0)
                final_runtime_rc = process.returncode or 0
                if output:
                    with user_io():
                        with log_path.open("a", encoding="utf-8") as handle:
                            handle.write("\n[runtime]\n" + output)
                final_rc = read_exit_code(status_path)

                if paused_by_hold:
                    break
                if final_rc == 0:
                    break
                if mode_index + 1 < len(modes) and video_failure(log_path):
                    continue
                break

            if paused_by_hold:
                paused_state = dict(base_state)
                paused_state.update({
                    "phase": "paused",
                    "active": True,
                    "paused": True,
                    "returnPending": True,
                    "cleanExit": True,
                    "message": "Game paused. Choose Resume or Exit.",
                })
                atomic_json(state_path, paused_state)
                start_shell(shell_vt)
                shell_released = False
                action = wait_for_command(command_path, session_id)
                if action == "exit":
                    paused_state.update({
                        "phase": "finished",
                        "active": False,
                        "paused": False,
                        "returnPending": False,
                        "message": f"{spec['title']} closed.",
                    })
                    atomic_json(state_path, paused_state)
                    return 0
                paused_state.update({
                    "phase": "launching",
                    "active": True,
                    "paused": False,
                    "returnPending": False,
                    "message": f"Resuming {spec['title']}…",
                })
                atomic_json(state_path, paused_state)
                stop_shell()
                shell_released = True
                monitor.triggered = False
                monitor.pressed_at.clear()
                continue

            clean = final_rc == 0
            if final_rc is None:
                detail = f"The game runtime did not report an exit code (runtime={final_runtime_rc})."
            elif clean:
                detail = f"{spec['title']} closed normally."
            else:
                try:
                    log_tail = log_path.read_text(encoding="utf-8", errors="replace")[-700:].strip()
                except OSError:
                    log_tail = ""
                detail = f"{spec['title']} closed with emulator error {final_rc}. {log_tail}"

            finished = dict(base_state)
            finished.update({
                "phase": "finished" if clean else "failed",
                "active": False,
                "paused": False,
                "returnPending": True,
                "cleanExit": clean,
                "exitCode": final_rc if final_rc is not None else -1,
                "message": detail,
            })
            atomic_json(state_path, finished)
            start_shell(shell_vt)
            shell_released = False
            return 0 if clean else 1
    except BaseException as error:
        failure = dict(base_state)
        failure.update({
            "phase": "failed",
            "active": False,
            "paused": False,
            "returnPending": True,
            "cleanExit": False,
            "message": f"Game display handoff failed: {error}",
        })
        try:
            atomic_json(state_path, failure)
        except Exception:
            pass
        raise
    finally:
        monitor.close()
        # Never leave the user on a black console if the transient supervisor,
        # openvt, or emulator throws unexpectedly.  Kill any remaining runtime
        # first so it releases DRM, then restore the NeutronOS shell.
        if read_pid(pid_path) is not None:
            terminate_runtime(pid_path, interrupt=False)
        if shell_released or run_quiet(
            "systemctl", "is-active", "--quiet", "neutronos.service", timeout=2.0
        ) != 0:
            start_shell(shell_vt)


if __name__ == "__main__":
    raise SystemExit(main())
