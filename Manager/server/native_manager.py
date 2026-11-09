#!/usr/bin/python3
"""NeutronOS Manager native read-only server, Python standard library only.

Bind to loopback, behind the existing Gemini Tailscale-only Nginx mTLS server.
The proxy secret and verified client certificate are REQUIRED on every route.
All destructive actions, uploads and shell sessions are disabled.
"""
import html
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import threading
import time
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

HOST = os.environ.get("MANAGER_HOSTNAME", "neutronos.neutronprojects.com").lower()
SECRET = os.environ.get("MANAGER_PROXY_SECRET", "")
if len(SECRET) < 32:
    raise SystemExit("MANAGER_PROXY_SECRET missing or too short. Refusing to start.")
WEB = Path(__file__).resolve().parent.parent / "web"
MEDIA = Path("/NeutronMedia")
USER_DATA = Path(os.environ.get("MANAGER_USER_DATA_PATH", "/NeutronOS/drneutron"))
FILES_HOME = Path(os.environ.get("MANAGER_FILES_HOME", "/var/lib/neutron-manager"))
IDLE = 1800
sessions = {}
lock = threading.RLock()

SERVICES = {
    "jellyfin": ("Jellyfin", "docker", "jellyfin", "Media Server · Movies · Shows · Live", "play", "purple"),
    "qbittorrent": ("qBittorrent", "docker", "qbittorrent", "Torrents · Downloads · Automation", "download", "blue"),
    "torrentlab": ("TorrentLab", "systemd", "torrentlab2.service", "Media Tools · Convert · Subtitles · Metadata", "flask", "red"),
    "neutronstream": ("NeutronStream", "systemd", "neutronstream.service", "Streaming · Remote Access · Live", "pc", "cyan"),
    "neutronai": ("NeutronAI", "systemd", "neutronllm-http.service", "Qwen · Ornith · DeepSeek", "atom", "red"),
}
APP_STYLES = {
    "neutronai": ("NeutronAI", "atom", "red"),
    "torrentlab": ("TorrentLab", "flask", "green"),
    "games": ("Games", "play", "blue"),
    "jellyfin": ("Jellyfin", "play", "violet"),
    "qbittorrent": ("qBittorrent", "download", "cyan"),
    "neutronstream": ("NeutronStream", "pc", "cyan"),
    "browser": ("Browser", "globe", "blue"),
    "terminal": ("Terminal", "term", "violet"),
    "files": ("Files / SFTP", "folder", "cyan"),
    "settings": ("Settings", "gear", "red"),
    "store": ("App Store", "stack", "green"),
    "security": ("Security", "shield", "violet"),
    "remote": ("Remote Systems", "pc", "cyan"),
    "docker": ("Docker", "cube", "blue"),
    "controller": ("Controllers", "gear", "red"),
}

def shell(args, timeout=3):
    try:
        r = subprocess.run(args, timeout=timeout, capture_output=True, text=True, check=False)
        return r.stdout.strip() if r.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""

def mem():
    info = {}
    with open("/proc/meminfo", encoding="utf-8") as f:
        for line in f:
            key, _, value = line.partition(":")
            info[key] = int(value.strip().split()[0]) * 1024
    return info

def disk(root):
    if not root.is_dir():
        return (0.0, 0.0)
    usage = shutil.disk_usage(root)
    return (usage.used / 1e9, usage.total / 1e9)

def cpu_sample():
    nums = [int(v) for v in Path("/proc/stat").read_text().splitlines()[0].split()[1:]]
    return sum(nums), nums[3] + nums[4]

def status():
    a = cpu_sample()
    time.sleep(0.12)
    b = cpu_sample()
    all_delta = b[0] - a[0]
    pct = round(100 * (1 - (b[1] - a[1]) / all_delta)) if all_delta > 0 else 0
    inf = mem()
    ram_total = inf["MemTotal"] / 1e9
    ram_used = (inf["MemTotal"] - inf.get("MemAvailable", 0)) / 1e9
    user_used, user_total = disk(USER_DATA)
    mounted = MEDIA.is_mount()
    media_used, media_total = disk(MEDIA) if mounted else (0.0, 0.0)
    secs = int(float(Path("/proc/uptime").read_text().split()[0]))
    days, rem = divmod(secs, 86400)
    hrs, rem = divmod(rem, 3600)
    mins = rem // 60
    cpu = "Unavailable"
    for line in Path("/proc/cpuinfo").read_text().splitlines():
        if line.startswith("model name"):
            cpu = line.partition(":")[2].strip()
            break
    gpu = next((x for x in shell(["/usr/bin/lspci"]).splitlines()
                if "VGA compatible" in x or "Display controller" in x), "Unavailable")
    loads = shell(["/usr/bin/uptime"])
    load = " / ".join(f"{v:.2f}" for v in os.getloadavg())
    return {
        "name": "Gemini", "version": os.environ.get("MANAGER_OS_VERSION", "NeutronOS Gemini"),
        "os": "NeutronOS Gemini", "online": True, "cpu_pct": max(0, min(100, pct)),
        "ram_used_gb": round(ram_used, 1), "ram_total_gb": round(ram_total, 1),
        "user_used_gb": round(user_used, 1), "user_total_gb": round(user_total, 1),
        "media_used_tb": round(media_used / 1e3, 2), "media_total_tb": round(media_total / 1e3, 2),
        "media_mounted": mounted, "kernel": os.uname().release,
        "uptime": f"{days} days, {hrs} hours" if days else f"{hrs} hours, {mins} min",
        "cpu_model": cpu, "gpu": gpu.split(": ", 1)[-1], "cores": f"{os.cpu_count()} logical threads",
        "architecture": os.uname().machine,
        "ip": shell(["/usr/bin/tailscale", "ip", "-4"]) or "Unavailable",
        "local_ip": os.environ.get("MANAGER_LAN_IP", "Unavailable"), "load": load,
        "swap": f'{(inf.get("SwapTotal", 0) - inf.get("SwapFree", 0))/1e9:.1f} / {inf.get("SwapTotal",0)/1e9:.1f} GB',
        "power_enabled": False, "read_only": True,
    }

