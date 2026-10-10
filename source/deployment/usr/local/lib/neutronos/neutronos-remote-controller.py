#!/usr/bin/env python3
"""Patch 78 TLS remote controller with explicit offline pairing."""
from __future__ import annotations
import base64, json, mimetypes, os, re, secrets, socket, ssl, threading, time, urllib.request
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

from neutronos_remote_security import AuditLog, PairingCodes, RateLimiter, ReplayGuard, TokenStore, ensure_local_certificate

ROOT = Path(os.environ.get("NEUTRONOS_ROOT", "/opt/neutronos")).resolve()
STATIC_DIR = Path(os.environ.get("NEUTRONOS_REMOTE_STATIC_DIR", str(ROOT / "services/remote/Static"))).resolve()
STATE_DIR = Path(os.environ.get("NEUTRONOS_REMOTE_STATE_DIR", "/var/lib/neutronos/remote"))
HOST, PORT = os.environ.get("NEUTRONOS_REMOTE_HOST", "127.0.0.1"), int(os.environ.get("NEUTRONOS_REMOTE_PORT", "8091"))
AUTH_MODE = os.environ.get("NEUTRONOS_REMOTE_AUTH_MODE", "token").strip().lower()
PAM_SOCKET = os.environ.get("NEUTRONOS_REMOTE_PAM_SOCKET", "/run/neutronos/remote-pam.sock")
TLS_CERT = Path(os.environ.get("NEUTRONOS_REMOTE_TLS_CERT", str(STATE_DIR / "tls.crt")))
TLS_KEY = Path(os.environ.get("NEUTRONOS_REMOTE_TLS_KEY", str(STATE_DIR / "tls.key")))
FALLBACK_REALM = os.environ.get("NEUTRONOS_REMOTE_PAM_REALM", "NeutronOS Remote Fallback")
EVENT_FILE = os.environ.get("NEUTRONOS_WEB_CONTROLLER_EVENT_FILE", "/run/neutronos/controller/remote-event.json")
MAX_BODY_BYTES = 16 * 1024
MAX_CONCURRENT_REQUESTS = int(os.environ.get("NEUTRONOS_REMOTE_MAX_CONCURRENCY", "16"))
SOCKET_TIMEOUT_SECONDS = float(os.environ.get("NEUTRONOS_REMOTE_SOCKET_TIMEOUT", "5"))
TOKENS, PAIRING = TokenStore(STATE_DIR / "tokens.json"), PairingCodes(STATE_DIR / "pairing.json")
AUDIT = AuditLog(STATE_DIR / "audit.jsonl")
AUTH_LIMIT, PAIR_LIMIT, PAIR_GLOBAL_LIMIT, COMMAND_LIMIT = RateLimiter(5, 60), RateLimiter(5, 300), RateLimiter(30, 300, 300), RateLimiter(240, 10, 10)
REPLAY = ReplayGuard()
PAM_LIMIT = RateLimiter(8, 300, 300)
PAM_SESSIONS = {}
PAM_SESSION_LOCK = threading.Lock()
PAM_SESSION_TTL = int(os.environ.get("NEUTRONOS_REMOTE_PAM_SESSION_TTL", "900"))
UI_BRIDGE_URL = os.environ.get("NEUTRONOS_REMOTE_UI_BRIDGE_URL", "http://127.0.0.1:8094").rstrip("/")
INPUT_SOCKET = os.environ.get("NEUTRONOS_REMOTE_INPUT_SOCKET", "/run/neutronos/remote-input.sock")
APPS_ROOT = ROOT / "qml" / "apps"
THEME_ICON_ROOT = ROOT / "themes" / "Default" / "apps" / "icons"
APP_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,96}$")

