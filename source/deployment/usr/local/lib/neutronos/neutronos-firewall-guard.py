#!/usr/bin/env python3
"""Independent NeutronOS firewall life-support guard.

This service is intentionally separate from neutron-securityd. Its only job is
keeping a conservative kernel firewall alive, restoring NeutronOS-owned tables
when they disappear, and publishing a tiny health record that other security
components can consume. It never flushes the global nftables ruleset.
"""
from __future__ import annotations

import argparse
import ipaddress
import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from neutronos_firewall import (
    BASE_TABLE,
    CONTAINMENT_TABLE,
    LIFELINE_TABLE,
    SECURITY_TABLE,
    FirewallActivator,
    containment_rules,
    emergency_table_script,
    lifeline_monitor_rules,
    lifeline_rules,
    security_table_rules,
    write_status,
)

STATE_ROOT = Path(os.environ.get("NEUTRONOS_SECURITY_CORE_STATE", "/var/lib/neutronos/security-core"))
FIREWALL_DIR = STATE_ROOT / "firewall"
STATUS_PATH = STATE_ROOT / "firewall-state.json"
BANS_PATH = STATE_ROOT / "bans.json"
RESPONSE_STATE_PATH = STATE_ROOT / "response-state.json"
FACTORY_POLICY_PATH = Path(os.environ.get("NEUTRONOS_FIREWALL_FACTORY_POLICY", "/etc/neutronos/firewall-normal.nft"))
CHECK_SECONDS = 5
STALE_SECONDS = 20
STOP = False


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def log(message: str) -> None:
    print(f"neutronos-firewall-guard: {message}", flush=True)


def load_json(path: Path, fallback: Any) -> Any:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        return fallback


