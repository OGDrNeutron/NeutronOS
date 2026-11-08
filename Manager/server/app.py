#!/usr/bin/env python3
"""NeutronOS Manager. Local-only ASGI backend behind Tailscale-bound mTLS Nginx.

The app itself performs no TLS termination. NEVER expose its loopback port publicly.
"""
import asyncio
import hmac
import json
import os
import pty
import re
import secrets
import shutil
import signal
import socket
import subprocess
import time
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile, WebSocket
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.websockets import WebSocketDisconnect

HOSTNAME = "neutronos.neutronprojects.com"
BASE = Path(__file__).resolve().parent.parent
WEB = BASE / "web"
USER_HOME = Path.home().resolve()
FILE_ROOTS = tuple(p.resolve() for p in (Path("/NeutronMedia"), USER_HOME) if p.is_dir())
SERVICES = {
    "torrentlab": ("TorrentLab 2.0", "torrentlab2.service"),
    "neutronai": ("NeutronAI backend", "neutronllm-http.service"),
    "ai-ingress": ("NeutronAI ingress", "neutronllm-ingress.service"),
    "docker": ("Docker engine", "docker.service"),
    "jellyfin": ("Jellyfin", "jellyfin.service"),
    "qbittorrent": ("qBittorrent", "qbittorrent-nox.service"),
}
SESSION_LIFETIME_SECONDS = 1800
MAX_UPLOAD_SIZE = 128 * 1024 * 1024
SESSIONS = {}
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


def process(args, timeout=8):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)


def deny(message="Unauthorized", status=403):
    raise HTTPException(status_code=status, detail=message)


def session_cookie(request):
    cookie = request.cookies.get("__Host-nm")
    entry = SESSIONS.get(cookie) if cookie else None
    if entry and time.monotonic() - entry["last"] < SESSION_LIFETIME_SECONDS:
        entry["last"] = time.monotonic()
        return entry
    if cookie:
        SESSIONS.pop(cookie, None)
    return None


def verify_request(request: Request, write=False):
    # The only legitimate ingress is the local nginx proxy, not a public socket.
    remote = request.client.host if request.client else ""
    if remote not in {"127.0.0.1", "::1"} or request.headers.get("host", "").split(":")[0].lower() != HOSTNAME:
        deny()
    if request.method not in ("GET", "HEAD", "OPTIONS"):
        origin = request.headers.get("origin")
        if origin and origin != "https://" + HOSTNAME:
            deny("Invalid origin")
    entry = session_cookie(request)
    if entry is None:
        deny("Session expired", 401)
    if write and not hmac.compare_digest(request.headers.get("x-csrf-token", ""), entry["csrf"]):
        deny("Invalid CSRF token")
    return entry


@app.middleware("http")
async def security_headers(request, call_next):
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; connect-src 'self' wss:; object-src 'none'; frame-ancestors 'none'; "
        "base-uri 'none'; form-action 'self'"
    )
    return response


@app.get("/api/session")
async def session(request: Request):
    remote = request.client.host if request.client else ""
    if remote not in {"127.0.0.1", "::1"} or request.headers.get("host", "").split(":")[0].lower() != HOSTNAME:
        deny()
    entry = session_cookie(request)
    cookie = request.cookies.get("__Host-nm")
    if entry is None:
        cookie = secrets.token_urlsafe(40)
        entry = {"csrf": secrets.token_urlsafe(32), "last": time.monotonic()}
        SESSIONS[cookie] = entry
    response = JSONResponse({"csrf": entry["csrf"], "expiresAfterIdleSeconds": SESSION_LIFETIME_SECONDS})
    response.set_cookie("__Host-nm", cookie, max_age=SESSION_LIFETIME_SECONDS,
                        httponly=True, secure=True, samesite="strict", path="/")
    return response


@app.get("/api/status")
async def status(request: Request):
    verify_request(request)
    info = {}
    with open("/proc/meminfo", encoding="utf-8") as f:
        for line in f:
            k, _, v = line.partition(":")
            info[k] = int(v.strip().split()[0])
    used = info["MemTotal"] - info.get("MemAvailable", 0)
    mem = f"{used / 1048576:.1f} / {info['MemTotal'] / 1048576:.1f} GB"
    media = Path("/NeutronMedia")
    if media.is_mount() and media.is_dir():
        disk = shutil.disk_usage(media)
        disk_label = f"{disk.used / 1e12:.2f} / {disk.total / 1e12:.2f} TB"
    else:
        disk_label = "Not mounted"
    return {"load": f"{os.getloadavg()[0]:.2f}", "memory": mem, "disk": disk_label,
            "hostname": socket.gethostname()}


@app.get("/api/services")
async def services(request: Request):
    verify_request(request)
    result = []
    for identifier, (label, unit) in SERVICES.items():
        installed = process(["/usr/bin/systemctl", "show", unit, "--property=LoadState", "--value"])
        available = installed.returncode == 0 and installed.stdout.strip() == "loaded"
        state = "Not installed"
        if available:
            read = process(["/usr/bin/systemctl", "is-active", unit])
            state = read.stdout.strip() or "unknown"
        result.append({"id": identifier, "label": label, "unit": unit,
                       "state": state, "available": available})
    return result