BUTTON_ALIASES = {"x":"primary","cross":"primary","a":"primary","primary":"primary","o":"cancel","circle":"cancel","b":"cancel","cancel":"cancel","square":"secondary","secondary":"secondary","triangle":"context","context":"context","options":"system","start":"system","menu":"system","system":"system","ps":"home","home":"home","guide":"home","share":"quick","create":"quick","select":"quick","quick":"quick","up":"up","down":"down","left":"left","right":"right","l1":"l1","r1":"r1","l2":"l2","r2":"r2","l3":"l3","r3":"r3","leftstick":"leftstick","rightstick":"rightstick"}
STATE_ALIASES = {"press":"press","pressed":"press","down":"press","release":"release","released":"release","up":"release","move":"move","axis":"move","stick":"move"}

def safe_int(value, fallback=0):
    try: return int(value)
    except (TypeError, ValueError): return fallback

def write_event(button, state, x=0, y=0, timestamp=None):
    button = BUTTON_ALIASES.get(str(button or "").strip().lower(), str(button or "").strip().lower())
    state = STATE_ALIASES.get(str(state or "").strip().lower(), str(state or "").strip().lower())
    if button not in set(BUTTON_ALIASES.values()) or state not in {"press","release","move"}: raise ValueError("invalid controller event")
    event = {"button":button,"state":state,"x":max(-32768,min(32767,safe_int(x))),"y":max(-32768,min(32767,safe_int(y))),"time":safe_int(timestamp,int(time.time()*1000)),"source":"remote-authenticated"}
    path=Path(EVENT_FILE); path.parent.mkdir(parents=True,exist_ok=True)
    import tempfile
    fd,name=tempfile.mkstemp(prefix='.remote-event.',dir=path.parent)
    try:
        os.fchmod(fd,0o600)
        with os.fdopen(fd,'w',encoding='utf-8') as handle:
            handle.write(json.dumps(event,separators=(",",":"))+"\n"); handle.flush(); os.fsync(handle.fileno())
        os.replace(name,path)
    finally:
        try: os.unlink(name)
        except FileNotFoundError: pass
    return event

def static_file(path):
    clean = "controller.html" if path in ("","/","/controller") else unquote(path).lstrip("/")
    requested=(STATIC_DIR/clean).resolve()
    try: requested.relative_to(STATIC_DIR)
    except ValueError: return None
    return requested

def pam_agent_auth(username: str, password: str) -> bool:
    if not username or not password or len(username) > 128 or len(password) > 1024:
        return False
    request = json.dumps({"username": username, "password": password}, separators=(",", ":")).encode() + b"\n"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(5.0)
            client.connect(PAM_SOCKET)
            client.sendall(request)
            response = b""
            while b"\n" not in response and len(response) < 4096:
                chunk = client.recv(4096 - len(response))
                if not chunk:
                    break
                response += chunk
        value = json.loads(response.split(b"\n", 1)[0].decode("utf-8"))
        return bool(value.get("ok"))
    except (OSError, ValueError, json.JSONDecodeError):
        return False


def bridge_request(method: str, path: str, payload: dict | None = None) -> dict:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(UI_BRIDGE_URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=2.0) as response:
            value = json.loads(response.read(16384).decode("utf-8"))
            return value if isinstance(value, dict) else {"ok": False, "error": "invalid UI bridge response"}
    except Exception as exc:
        return {"ok": False, "error": f"UI bridge unavailable: {exc}"}


def remote_input(payload: dict) -> dict:
    request = json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(3.0)
            client.connect(INPUT_SOCKET)
            client.sendall(request)
            response = b""
            while b"\n" not in response and len(response) < 16384:
                chunk = client.recv(4096)
                if not chunk:
                    break
                response += chunk
        value = json.loads(response.split(b"\n", 1)[0].decode("utf-8"))
        return value if isinstance(value, dict) else {"ok": False, "error": "invalid keyboard injector response"}
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return {"ok": False, "error": f"native keyboard unavailable: {exc}"}


def safe_app_id(value: object) -> str:
    app_id = str(value or "").strip()
    return app_id if APP_ID_PATTERN.fullmatch(app_id) else ""