class Guard:
    def __init__(self, nft: str | None = None) -> None:
        self.nft = nft or shutil.which("nft") or "/usr/sbin/nft"
        self.activator = FirewallActivator(FIREWALL_DIR, self.nft)
        self.last_repair = ""
        self.last_error = ""
        self.repair_count = 0

    def nft_available(self) -> bool:
        return Path(self.nft).is_file() and os.access(self.nft, os.X_OK)

    def table_text(self, table: str) -> str:
        try:
            result = subprocess.run(
                [self.nft, "list", "table", "inet", table],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.SubprocessError):
            return ""
        return result.stdout if result.returncode == 0 else ""

    @staticmethod
    def drop_policy_table(text: str) -> bool:
        lowered = text.lower()
        return (
            "hook input" in lowered
            and "hook forward" in lowered
            and lowered.count("policy drop") >= 2
            and "policy accept" in lowered
        )

    def lifeline_health(self) -> tuple[bool, str]:
        text = self.table_text(LIFELINE_TABLE)
        lowered = text.lower()
        if not text or "neutronos-life-support" not in lowered:
            return False, "missing"
        if self.drop_policy_table(text):
            return True, "emergency"
        if ("hook input" in lowered and "hook forward" in lowered
                and lowered.count("policy accept") >= 2
                and "neutronos-life-support-sentinel" in lowered):
            return True, "monitor"
        return False, "invalid"

    def base_health(self) -> tuple[bool, str]:
        text = self.table_text(BASE_TABLE)
        if not self.drop_policy_table(text):
            return False, "missing-or-invalid"
        if "neutronos-life-support" in text:
            return True, "emergency"
        return True, "policy"

    def security_healthy(self) -> bool:
        text = self.table_text(SECURITY_TABLE).lower()
        return (
            "banned_v4" in text
            and "banned_v6" in text
            and "hook input" in text
            and "@banned_v4" in text
            and "@banned_v6" in text
        )

    def containment_expected(self) -> bool:
        state = load_json(RESPONSE_STATE_PATH, {})
        return isinstance(state, dict) and bool(state.get("containmentActive", False))

    def containment_healthy(self) -> bool:
        text = self.table_text(CONTAINMENT_TABLE).lower()
        return "hook input" in text and "policy drop" in text

    def active_bans(self) -> tuple[list[str], list[str]]:
        raw = load_json(BANS_PATH, {})
        if not isinstance(raw, dict):
            return [], []
        now = datetime.now(timezone.utc)
        v4: list[str] = []
        v6: list[str] = []
        for address, record in raw.items():
            if not isinstance(record, dict):
                continue
            expires_raw = str(record.get("expiresAt") or "").strip()
            if expires_raw:
                try:
                    expires = datetime.fromisoformat(expires_raw.replace("Z", "+00:00"))
                    if expires.tzinfo is None:
                        expires = expires.replace(tzinfo=timezone.utc)
                    if expires.astimezone(timezone.utc) <= now:
                        continue
                except ValueError:
                    continue
            try:
                parsed = ipaddress.ip_address(str(address))
            except ValueError:
                continue
            (v4 if parsed.version == 4 else v6).append(str(parsed))
        return sorted(set(v4)), sorted(set(v6))

    def apply_named(self, name: str, rules: str, remember: bool = False) -> bool:
        result = self.activator.apply(rules, remember=remember)
        if result.get("success"):
            self.last_repair = f"{utc_now()} {name}"
            self.last_error = ""
            self.repair_count += 1
            log(f"restored {name}")
            return True
        self.last_error = f"{name}: {result.get('error', 'unknown')} {result.get('detail', '')}".strip()
        log(f"FAILED to restore {name}: {self.last_error}")
        return False

    def ensure_lifeline(self, emergency: bool) -> tuple[bool, str]:
        healthy, mode = self.lifeline_health()
        wanted = "emergency" if emergency else "monitor"
        if healthy and mode == wanted:
            return True, mode
        rules = lifeline_rules() if emergency else lifeline_monitor_rules()
        if not self.apply_named(f"lifeline-{wanted}", rules, remember=False):
            return healthy, mode
        return self.lifeline_health()

    def ensure_base(self) -> tuple[bool, str]:
        healthy, mode = self.base_health()
        if healthy and mode == "policy":
            return True, mode

        # An emergency policy is protection, not success. Always try to promote
        # DEGRADED/emergency state back to the last known-good normal policy.
        known_good = self.activator.restore_known_good()
        if known_good.get("success"):
            restored, restored_mode = self.base_health()
            if restored and restored_mode == "policy":
                self.last_repair = f"{utc_now()} base-known-good"
                self.last_error = ""
                self.repair_count += 1
                log("restored normal base firewall from known-good policy")
                return True, restored_mode

        # The factory normal policy is immutable OS-owned recovery material. It
        # is used when mutable known-good state is absent/corrupt, then becomes
        # the new known-good snapshot after a successful atomic activation.
        try:
            factory_rules = FACTORY_POLICY_PATH.read_text(encoding="utf-8")
        except OSError:
            factory_rules = ""
        if factory_rules:
            if self.apply_named("base-factory-policy", factory_rules, remember=True):
                restored, restored_mode = self.base_health()
                if restored and restored_mode == "policy":
                    return True, restored_mode

        # If an emergency table was already enforcing traffic, keep it. If no
        # valid base policy exists at all, install the conservative emergency
        # table before returning. Public inbound must never fail open.
        if healthy and mode == "emergency":
            return True, mode
        if self.apply_named("base-emergency", emergency_table_script(), remember=False):
            restored, restored_mode = self.base_health()
            return restored, "emergency" if restored else restored_mode
        return False, "missing"

    def ensure_security(self) -> bool:
        if self.security_healthy():
            return True
        v4, v6 = self.active_bans()
        return self.apply_named("security-ban-table", security_table_rules(v4, v6), remember=False) and self.security_healthy()

    def ensure_containment(self) -> tuple[bool, bool]:
        expected = self.containment_expected()
        if not expected:
            return False, True
        if self.containment_healthy():
            return True, True
        repaired = self.apply_named("containment", containment_rules(), remember=False)
        return True, repaired and self.containment_healthy()

    def check_once(self) -> dict[str, Any]:
        if not self.nft_available():
            state = {
                "protectionState": "CRITICAL",
                "firewallActive": False,
                "lifelineActive": False,
                "lifelineMode": "missing",
                "lifelineEnforcing": False,
                "baseTableActive": False,
                "baseMode": "missing",
                "securityTableActive": False,
                "containmentExpected": self.containment_expected(),
                "containmentActive": False,
                "lastRepair": self.last_repair,
                "lastError": "nft executable is unavailable",
                "repairCount": self.repair_count,
                "updatedAt": utc_now(),
            }
            write_status(STATUS_PATH, state)
            return state

        # Check the normal policy first. If it is missing/corrupt, put the
        # fail-closed lifeline in place *before* any recovery attempt. Once a
        # valid base policy exists, return the lifeline to non-blocking monitor
        # mode so intentional service exposure remains governed by that policy.
        base_before, base_mode_before = self.base_health()
        lifeline, lifeline_mode = self.ensure_lifeline(emergency=not base_before)
        if not lifeline and not base_before:
            base, base_mode = False, "missing"
        elif base_before and base_mode_before == "policy":
            base, base_mode = True, "policy"
        else:
            # A present emergency table is still degraded protection, not a
            # healthy normal policy. Actively promote it from known-good/factory
            # state instead of treating mere table existence as success.
            base, base_mode = self.ensure_base()

        if base:
            monitor_ok, monitor_mode = self.ensure_lifeline(emergency=False)
            if monitor_ok:
                lifeline, lifeline_mode = monitor_ok, monitor_mode

        firewall_active = bool(base or (lifeline and lifeline_mode == "emergency"))
        security = self.ensure_security() if firewall_active else False
        containment_expected, containment_ok = self.ensure_containment() if firewall_active else (self.containment_expected(), False)

        if not firewall_active:
            protection = "CRITICAL"
        elif containment_expected and not containment_ok:
            protection = "CRITICAL"
        elif not base or not security or base_mode == "emergency":
            protection = "DEGRADED"
        else:
            protection = "SECURE"

        state = {
            "protectionState": protection,
            "firewallActive": firewall_active,
            "lifelineActive": bool(lifeline),
            "lifelineMode": lifeline_mode,
            "lifelineEnforcing": bool(lifeline and lifeline_mode == "emergency"),
            "baseTableActive": bool(base),
            "baseMode": base_mode,
            "securityTableActive": bool(security),
            "containmentExpected": bool(containment_expected),
            "containmentActive": bool(containment_expected and containment_ok),
            "lastRepair": self.last_repair,
            "lastError": self.last_error,
            "repairCount": self.repair_count,
            "updatedAt": utc_now(),
        }
        write_status(STATUS_PATH, state)
        return state



