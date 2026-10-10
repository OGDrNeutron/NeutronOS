"""Shared offline-capable security primitives for Patch 78 remote services."""
from __future__ import annotations
import hashlib, hmac, json, os, secrets, subprocess, tempfile, threading, time
from pathlib import Path
from typing import Any


def atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, indent=2, sort_keys=True); handle.write("\n")
            handle.flush(); os.fsync(handle.fileno())
        os.chmod(name, 0o600); os.replace(name, path)
    finally:
        try: os.unlink(name)
        except FileNotFoundError: pass


class AuditLog:
    SECRET_KEYS = {"token", "secret", "pin", "pairingCode", "authorization"}
    def __init__(self, path: Path): self.path = path
    def write(self, event: str, detail: dict[str, Any]) -> None:
        clean = {key: ("[REDACTED]" if key.lower() in {v.lower() for v in self.SECRET_KEYS} else value)
                 for key, value in detail.items()}
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({"timestamp": time.time(), "event": event, "detail": clean},
                                    separators=(",", ":"), sort_keys=True) + "\n")
        os.chmod(self.path, 0o600)


class RateLimiter:
    def __init__(self, limit: int = 5, window: int = 60, max_backoff: int = 300):
        self.limit, self.window, self.max_backoff = limit, window, max_backoff
        self._events: dict[str, list[float]] = {}; self._blocked: dict[str, float] = {}; self._lock = threading.Lock()
    def allowed(self, identity: str, now: float | None = None) -> tuple[bool, int]:
        now = time.monotonic() if now is None else now
        with self._lock:
            until = self._blocked.get(identity, 0)
            if until > now: return False, max(1, int(until - now))
            events = [event for event in self._events.get(identity, []) if now - event <= self.window]
            self._events[identity] = events
            return True, 0
    def failure(self, identity: str, now: float | None = None) -> int:
        now = time.monotonic() if now is None else now
        with self._lock:
            events = [event for event in self._events.get(identity, []) if now - event <= self.window] + [now]
            self._events[identity] = events
            if len(events) < self.limit: return 0
            delay = min(self.max_backoff, 2 ** min(8, len(events) - self.limit + 1))
            self._blocked[identity] = now + delay
            return delay
    def success(self, identity: str) -> None:
        with self._lock: self._events.pop(identity, None); self._blocked.pop(identity, None)


class ReplayGuard:
    def __init__(self, window_seconds: int = 30, maximum: int = 4096):
        self.window, self.maximum = window_seconds, maximum
        self._seen: dict[str, float] = {}; self._lock = threading.Lock()
    def accept(self, identity: str, nonce: str, timestamp_ms: int, now: float | None = None) -> bool:
        now = time.time() if now is None else now
        if not nonce or len(nonce) > 128 or abs(now - timestamp_ms / 1000.0) > self.window: return False
        key = hashlib.sha256((identity + "\0" + nonce).encode()).hexdigest()
        with self._lock:
            self._seen = {item: stamp for item, stamp in self._seen.items() if now - stamp <= self.window}
            if key in self._seen: return False
            if len(self._seen) >= self.maximum:
                oldest = min(self._seen, key=self._seen.get); self._seen.pop(oldest, None)
            self._seen[key] = now; return True


class TokenStore:
    def __init__(self, path: Path, lifetime: int = 30 * 24 * 3600):
        self.path, self.lifetime = path, lifetime
        self._lock = threading.Lock()
    def _load(self) -> dict[str, Any]:
        try: value = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError): value = {"schema": 1, "tokens": []}
        return value if isinstance(value, dict) and isinstance(value.get("tokens"), list) else {"schema": 1, "tokens": []}
    @staticmethod
    def _digest(token: str, salt: str) -> str:
        return hashlib.sha256(bytes.fromhex(salt) + token.encode()).hexdigest()
    def issue(self, device_id: str, now: int | None = None) -> tuple[str, dict[str, Any]]:
        if not device_id or len(device_id) > 160: raise ValueError("invalid device identity")
        now = int(time.time()) if now is None else now; token = secrets.token_urlsafe(48); salt = secrets.token_hex(16)
        record = {"id": secrets.token_hex(16), "deviceId": device_id, "salt": salt,
                  "digest": self._digest(token, salt), "createdAt": now, "expiresAt": now + self.lifetime,
                  "revoked": False}
        with self._lock:
            value = self._load(); value["tokens"].append(record); atomic_json(self.path, value)
        return token, {key: value for key, value in record.items() if key not in {"salt", "digest"}}
    def authenticate(self, token: str, now: int | None = None) -> dict[str, Any] | None:
        now = int(time.time()) if now is None else now
        if not token or len(token) > 512: return None
        for record in self._load()["tokens"]:
            if record.get("revoked") or int(record.get("expiresAt", 0)) <= now: continue
            try: matches = hmac.compare_digest(self._digest(token, str(record["salt"])), str(record["digest"]))
            except (KeyError, ValueError): matches = False
            if matches: return {key: value for key, value in record.items() if key not in {"salt", "digest"}}
        return None
    def revoke(self, token_id: str) -> bool:
        with self._lock:
            value = self._load(); changed = False
            for record in value["tokens"]:
                if hmac.compare_digest(str(record.get("id", "")), token_id): record["revoked"] = True; changed = True
            if changed: atomic_json(self.path, value)
            return changed
    def rotate(self, token_id: str, device_id: str) -> tuple[str, dict[str, Any]]:
        if not self.revoke(token_id): raise ValueError("unknown token")
        return self.issue(device_id)


class PairingCodes:
    def __init__(self, path: Path, ttl: int = 300):
        self.path, self.ttl = path, ttl
        self._lock = threading.Lock()
    def create(self, now: int | None = None) -> str:
        now = int(time.time()) if now is None else now
        code = f"{secrets.randbelow(1000000):06d}"
        salt = secrets.token_hex(16)
        with self._lock:
            atomic_json(self.path, {"salt": salt, "digest": TokenStore._digest(code, salt), "expiresAt": now + self.ttl})
        return code

    def consume(self, code: str, now: int | None = None) -> bool:
        now = int(time.time()) if now is None else now
        with self._lock:
            try:
                value = json.loads(self.path.read_text())
                valid = int(value["expiresAt"]) > now and hmac.compare_digest(
                    TokenStore._digest(code, value["salt"]), value["digest"])
            except (OSError, KeyError, ValueError, json.JSONDecodeError):
                valid = False
            if not valid:
                return False
            try:
                self.path.unlink()
            except FileNotFoundError:
                return False
            return True


def ensure_local_certificate(cert: Path, key: Path, common_name: str = "neutronos.local") -> None:
    if cert.is_file() and key.is_file(): return
    cert.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    openssl = "/usr/bin/openssl"
    result = subprocess.run([openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                             "-keyout", str(key), "-out", str(cert), "-days", "825",
                             "-subj", f"/CN={common_name}", "-addext", "subjectAltName=DNS:neutronos.local"],
                            capture_output=True, timeout=30)
    if result.returncode != 0: raise RuntimeError("local TLS certificate generation failed")
    os.chmod(key, 0o600); os.chmod(cert, 0o644)


def resolve_inside(root: Path, requested: str, *, must_exist: bool = True) -> Path:
    root = root.resolve(strict=True)
    if not requested or "\x00" in requested: raise ValueError("malformed path")
    candidate = Path(requested)
    candidate = candidate if candidate.is_absolute() else root / candidate
    resolved = candidate.resolve(strict=must_exist)
    try: resolved.relative_to(root)
    except ValueError as exc: raise PermissionError("path is outside an allowed media root") from exc
    return resolved