def app_manifest(app_dir: Path) -> dict | None:
    try:
        value = json.loads((app_dir / "app.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(value, dict):
        return None
    app_id = safe_app_id(value.get("id") or app_dir.name)
    if not app_id:
        return None
    return value | {"id": app_id}


def discover_apps() -> list[dict]:
    apps: list[dict] = []
    if not APPS_ROOT.is_dir():
        return apps
    for app_dir in sorted(APPS_ROOT.iterdir(), key=lambda item: item.name.lower()):
        if not app_dir.is_dir():
            continue
        value = app_manifest(app_dir)
        if not value or value.get("hidden") is True:
            continue
        app_id = value["id"]
        apps.append({
            "id": app_id,
            "name": str(value.get("name") or app_id),
            "category": str(value.get("category") or "Apps"),
            "iconUrl": f"/api/apps/icon/{app_id}",
        })
    apps.sort(key=lambda item: (item["category"].lower(), item["name"].lower(), item["id"]))
    return apps


def app_icon_path(app_id: str) -> Path | None:
    app_id = safe_app_id(app_id)
    if not app_id:
        return None
    app_dir = APPS_ROOT / app_id
    value = app_manifest(app_dir) if app_dir.is_dir() else None
    icon = str((value or {}).get("icon") or app_id).strip()
    candidates: list[Path] = []
    if icon:
        raw = Path(icon[7:] if icon.startswith("file://") else icon)
        if raw.is_absolute():
            candidates.append(raw)
        else:
            candidates.extend([app_dir / raw, app_dir / "assets" / "icons" / raw])
        if raw.suffix == "":
            for ext in (".png", ".webp", ".svg", ".jpg", ".jpeg"):
                candidates.extend([
                    THEME_ICON_ROOT / f"{icon}{ext}",
                    app_dir / f"{icon}{ext}",
                    app_dir / "assets" / "icons" / f"{icon}{ext}",
                ])
    for ext in (".png", ".webp", ".svg", ".jpg", ".jpeg"):
        candidates.append(THEME_ICON_ROOT / f"{app_id}{ext}")
    for candidate in candidates:
        try:
            resolved = candidate.resolve(strict=True)
            resolved.relative_to(ROOT)
        except (OSError, ValueError):
            continue
        if resolved.is_file() and resolved.stat().st_size <= 8 * 1024 * 1024:
            return resolved
    return None

class Handler(BaseHTTPRequestHandler):
    server_version="NeutronOSRemoteController/4.0"
    def setup(self):
        super().setup()
        self.connection.settimeout(SOCKET_TIMEOUT_SECONDS)
    def peer_identity(self): return str(self.client_address[0])
    def identity(self): return self.peer_identity()
    def token(self):
        value=self.headers.get("Authorization",""); return value[7:].strip() if value.startswith("Bearer ") else ""
    def authenticate(self): return TOKENS.authenticate(self.token())
    def basic_credentials(self):
        value = self.headers.get("Authorization", "")
        if not value.startswith("Basic "):
            return None
        try:
            decoded = base64.b64decode(value[6:].strip(), validate=True).decode("utf-8")
            username, password = decoded.split(":", 1)
        except (ValueError, UnicodeDecodeError):
            return None
        return username, password
    def pam_cookie(self):
        raw = self.headers.get("Cookie", "")
        for part in raw.split(";"):
            key, sep, value = part.strip().partition("=")
            if sep and key == "__Host-NeutronRemoteFallback":
                return value
        return ""
    def pam_session_record(self):
        token = self.pam_cookie()
        if not token:
            return None
        now = int(time.time())
        with PAM_SESSION_LOCK:
            expired = [k for k,v in PAM_SESSIONS.items() if int(v.get("expiresAt",0)) <= now]
            for key in expired:
                PAM_SESSIONS.pop(key, None)
            value = PAM_SESSIONS.get(token)
            return dict(value) if value else None
    def require_pam(self):
        record = self.pam_session_record()
        if record:
            return record
        allowed, retry = PAM_LIMIT.allowed("global")
        if not allowed:
            self.send_json(429, {"ok":False,"error":"fallback authentication backoff","retryAfter":retry})
            AUDIT.write("fallback_authentication_lockout", {"identity":self.peer_identity()})
            return None
        credentials = self.basic_credentials()
        if not credentials:
            PAM_LIMIT.failure("global")
            self.send_response(401)
            self.send_header("WWW-Authenticate", f'Basic realm="{FALLBACK_REALM}", charset="UTF-8"')
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        username, password = credentials
        if not pam_agent_auth(username, password):
            PAM_LIMIT.failure("global")
            AUDIT.write("fallback_authentication_failure", {"identity":self.peer_identity(),"username":username})
            self.send_response(401)
            self.send_header("WWW-Authenticate", f'Basic realm="{FALLBACK_REALM}", charset="UTF-8"')
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None
        PAM_LIMIT.success("global")
        token = secrets.token_urlsafe(32)
        record = {"id":f"pam:{username}","deviceId":f"local-account:{username}","username":username,"expiresAt":int(time.time())+PAM_SESSION_TTL}
        with PAM_SESSION_LOCK:
            PAM_SESSIONS[token] = record
        self._pam_set_cookie = token
        AUDIT.write("fallback_authentication_success", {"identity":self.peer_identity(),"username":username})
        return record
    def send_bytes(self,status,data,content_type):
        self.send_response(status); self.send_header("Content-Type",content_type); self.send_header("Content-Length",str(len(data))); self.send_header("Cache-Control","no-store"); self.send_header("X-Content-Type-Options","nosniff"); self.send_header("Referrer-Policy","no-referrer"); self.send_header("Strict-Transport-Security","max-age=31536000")
        token = getattr(self, "_pam_set_cookie", "")
        if token:
            self.send_header("Set-Cookie", f"__Host-NeutronRemoteFallback={token}; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age={PAM_SESSION_TTL}")
        self.end_headers()
        if data: self.wfile.write(data)
    def send_json(self,status,value): self.send_bytes(status,json.dumps(value,separators=(",",":")).encode(),"application/json")
    def body(self):
        length=safe_int(self.headers.get("Content-Length","0"),-1)
        if length < 0 or length > MAX_BODY_BYTES: raise OverflowError
        value=json.loads(self.rfile.read(length).decode()) if length else {}
        if not isinstance(value,dict): raise ValueError("request must be an object")
        return value
    def require_auth(self):
        if AUTH_MODE == "pam":
            return self.require_pam()
        identity=self.identity(); allowed,retry=AUTH_LIMIT.allowed(identity)
        if not allowed: self.send_json(429,{"ok":False,"error":"authentication backoff","retryAfter":retry}); AUDIT.write("authentication_lockout",{"identity":identity}); return None
        record=self.authenticate()
        if not record: AUTH_LIMIT.failure(identity); self.send_json(401,{"ok":False,"error":"authentication required"}); AUDIT.write("authentication_failure",{"identity":identity}); return None
        AUTH_LIMIT.success(identity); return record
    def do_GET(self):
        parsed=urlparse(self.path)
        if parsed.path == "/api/public/status":
            self.send_json(200,{"ok":True,"ready":True,"encrypted":True,"authMode":AUTH_MODE,"version":"4.0-ui2"})
            return

        fallback_record = None
        if AUTH_MODE == "pam":
            fallback_record = self.require_pam()
            if not fallback_record:
                return

        if parsed.path in {"/api/health","/api/status"}:
            record=fallback_record or self.require_auth()
            if record:
                focus = bridge_request("GET", "/focus")
                self.send_json(200,{"ok":True,"ready":True,"encrypted":True,"deviceId":record["deviceId"],"authMode":AUTH_MODE,
                                    "textInputActive":bool(focus.get("textInputActive"))})
            return

        if parsed.path == "/api/apps":
            record=fallback_record or self.require_auth()
            if record:
                self.send_json(200,{"ok":True,"apps":discover_apps()})
            return

        if parsed.path.startswith("/api/apps/icon/"):
            record=fallback_record or self.require_auth()
            if not record:
                return
            icon=app_icon_path(parsed.path[len("/api/apps/icon/"):])
            if not icon:
                self.send_json(404,{"ok":False,"error":"app icon not found"}); return
            self.send_bytes(200,icon.read_bytes(),mimetypes.guess_type(str(icon))[0] or "application/octet-stream")
            return

        if parsed.path == "/api/keyboard/status":
            record=fallback_record or self.require_auth()
            if record:
                focus=bridge_request("GET","/focus")
                self.send_json(200,{"ok":True,"textInputActive":bool(focus.get("textInputActive")),
                                    "nativeKeyboardReady":Path(INPUT_SOCKET).exists()})
            return

        file=static_file(parsed.path)
        if not file or not file.is_file(): self.send_json(404,{"ok":False,"error":"not found"}); return
        self.send_bytes(200,file.read_bytes(),mimetypes.guess_type(str(file))[0] or "application/octet-stream")

    def do_POST(self):
        parsed=urlparse(self.path); identity=self.identity()
        try: value=self.body()
        except OverflowError: self.send_json(413,{"ok":False,"error":"request too large"}); return
        except (UnicodeDecodeError,json.JSONDecodeError,ValueError): self.send_json(400,{"ok":False,"error":"malformed request"}); return

        if parsed.path == "/api/login":
            if AUTH_MODE != "token":
                self.send_json(403,{"ok":False,"error":"account bootstrap is available only on the Tailscale controller"}); return
            allowed,retry=PAM_LIMIT.allowed("login:"+identity)
            if not allowed:
                self.send_json(429,{"ok":False,"error":"account authentication backoff","retryAfter":retry}); return
            username=str(value.get("username","")).strip(); password=str(value.get("password",""))
            if not pam_agent_auth(username,password):
                PAM_LIMIT.failure("login:"+identity); AUDIT.write("controller_account_login_failure",{"identity":identity,"username":username})
                self.send_json(401,{"ok":False,"error":"Linux username or password is incorrect"}); return
            PAM_LIMIT.success("login:"+identity)
            token,record=TOKENS.issue(f"account:{username}")
            AUDIT.write("controller_account_login_success",{"identity":identity,"username":username,"tokenId":record["id"]})
            self.send_json(201,{"ok":True,"token":token,"tokenId":record["id"],"expiresAt":record["expiresAt"]}); return

        fallback_record = None
        if AUTH_MODE == "pam":
            fallback_record = self.require_pam()
            if not fallback_record:
                return

        if parsed.path=="/api/pair":
            if AUTH_MODE == "pam":
                self.send_json(403,{"ok":False,"error":"pairing is disabled in local fallback mode"})
                return
            identity=self.peer_identity()
            allowed,retry=PAIR_LIMIT.allowed(identity)
            global_allowed,global_retry=PAIR_GLOBAL_LIMIT.allowed("global")
            if not allowed or not global_allowed:
                self.send_json(429,{"ok":False,"error":"pairing backoff","retryAfter":max(retry,global_retry)}); return
            device=str(value.get("deviceId","")).strip(); code=str(value.get("code","")).strip()
            if not device or not PAIRING.consume(code): PAIR_LIMIT.failure(identity); PAIR_GLOBAL_LIMIT.failure("global"); AUDIT.write("pairing_denied",{"identity":identity,"deviceId":device}); self.send_json(403,{"ok":False,"error":"pairing code is incorrect or expired"}); return
            token,record=TOKENS.issue(device); PAIR_LIMIT.success(identity); AUDIT.write("pairing_approved",{"deviceId":device,"tokenId":record["id"]}); self.send_json(201,{"ok":True,"token":token,"tokenId":record["id"],"expiresAt":record["expiresAt"]}); return

        record=fallback_record or self.require_auth()
        if not record: return

        if parsed.path == "/api/apps/launch":
            app_id=safe_app_id(value.get("appId"))
            if not app_id or not (APPS_ROOT/app_id/"app.json").is_file():
                self.send_json(404,{"ok":False,"error":"app is not installed"}); return
            response=bridge_request("POST","/command",{"op":"launchApp","appId":app_id})
            if not response.get("ok"):
                self.send_json(503,{"ok":False,"error":response.get("error","UI bridge unavailable")}); return
            AUDIT.write("remote_app_launch",{"deviceId":record["deviceId"],"appId":app_id})
            self.send_json(202,{"ok":True,"queued":True,"appId":app_id}); return

        if parsed.path == "/api/keyboard/input":
            op=str(value.get("op","")).strip().lower()
            payload={"op":op}
            if op == "text":
                text=str(value.get("text",""))
                if len(text)>4096: self.send_json(413,{"ok":False,"error":"text input too large"}); return
                payload["text"]=text
            elif op == "backspace": payload["count"]=max(1,min(128,safe_int(value.get("count"),1)))
            elif op not in {"enter","tab"}: self.send_json(400,{"ok":False,"error":"unsupported keyboard operation"}); return
            focus=bridge_request("GET","/focus")
            if not focus.get("textInputActive"):
                self.send_json(409,{"ok":False,"error":"NeutronOS does not currently have an editable text field focused"}); return
            response=remote_input(payload)
            if not response.get("ok"):
                self.send_json(503,response); return
            self.send_json(200,response); return

        if parsed.path not in {"/event","/api/event","/api/controller/event"}: self.send_json(404,{"ok":False,"error":"not found"}); return
        allowed,retry=COMMAND_LIMIT.allowed(record["id"])
        if not allowed: COMMAND_LIMIT.failure(record["id"]); self.send_json(429,{"ok":False,"error":"command rate exceeded","retryAfter":retry}); return
        COMMAND_LIMIT.failure(record["id"])
        if not REPLAY.accept(record["id"],str(value.get("nonce", "")),safe_int(value.get("time"),0)):
            self.send_json(409,{"ok":False,"error":"stale or replayed request"}); AUDIT.write("connection_rejected",{"deviceId":record["deviceId"],"reason":"replay"}); return
        try: event=write_event(value.get("button",value.get("action")),value.get("state","press"),value.get("x",0),value.get("y",0),value.get("time")); self.send_json(200,{"ok":True,"event":event})
        except ValueError as exc: self.send_json(400,{"ok":False,"error":str(exc)})
    def log_message(self,fmt,*args): pass

class BoundedThreadingHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 32

    def __init__(self, *args, **kwargs):
        self._slots = threading.BoundedSemaphore(max(1, MAX_CONCURRENT_REQUESTS))
        super().__init__(*args, **kwargs)

    def process_request(self, request, client_address):
        if not self._slots.acquire(blocking=False):
            try:
                request.shutdown(2)
            except OSError:
                pass
            self.shutdown_request(request)
            AUDIT.write("connection_rejected", {"identity": str(client_address[0]), "reason": "concurrency-limit"})
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self._slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._slots.release()


def main():
    if AUTH_MODE not in {"token", "pam"}:
        raise RuntimeError("unsupported remote authentication mode")
    if TLS_CERT.is_file() and TLS_KEY.is_file():
        cert, key = TLS_CERT, TLS_KEY
    else:
        cert, key = STATE_DIR/"tls.crt", STATE_DIR/"tls.key"
        ensure_local_certificate(cert,key)
    server=BoundedThreadingHTTPServer((HOST,PORT),Handler); context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.minimum_version=ssl.TLSVersion.TLSv1_2; context.load_cert_chain(cert,key); server.socket=context.wrap_socket(server.socket,server_side=True)
    AUDIT.write("service_started",{"host":HOST,"port":PORT,"encrypted":True,"authMode":AUTH_MODE}); server.serve_forever(); return 0

if __name__=="__main__": raise SystemExit(main())