def service_state(ident, kind, name):
    if kind == "docker":
        # No Docker privileges are added without permission. Be explicit.
        return "unavailable"
    if ident == "neutronstream":
        try:
            with socket.create_connection(("127.0.0.1", 8765), 0.3):
                return "running"
        except OSError:
            pass
    state = shell(["/usr/bin/systemctl", "is-active", name])
    return state.lower() or "unavailable"

def services():
    return [
        {"id": ident, "name": name, "kind": kind, "unit": unit,
         "summary": summary, "icon": icon, "color": color, "state": service_state(ident, kind, unit)}
        for ident, (name, kind, unit, summary, icon, color) in SERVICES.items()
    ]

def apps():
    found = set()
    for root in (Path("/NeutronOS/qml/apps"), Path("/NeutronOS/drneutron/apps")):
        try:
            for e in root.iterdir():
                if e.is_dir() and re.fullmatch(r"[A-Za-z0-9._-]{1,80}", e.name):
                    found.add(e.name.lower())
        except OSError:
            continue
    found.update(("neutronai", "torrentlab", "jellyfin", "qbittorrent", "neutronstream", "terminal", "files", "docker"))
    ordered = list(dict.fromkeys([*APP_STYLES.keys(), *sorted(found)]))
    return [
        {"id": ident, "name": APP_STYLES.get(ident, (ident.replace("-", " ").title(), "gear", "blue"))[0],
         "icon": APP_STYLES.get(ident, ("", "gear", "blue"))[1],
         "color": APP_STYLES.get(ident, ("", "gear", "blue"))[2],
         "installed": ident in found}
        for ident in ordered
    ]

def tools():
    result = {}
    for ident in (*APP_STYLES.keys(), "sftp"):
        val = os.environ.get("MANAGER_TOOL_" + ident.upper().replace("-", "_"), "").strip()
        if val.startswith("/") and not val.startswith("//") and "\\" not in val:
            result[ident] = val
        elif re.fullmatch(r"https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?(/[A-Za-z0-9_./%+-]*)?", val):
            host = val[8:].split("/", 1)[0].split(":")[0].lower()
            if host == HOST or host.endswith(".neutronprojects.com"):
                result[ident] = val
    return result

def safe_file(raw):
    if not raw.startswith("/"):
        raise PermissionError("Absolute file path required")
    source = Path(raw)
    if MEDIA == source or MEDIA in source.parents:
        if not MEDIA.is_mount():
            raise PermissionError("NeutronMedia not mounted")
    path = source.resolve(strict=True)
    allowed = tuple(root.resolve(strict=True) for root in (MEDIA, FILES_HOME) if root.is_dir())
    if not any(path == r or r in path.parents for r in allowed):
        raise PermissionError("Outside allowed directories")
    return path

def entries(raw):
    folder = safe_file(raw)
    if not folder.is_dir():
        raise NotADirectoryError("Not a directory")
    listing = []
    for child in sorted(folder.iterdir(), key=lambda c: (not c.is_dir(), c.name.lower()))[:500]:
        try:
            resolved = safe_file(str(child))
            listing.append({"name": child.name, "directory": resolved.is_dir(),
                            "path": str(resolved), "size": resolved.stat().st_size if resolved.is_file() else 0})
        except (OSError, PermissionError):
            continue
    return {"path": str(folder), "entries": listing}

