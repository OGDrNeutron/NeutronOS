#!/usr/bin/env python3
"""Package-owned NeutronOS bridge for the official Codex app-server.

The bridge speaks bounded JSONL to NeutronShell on stdin/stdout and speaks the
official Codex app-server JSONL protocol to the external Codex executable. It
does not persist credentials; ChatGPT and API-key login are delegated to Codex.
"""

from __future__ import annotations

import json
import os
import pathlib
import queue
import shutil
import subprocess
import sys
import threading
import time
from typing import Any

MAX_LINE = 4 * 1024 * 1024
APP_VERSION = "1.0.0-alpha.1"


class Bridge:
    def __init__(self) -> None:
        self.codex = self.find_codex()
        self.server: subprocess.Popen[str] | None = None
        self.requests: dict[int, str] = {}
        self.next_id = 1
        self.write_lock = threading.Lock()
        self.server_lock = threading.Lock()
        self.thread_id = ""
        self.turn_id = ""
        self.pending_prompt = ""
        self.model = ""
        self.reasoning = "medium"
        self.server_error = ""
        self.running = True

    @staticmethod
    def find_codex() -> str:
        found = shutil.which("codex")
        if found:
            return found
        home = pathlib.Path.home()
        for path in (home / ".local/bin/codex", home / ".npm-global/bin/codex"):
            if path.is_file() or path.is_symlink():
                return str(path)
        return ""

    def emit(self, kind: str, **values: Any) -> None:
        payload = {"type": kind, **values}
        encoded = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
        if len(encoded.encode("utf-8")) > MAX_LINE:
            payload = {"type": "error", "message": "Codex event exceeded bridge limit"}
            encoded = json.dumps(payload, separators=(",", ":"))
        with self.write_lock:
            sys.stdout.write(encoded + "\n")
            sys.stdout.flush()

    def status(self, stage: str, message: str = "", **extra: Any) -> None:
        self.emit("state", stage=stage, message=message, installed=bool(self.codex),
                  connected=self.server is not None and self.server.poll() is None,
                  model=self.model, reasoning=self.reasoning,
                  appVersion=APP_VERSION, **extra)

    def start(self) -> None:
        if not self.codex:
            self.status("CODEX NOT INSTALLED", "The official Codex runtime was not found.")
            return
        try:
            version = subprocess.run([self.codex, "--version"], text=True,
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     timeout=5, check=False).stdout.strip()
            self.emit("runtime", version=version or "Unknown")
        except (OSError, subprocess.TimeoutExpired):
            self.emit("runtime", version="Unknown")
        self.status("CHECKING APP-SERVER", "Starting the official local Codex app-server.")
        try:
            self.server = subprocess.Popen(
                [self.codex, "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, encoding="utf-8", bufsize=1,
                env=os.environ.copy(),
            )
        except OSError as exc:
            self.emit("error", message=f"Unable to start Codex app-server: {exc}")
            return
        threading.Thread(target=self.read_server, name="codex-app-server", daemon=True).start()
        threading.Thread(target=self.read_server_errors, name="codex-app-server-errors", daemon=True).start()
        self.request("initialize", {
            "clientInfo": {"name": "neutronos_codex", "title": "NeutronOS Codex", "version": APP_VERSION},
            "capabilities": {"experimentalApi": True},
        }, "initialize")

    def server_write(self, payload: dict[str, Any]) -> bool:
        if not self.server or not self.server.stdin or self.server.poll() is not None:
            self.emit("error", message="Codex app-server is not connected")
            return False
        encoded = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
        if len(encoded.encode("utf-8")) > MAX_LINE:
            self.emit("error", message="Request exceeded bridge limit")
            return False
        try:
            with self.server_lock:
                self.server.stdin.write(encoded + "\n")
                self.server.stdin.flush()
            return True
        except (BrokenPipeError, OSError) as exc:
            self.emit("error", message=f"Codex connection failed: {exc}")
            return False

    def request(self, method: str, params: dict[str, Any], operation: str) -> int:
        request_id = self.next_id
        self.next_id += 1
        self.requests[request_id] = operation
        self.server_write({"id": request_id, "method": method, "params": params})
        return request_id

    def notify(self, method: str, params: dict[str, Any] | None = None) -> None:
        self.server_write({"method": method, "params": params or {}})

    def read_server(self) -> None:
        assert self.server and self.server.stdout
        for raw in self.server.stdout:
            if len(raw.encode("utf-8")) > MAX_LINE:
                self.emit("error", message="Codex app-server sent an oversized message")
                continue
            try:
                message = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if isinstance(message, dict):
                self.handle_server(message)
        if self.running:
            code = self.server.poll() if self.server else -1
            detail = f": {self.server_error}" if self.server_error else ""
            self.emit("state", stage="DISCONNECTED", message=f"Codex app-server exited ({code}){detail}",
                      installed=bool(self.codex), connected=False, model=self.model,
                      reasoning=self.reasoning, appVersion=APP_VERSION)

    def read_server_errors(self) -> None:
        assert self.server and self.server.stderr
        recent: queue.Queue[str] = queue.Queue(maxsize=8)
        for raw in self.server.stderr:
            text = raw.strip()
            if text:
                self.server_error = text[:1200]
                try: recent.put_nowait(text[:1024])
                except queue.Full:
                    recent.get_nowait(); recent.put_nowait(text[:1024])

    def handle_server(self, message: dict[str, Any]) -> None:
        if "id" in message and ("result" in message or "error" in message):
            self.handle_response(message)
            return
        method = str(message.get("method", ""))
        params = message.get("params") if isinstance(message.get("params"), dict) else {}
        if "id" in message:
            command = self.command_from_approval(params)
            self.emit("approval", requestId=message["id"], method=method, command=command,
                      reason=str(params.get("reason") or "Codex requests permission to continue."),
                      details=params)
            return
        self.handle_notification(method, params)

    @staticmethod
    def command_from_approval(params: dict[str, Any]) -> str:
        for key in ("command", "cmd", "commandLine"):
            value = params.get(key)
            if isinstance(value, str): return value
            if isinstance(value, list): return " ".join(map(str, value))
        item = params.get("item")
        if isinstance(item, dict):
            value = item.get("command")
            if isinstance(value, str): return value
            if isinstance(value, list): return " ".join(map(str, value))
        return "Codex tool request"

    def handle_response(self, message: dict[str, Any]) -> None:
        request_id = int(message.get("id", 0))
        operation = self.requests.pop(request_id, "")
        if message.get("error"):
            error = message["error"]
            detail = str(error.get("message", error)) if isinstance(error, dict) else str(error)
            self.emit("error", message=f"{operation or 'Codex request'}: {detail}")
            return
        result = message.get("result") if isinstance(message.get("result"), dict) else {}
        if operation == "initialize":
            self.notify("initialized")
            self.status("CHECKING AUTHENTICATION", "Reading official Codex account state.")
            self.request("account/read", {}, "account-read")
            self.request("config/read", {}, "config-read")
            self.request("model/list", {}, "model-list")
            self.request("thread/list", {"limit": 50, "sortKey": "updated_at"}, "thread-list")
        elif operation == "account-read":
            account = result.get("account")
            authenticated = bool(account)
            if authenticated:
                self.status("READY", "Codex is authenticated and ready.", authenticated=True)
                pathlib.Path("first-run-ready").write_text(APP_VERSION + "\n", encoding="utf-8")
            else:
                self.status("CODEX SIGN-IN REQUIRED", "Use an official Codex sign-in method.", authenticated=False)
        elif operation == "config-read":
            config = result.get("config") if isinstance(result.get("config"), dict) else result
            model = config.get("model") if isinstance(config, dict) else None
            effort = config.get("model_reasoning_effort") if isinstance(config, dict) else None
            if isinstance(model, str): self.model = model
            if isinstance(effort, str): self.reasoning = effort
            self.emit("configuration", model=self.model, reasoning=self.reasoning)
        elif operation == "model-list":
            models = result.get("data") or result.get("models") or []
            self.emit("models", models=models)
        elif operation == "thread-list":
            self.emit("sessions", sessions=result.get("data") or result.get("threads") or [])
        elif operation == "thread-start":
            thread = result.get("thread") if isinstance(result.get("thread"), dict) else result
            self.thread_id = str(thread.get("id", ""))
            self.emit("session", threadId=self.thread_id)
            if self.pending_prompt: self.start_turn()
        elif operation == "thread-resume":
            thread = result.get("thread") if isinstance(result.get("thread"), dict) else result
            self.thread_id = str(thread.get("id", self.thread_id))
            self.emit("session", threadId=self.thread_id)
        elif operation == "turn-start":
            turn = result.get("turn") if isinstance(result.get("turn"), dict) else result
            self.turn_id = str(turn.get("id", ""))
            self.emit("busy", active=True, turnId=self.turn_id)
        elif operation == "turn-interrupt":
            self.emit("activity", kind="warning", title="Interrupt requested", detail="Codex is stopping the active turn.", status="warning")
        elif operation == "login-start":
            self.emit("login", loginId=result.get("loginId") or result.get("id", ""),
                      url=result.get("verificationUrl") or result.get("authUrl") or "",
                      code=result.get("userCode") or result.get("code") or "")
            self.status("WAITING FOR CHATGPT SIGN-IN", "Complete the official Codex sign-in flow.")

    def handle_notification(self, method: str, params: dict[str, Any]) -> None:
        if method in ("account/updated", "account/login/completed"):
            self.request("account/read", {}, "account-read")
            return
        if method in ("turn/completed", "turn/failed", "turn/cancelled"):
            status = "error" if "failed" in method else "success"
            self.emit("busy", active=False, turnId="")
            self.emit("activity", kind="test" if status == "success" else "error",
                      title="Codex turn completed" if status == "success" else "Codex turn failed",
                      detail=str(params.get("error") or params.get("status") or ""), status=status)
            self.turn_id = ""
            return
        item = params.get("item")
        if isinstance(item, dict):
            kind = str(item.get("type", "activity"))
            title = {
                "agentMessage": "Codex", "reasoning": "Reasoning summary",
                "commandExecution": "Command", "fileChange": "File change",
                "mcpToolCall": "Tool", "webSearch": "Web search",
            }.get(kind, kind or "Activity")
            detail = item.get("text") or item.get("command") or item.get("path") or item.get("status") or ""
            if isinstance(detail, list): detail = " ".join(map(str, detail))
            self.emit("activity", kind=kind, title=title, detail=str(detail),
                      status="success" if method.endswith("completed") else "info",
                      itemId=str(item.get("id", "")))

    def start_turn(self) -> None:
        prompt = self.pending_prompt.strip()
        self.pending_prompt = ""
        if not prompt or not self.thread_id: return
        self.request("turn/start", {
            "threadId": self.thread_id,
            "input": [{"type": "text", "text": prompt}],
            "approvalPolicy": "on-request",
            "effort": self.reasoning,
        }, "turn-start")
        self.emit("activity", kind="user", title="You", detail=prompt, status="info")

    def command(self, data: dict[str, Any]) -> None:
        action = str(data.get("action", ""))
        if action == "open":
            if self.server is None: self.start()
        elif action == "install-runtime":
            self.status("INSTALLING CODEX", "Installing the official Codex runtime for this user.")
            prefix = pathlib.Path.home() / ".local"
            try:
                result = subprocess.run(
                    ["npm", "install", "--prefix", str(prefix), "@openai/codex@latest"],
                    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300,
                    check=False,
                )
                self.codex = self.find_codex()
                if result.returncode == 0 and self.codex:
                    self.status("CHECKING APP-SERVER", "Official Codex installed. Starting app-server.")
                    self.start()
                else:
                    detail = (result.stderr or result.stdout or "Installation failed").strip()[-1200:]
                    self.emit("error", message=detail)
            except (OSError, subprocess.TimeoutExpired) as exc:
                self.emit("error", message=f"Codex installation failed: {exc}")
        elif action == "refresh":
            self.request("account/read", {}, "account-read")
            self.request("thread/list", {"limit": 50, "sortKey": "updated_at"}, "thread-list")
        elif action == "new-session":
            self.request("thread/start", {"approvalPolicy": "on-request", "sandbox": "workspace-write"}, "thread-start")
        elif action == "resume-session":
            self.thread_id = str(data.get("threadId", ""))
            self.request("thread/resume", {"threadId": self.thread_id}, "thread-resume")
        elif action == "prompt":
            self.pending_prompt = str(data.get("text", ""))
            if self.thread_id: self.start_turn()
            else: self.request("thread/start", {"approvalPolicy": "on-request", "sandbox": "workspace-write"}, "thread-start")
        elif action == "interrupt" and self.thread_id and self.turn_id:
            self.request("turn/interrupt", {"threadId": self.thread_id, "turnId": self.turn_id}, "turn-interrupt")
        elif action == "chatgpt-login":
            self.request("account/login/start", {"type": "chatgptDeviceCode"}, "login-start")
        elif action == "api-key-login":
            key = str(data.get("apiKey", ""))
            if key: self.request("account/login/start", {"type": "apiKey", "apiKey": key}, "login-start")
        elif action == "approval":
            request_id = data.get("requestId")
            decision = str(data.get("decision", "decline"))
            self.server_write({"id": request_id, "result": {"decision": decision}})
        elif action == "set-reasoning":
            value = str(data.get("effort", "medium"))
            if value in ("low", "medium", "high", "xhigh"): self.reasoning = value
            self.emit("configuration", model=self.model, reasoning=self.reasoning)
        elif action == "close":
            self.running = False
            if self.server and self.server.poll() is None: self.server.terminate()
            raise SystemExit(0)

    def run(self) -> None:
        self.emit("state", stage="CHECKING CODEX", message="Locating the official Codex runtime.",
                  installed=bool(self.codex), connected=False, model="", reasoning=self.reasoning,
                  appVersion=APP_VERSION)
        for raw in sys.stdin:
            if len(raw.encode("utf-8")) > MAX_LINE: continue
            try: data = json.loads(raw)
            except json.JSONDecodeError: continue
            if isinstance(data, dict): self.command(data)


if __name__ == "__main__":
    Bridge().run()