def remote_safe_readonly(max_age_seconds: int = 20) -> tuple[bool, dict[str, Any]]:
    """Read the guard heartbeat without mutating firewall state.

    This is used by the Remote Systems systemd ExecStartPre inside the remote
    broker's read-only sandbox. The always-on guard remains responsible for
    direct kernel verification and state publication.
    """
    state = load_json(STATUS_PATH, {})
    if not isinstance(state, dict):
        return False, {}
    if not bool(state.get("firewallActive", False)):
        return False, state
    if str(state.get("protectionState") or "").upper() == "CRITICAL":
        return False, state
    try:
        updated = datetime.fromisoformat(str(state.get("updatedAt") or "").replace("Z", "+00:00"))
        if updated.tzinfo is None:
            updated = updated.replace(tzinfo=timezone.utc)
        age = (datetime.now(timezone.utc) - updated.astimezone(timezone.utc)).total_seconds()
    except (TypeError, ValueError):
        return False, state
    return age <= max_age_seconds, state


def remote_service_active() -> bool:
    return subprocess.run(
        ["systemctl", "is-active", "--quiet", "neutron-remote-service.service"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        timeout=5,
    ).returncode == 0


def stop_remote_service_if_critical(state: dict[str, Any]) -> None:
    """Fail closed for NeutronOS remote exposure when kernel protection is lost.

    Remote Systems remains an optional package, but its broker is the OS-wide
    authority for NeutronOS remote providers. A CRITICAL firewall state means
    there is no verified fail-closed kernel policy, so keeping that broker alive
    would allow new remote leases during the exact condition in which network
    exposure is least trustworthy.
    """
    if str(state.get("protectionState") or "").upper() != "CRITICAL":
        return
    try:
        if not remote_service_active():
            return
        result = subprocess.run(
            ["systemctl", "stop", "neutron-remote-service.service"],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
        if result.returncode == 0:
            log("stopped neutron-remote-service.service because firewall protection is CRITICAL")
        else:
            log("FAILED to stop neutron-remote-service.service during CRITICAL firewall state: " + result.stderr.strip())
    except (OSError, subprocess.SubprocessError) as exc:
        log(f"FAILED to stop remote broker during CRITICAL firewall state: {exc}")

def self_test() -> int:
    checks = {
        "lifelineNoGlobalFlush": "flush ruleset" not in lifeline_rules().lower(),
        "lifelineDropPolicies": lifeline_rules().lower().count("policy drop") >= 2,
        "lifelineMonitorNoGlobalFlush": "flush ruleset" not in lifeline_monitor_rules().lower(),
        "lifelineMonitorNonBlocking": lifeline_monitor_rules().lower().count("policy accept") >= 2,
        "emergencyNoGlobalFlush": "flush ruleset" not in emergency_table_script().lower(),
        "securityNoGlobalFlush": "flush ruleset" not in security_table_rules().lower(),
        "containmentNoGlobalFlush": "flush ruleset" not in containment_rules().lower(),
        "factoryPolicyConfigured": str(FACTORY_POLICY_PATH).endswith("/etc/neutronos/firewall-normal.nft"),
    }
    print(json.dumps({"ok": all(checks.values()), "checks": checks}, sort_keys=True))
    return 0 if all(checks.values()) else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--apply-once", action="store_true")
    parser.add_argument("--require-remote-safe", action="store_true")
    parser.add_argument("--check-seconds", type=int, default=CHECK_SECONDS)
    args = parser.parse_args()
    if args.self_test:
        return self_test()

    guard = Guard()
    if args.require_remote_safe:
        safe, state = remote_safe_readonly()
        print(json.dumps({"remoteSafe": safe, **state}, sort_keys=True))
        return 0 if safe else 1
    if args.apply_once:
        state = guard.check_once()
        stop_remote_service_if_critical(state)
        print(json.dumps(state, sort_keys=True))
        return 0 if state.get("firewallActive") else 1

    def stop(_signum: int, _frame: Any) -> None:
        global STOP
        STOP = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    interval = max(2, min(30, int(args.check_seconds)))
    while not STOP:
        state = guard.check_once()
        stop_remote_service_if_critical(state)
        for _ in range(interval * 10):
            if STOP:
                break
            time.sleep(0.1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