MIME = {".html":"text/html; charset=utf-8", ".js":"text/javascript; charset=utf-8",
        ".css":"text/css; charset=utf-8", ".json":"application/json", ".webmanifest":"application/manifest+json",
        ".png":"image/png", ".svg":"image/svg+xml", ".ico":"image/x-icon"}

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "NeutronManager"
    sys_version = ""

    def base_headers(self, kind="application/json; charset=utf-8", length=0):
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self' wss:; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")

    def send_json(self, obj, status=200, cookie=None):
        body = json.dumps(obj, separators=(",", ":")).encode()
        self.send_response(status)
        self.base_headers(length=len(body))
        if cookie:
            self.send_header("Set-Cookie", f"__Host-nm={cookie}; Max-Age={IDLE}; Path=/; Secure; HttpOnly; SameSite=Strict")
        self.end_headers()
        self.wfile.write(body)

    def reject(self, status=403, detail="Access denied"):
        self.send_json({"detail": detail}, status=status)

    def trusted(self):
        host = self.headers.get("Host", "").split(":")[0].lower()
        provided = self.headers.get("X-Neutron-Proxy-Secret", "")
        verified = self.headers.get("X-Neutron-Client-Verified", "")
        return (self.client_address[0] == "127.0.0.1" and host == HOST
                and len(provided) == len(SECRET) and secrets.compare_digest(provided, SECRET)
                and verified == "SUCCESS")

    def cookie_session(self):
        jar = SimpleCookie()
        try:
            jar.load(self.headers.get("Cookie", ""))
        except Exception:
            return None, None
        token = jar["__Host-nm"].value if "__Host-nm" in jar else ""
        with lock:
            session = sessions.get(token)
            if session and time.monotonic() - session["last"] < IDLE:
                return token, session
            sessions.pop(token, None)
        return None, None

    def do_GET(self):
        if not self.trusted():
            return self.reject()
        parts = urlsplit(self.path)
        route = parts.path
        if route == "/api/session":
            token, session = self.cookie_session()
            if session is None:
                token = secrets.token_urlsafe(48)
                session = {"csrf": secrets.token_urlsafe(32), "last": time.monotonic()}
                with lock:
                    sessions[token] = session
            return self.send_json({"csrf":session["csrf"], "idle_timeout_seconds":IDLE}, cookie=token)
        if route.startswith("/api/"):
            token, session = self.cookie_session()
            if session is None:
                return self.reject(401, "Session expired")
            try:
                if route == "/api/status":
                    return self.send_json(status())
                if route == "/api/services":
                    return self.send_json(services())
                if route == "/api/apps":
                    return self.send_json(apps())
                if route == "/api/tools":
                    return self.send_json(tools())
                if route == "/api/files":
                    params = parse_qs(parts.query)
                    return self.send_json(entries(params.get("path", ["/NeutronMedia"])[0]))
                if route == "/api/download":
                    path = safe_file(parse_qs(parts.query).get("path", [""])[0])
                    if not path.is_file():
                        return self.reject(400, "Not a regular file")
                    self.send_response(200)
                    self.base_headers(kind="application/octet-stream", length=path.stat().st_size)
                    self.send_header("Content-Disposition", 'attachment; filename="download"')
                    self.end_headers()
                    with path.open("rb") as f:
                        shutil.copyfileobj(f, self.wfile, 1024 * 1024)
                    return
            except (OSError, PermissionError, NotADirectoryError, ValueError):
                return self.reject(403, "File or system resource unavailable")
            return self.reject(404, "Unknown API route")
        relative = route.lstrip("/") or "index.html"
        try:
            file = (WEB / relative).resolve(strict=True)
            if WEB.resolve() not in file.parents or not file.is_file():
                return self.reject(404, "Not found")
            size = file.stat().st_size
            self.send_response(200)
            self.base_headers(kind=MIME.get(file.suffix, "application/octet-stream"), length=size)
            self.end_headers()
            with file.open("rb") as stream:
                shutil.copyfileobj(stream, self.wfile, 1024 * 1024)
        except OSError:
            return self.reject(404, "Not found")

    def do_POST(self):
        if not self.trusted():
            return self.reject()
        token, session = self.cookie_session()
        if session is None:
            return self.reject(401, "Session expired")
        if self.path != "/api/activity":
            return self.reject(403, "Read-only mode. Administration not enabled")
        if self.headers.get("Origin", "") != "https://" + HOST:
            return self.reject(403, "Origin check failed")
        if not secrets.compare_digest(self.headers.get("X-CSRF-Token", ""), session["csrf"]):
            return self.reject(403, "CSRF check failed")
        with lock:
            session["last"] = time.monotonic()
        return self.send_json({"ok":True}, cookie=token)

    def do_PUT(self):
        self.reject()
    def do_PATCH(self):
        self.reject()
    def do_DELETE(self):
        self.reject()

if __name__ == "__main__":
    assert WEB.is_dir(), "Web assets missing"
    server = ThreadingHTTPServer(("127.0.0.1", 8877), Handler)
    print("NeutronOS Manager listening on 127.0.0.1:8877, read-only and mTLS proxy gated", flush=True)
    server.serve_forever()