@app.post("/api/services/{identifier}/{action}")
async def service_action(identifier: str, action: str, request: Request):
    verify_request(request, write=True)
    if identifier not in SERVICES or action not in ("start", "stop", "restart"):
        deny("Not permitted")
    # Only the exact configured unit/action pair is executed. Never pass shell input.
    unit = SERVICES[identifier][1]
    result = process(["/usr/bin/sudo", "-n", "/usr/bin/systemctl", action, unit], timeout=20)
    if result.returncode:
        raise HTTPException(409, detail=(result.stderr.strip() or "Operation failed")[:320])
    return {"ok": True}


@app.get("/api/tools")
async def tools(request: Request):
    verify_request(request)
    # Configure only same-origin paths or explicit private HTTPS routes in the environment.
    options = {}
    for identifier in ("torrentlab", "neutronai", "jellyfin", "qbittorrent", "docker", "sftp"):
        name = "MANAGER_TOOL_" + identifier.upper()
        path = os.environ.get(name, "").strip()
        if path.startswith("/") and not path.startswith("//"):
            options[identifier] = path
        elif re.fullmatch(r"https://[a-zA-Z0-9.-]+(?::[0-9]{1,5})?(?:/[^?#]*)?", path):
            options[identifier] = path
    return options


def safe_path(raw, require_exists=True):
    if not raw or not raw.startswith("/"):
        deny("Absolute path required")
    if not FILE_ROOTS:
        deny("No file roots configured")
    path = Path(raw).resolve(strict=require_exists)
    if not any(path == root or root in path.parents for root in FILE_ROOTS):
        deny("Outside allowed file roots")
    return path


@app.get("/api/files")
async def files(request: Request, path: str = "/NeutronMedia"):
    verify_request(request)
    try:
        folder = safe_path(path)
        if not folder.is_dir():
            deny("Not a directory", 400)
        items = []
        for obj in sorted(folder.iterdir(), key=lambda x: (not x.is_dir(), x.name.casefold()))[:500]:
            # Suppress symlinks that resolve outside allowed roots.
            try:
                resolved = safe_path(str(obj))
                items.append({"name": obj.name, "path": str(resolved),
                              "directory": resolved.is_dir(),
                              "size": resolved.stat().st_size if resolved.is_file() else 0})
            except (OSError, HTTPException):
                continue
        return {"path": str(folder), "entries": items}
    except OSError as exc:
        deny(str(exc), 400)


@app.get("/api/download")
async def download(request: Request, path: str):
    verify_request(request)
    try:
        target = safe_path(path)
        if not target.is_file():
            deny("Not a regular file", 400)
        return FileResponse(target, filename=target.name, media_type="application/octet-stream")
    except OSError as exc:
        deny(str(exc), 400)


@app.post("/api/upload")
async def upload(request: Request, path: str = Form(...), file: UploadFile = File(...)):
    verify_request(request, write=True)
    try:
        folder = safe_path(path)
        if not folder.is_dir():
            deny("Not a directory", 400)
        name = Path(file.filename or "").name
        if not name or name in (".", ".."):
            deny("Invalid filename", 400)
        target = folder / name
        # Exclusive, no-follow create: never overwrite files or follow symlinks.
        fd = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        count = 0
        try:
            with os.fdopen(fd, "wb") as handle:
                while chunk := await file.read(65536):
                    count += len(chunk)
                    if count > MAX_UPLOAD_SIZE:
                        raise HTTPException(413, detail="Upload exceeds 128 MB")
                    handle.write(chunk)
        except BaseException:
            target.unlink(missing_ok=True)
            raise
        return {"ok": True, "size": count}
    except FileExistsError:
        deny("File already exists", 409)
    except OSError as exc:
        deny(str(exc), 400)


@app.websocket("/api/terminal")
async def terminal(ws: WebSocket):
    origin = ws.headers.get("origin", "")
    host = ws.headers.get("host", "").split(":")[0].lower()
    remote = ws.client.host if ws.client else ""
    cookie = ws.cookies.get("__Host-nm", "")
    entry = SESSIONS.get(cookie)
    token = ws.query_params.get("csrf", "")
    if (origin != "https://" + HOSTNAME or host != HOSTNAME or remote not in {"127.0.0.1", "::1"}
        or not entry or time.monotonic() - entry["last"] >= SESSION_LIFETIME_SECONDS
        or not hmac.compare_digest(token, entry["csrf"])):
        await ws.close(code=1008)
        return
    entry["last"] = time.monotonic()
    await ws.accept()
    # Spawn an interactive PTY under the non-root service account.
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(str(USER_HOME))
        os.execv("/bin/bash", ["/bin/bash", "--noprofile", "--norc", "-i"])
    async def send_output():
        while True:
            data = await asyncio.to_thread(os.read, master, 4096)
            if not data:
                return
            await ws.send_text(data.decode("utf-8", "replace"))
    async def receive_commands():
        while True:
            chunk = await ws.receive_text()
            if len(chunk) > 8192:
                await ws.close(code=1009)
                return
            if time.monotonic() - entry["last"] >= SESSION_LIFETIME_SECONDS:
                await ws.close(code=1008)
                return
            entry["last"] = time.monotonic()
            await asyncio.to_thread(os.write, master, chunk.encode("utf-8"))
    tasks = [asyncio.create_task(send_output()), asyncio.create_task(receive_commands())]
    try:
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    finally:
        for task in tasks:
            task.cancel()
        try:
            os.killpg(pid, signal.SIGHUP)
        except ProcessLookupError:
            pass
        try:
            os.close(master)
        except OSError:
            pass
        try:
            os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            pass


# Static assets are served only after Nginx has checked the client certificate.
app.mount("/", StaticFiles(directory=str(WEB), html=True), name="web")
