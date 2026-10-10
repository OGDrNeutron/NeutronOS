"""NeutronOS nftables policy generation, atomic activation, and life-support fallback."""
from __future__ import annotations

import ipaddress
import json
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

MODES = {"normal-wifi", "ethernet", "wifi-hotspot", "lan-hotspot", "offline-roku"}
SERVICES = {"ssh", "tailscale", "jellyfin", "remote-controller", "media-optimizer"}
PORTS = {
    "ssh": [("tcp", 22)],
    "jellyfin": [("tcp", 8096)],
    "remote-controller": [("tcp", 8091)],
    "media-optimizer": [("tcp", 8787)],
}
ZONE_NAMES = {"lan", "ethernet", "hotspot-wifi", "lan-hotspot", "offline-roku", "tailscale"}

BASE_TABLE = "neutronos"
LIFELINE_TABLE = "neutronos_lifeline"
SECURITY_TABLE = "neutronos_security"
CONTAINMENT_TABLE = "neutronos_containment"
CANONICAL_FIREWALL_STATE_DIR = Path("/var/lib/neutronos/security-core/firewall")
PRIVATE_V4 = ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10")
PRIVATE_V6 = ("fc00::/7", "fe80::/10")


class FirewallPolicyError(ValueError):
    pass


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _interface(value: Any) -> str:
    value = str(value or "")
    if not value or len(value) > 15 or not all(ch.isalnum() or ch in "_.-" for ch in value):
        raise FirewallPolicyError("invalid interface name")
    return value


@dataclass(frozen=True)
class FirewallPolicy:
    mode: str
    interfaces: dict[str, str]
    services: dict[str, list[str]]
    management: dict[str, str]
    internet_forwarding: bool = False

    @classmethod
    def parse(cls, value: dict[str, Any]) -> "FirewallPolicy":
        if not isinstance(value, dict) or set(value) - {"mode", "interfaces", "services", "management", "internetForwarding"}:
            raise FirewallPolicyError("unknown firewall policy field")
        mode = str(value.get("mode", ""))
        if mode not in MODES:
            raise FirewallPolicyError("invalid network mode")
        interfaces = value.get("interfaces", {})
        if not isinstance(interfaces, dict) or set(interfaces) - ZONE_NAMES:
            raise FirewallPolicyError("invalid interface zones")
        clean_interfaces = {str(zone): _interface(name) for zone, name in interfaces.items()}
        services = value.get("services", {})
        if not isinstance(services, dict) or set(services) - SERVICES:
            raise FirewallPolicyError("unknown service")
        clean_services: dict[str, list[str]] = {}
        for service, zones in services.items():
            if not isinstance(zones, list) or not all(isinstance(z, str) and z in ZONE_NAMES for z in zones):
                raise FirewallPolicyError("invalid service zones")
            clean_services[service] = sorted(set(zones))
        management = value.get("management", {})
        if not isinstance(management, dict) or set(management) - {"interface", "source"}:
            raise FirewallPolicyError("invalid management context")
        clean_management: dict[str, str] = {}
        if management:
            clean_management["interface"] = _interface(management.get("interface"))
            try:
                clean_management["source"] = str(ipaddress.ip_address(str(management.get("source"))))
            except ValueError as exc:
                raise FirewallPolicyError("invalid management source") from exc
        return cls(mode, clean_interfaces, clean_services, clean_management,
                   bool(value.get("internetForwarding", False)))


def generate(policy_value: dict[str, Any]) -> str:
    """Generate the normal NeutronOS service policy.

    This API is retained for existing callers. The script intentionally changes
    only the NeutronOS-owned table and never flushes the global nftables ruleset.
    """
    policy = FirewallPolicy.parse(policy_value)
    lines = [
        "#!/usr/sbin/nft -f",
        f"flush table inet {BASE_TABLE}",
        f"table inet {BASE_TABLE} {{",
        " chain input {",
        "  type filter hook input priority filter; policy drop;",
        '  iifname "lo" accept',
        "  ct state established,related accept",
        "  ct state invalid drop",
        "  ip protocol icmp accept",
        "  ip6 nexthdr ipv6-icmp accept",
    ]
    if policy.management:
        lines.append(
            f'  iifname "{policy.management["interface"]}" ip saddr {policy.management["source"]} '
            'tcp dport 22 accept comment "preserve-admin"'
        )
    for service in sorted(policy.services):
        if service == "tailscale":
            for zone in policy.services[service]:
                if zone in policy.interfaces:
                    lines.append(
                        f'  iifname "{policy.interfaces[zone]}" udp dport 41641 accept comment "tailscale"'
                    )
            continue
        for zone in policy.services[service]:
            interface = policy.interfaces.get(zone)
            if not interface:
                raise FirewallPolicyError(f"service zone has no interface: {zone}")
            for protocol, port in PORTS[service]:
                lines.append(
                    f'  iifname "{interface}" {protocol} dport {port} accept comment "{service}"'
                )
    for zone in ("hotspot-wifi", "lan-hotspot", "offline-roku"):
        interface = policy.interfaces.get(zone)
        if interface:
            lines += [
                f'  iifname "{interface}" udp dport {{ 53, 67 }} accept comment "{zone}-dhcp-dns"',
                f'  iifname "{interface}" tcp dport 53 accept comment "{zone}-dns"',
            ]
    lines += [
        " }",
        " chain forward {",
        "  type filter hook forward priority filter; policy drop;",
        "  ct state established,related accept",
    ]
    if policy.internet_forwarding and policy.mode != "offline-roku":
        for zone in ("hotspot-wifi", "lan-hotspot"):
            if zone in policy.interfaces:
                lines.append(
                    f'  iifname "{policy.interfaces[zone]}" accept comment "explicit-forwarding"'
                )
    lines += [
        " }",
        " chain output {",
        "  type filter hook output priority filter; policy accept;",
        " }",
        "}",
        "",
    ]
    return "\n".join(lines)


def _set_literal(values: tuple[str, ...]) -> str:
    return "{ " + ", ".join(values) + " }"


def emergency_table_script(table: str = BASE_TABLE, priority: str = "filter") -> str:
    """Return a conservative fail-closed policy for recovery.

    The emergency policy deliberately preserves local/private/Tailscale access
    so a firewall self-repair cannot strand the console, while rejecting new
    unsolicited public inbound traffic. The normal generated policy can be
    stricter and is restored from known-good state when available.
    """
    v4 = _set_literal(PRIVATE_V4)
    v6 = _set_literal(PRIVATE_V6)
    return "\n".join([
        "#!/usr/sbin/nft -f",
        f"flush table inet {table}",
        f"table inet {table} {{",
        " chain input {",
        f"  type filter hook input priority {priority}; policy drop;",
        '  iifname "lo" accept comment "neutronos-life-support-loopback"',
        "  ct state established,related accept comment \"neutronos-life-support-established\"",
        "  ct state invalid drop",
        "  ip protocol icmp accept",
        "  ip6 nexthdr ipv6-icmp accept",
        '  iifname "tailscale0" accept comment "neutronos-life-support-tailscale"',
        f"  ip saddr {v4} accept comment \"neutronos-life-support-private-v4\"",
        f"  ip6 saddr {v6} accept comment \"neutronos-life-support-private-v6\"",
        "  udp sport 67 udp dport 68 accept comment \"neutronos-life-support-dhcp4-client\"",
        "  udp sport 547 udp dport 546 accept comment \"neutronos-life-support-dhcp6-client\"",
        "  udp dport 67 accept comment \"neutronos-life-support-dhcp-server\"",
        "  udp dport 41641 accept comment \"neutronos-life-support-tailscale-wireguard\"",
        " }",
        " chain forward {",
        f"  type filter hook forward priority {priority}; policy drop;",
        "  ct state established,related accept",
        '  iifname "tailscale0" accept comment "neutronos-life-support-tailscale-forward"',
        f"  ip saddr {v4} accept comment \"neutronos-life-support-private-forward-v4\"",
        f"  ip6 saddr {v6} accept comment \"neutronos-life-support-private-forward-v6\"",
        " }",
        " chain output {",
        f"  type filter hook output priority {priority}; policy accept;",
        " }",
        "}",
        "",
    ])


def lifeline_monitor_rules() -> str:
    """Install a non-blocking sentinel while the normal base policy is healthy.

    A permanent fail-closed chain at an earlier hook priority would prevent the
    normal policy from intentionally exposing a service to a non-private source.
    The guard therefore keeps this lightweight sentinel in ACCEPT mode during
    normal operation and switches it to the emergency DROP policy *before* it
    attempts to recover a missing/corrupt base table.
    """
    return "\n".join([
        "#!/usr/sbin/nft -f",
        f"flush table inet {LIFELINE_TABLE}",
        f"table inet {LIFELINE_TABLE} {{",
        " chain input {",
        "  type filter hook input priority -250; policy accept;",
        '  counter comment "neutronos-life-support-sentinel"',
        " }",
        " chain forward {",
        "  type filter hook forward priority -250; policy accept;",
        '  counter comment "neutronos-life-support-sentinel"',
        " }",
        "}",
        "",
    ])


def lifeline_rules() -> str:
    """Return the fail-closed emergency lifeline used while base policy is absent."""
    return emergency_table_script(LIFELINE_TABLE, "-250")


def security_table_rules(banned_v4: list[str] | None = None,
                         banned_v6: list[str] | None = None) -> str:
    banned_v4 = banned_v4 or []
    banned_v6 = banned_v6 or []
    lines = [
        "#!/usr/sbin/nft -f",
        f"flush table inet {SECURITY_TABLE}",
        f"table inet {SECURITY_TABLE} {{",
        " set banned_v4 { type ipv4_addr; }",
        " set banned_v6 { type ipv6_addr; }",
        " chain input {",
        "  type filter hook input priority -300; policy accept;",
        "  ip saddr @banned_v4 drop",
        "  ip6 saddr @banned_v6 drop",
        " }",
        "}",
    ]
    if banned_v4:
        lines.append(f"add element inet {SECURITY_TABLE} banned_v4 {{ {', '.join(banned_v4)} }}")
    if banned_v6:
        lines.append(f"add element inet {SECURITY_TABLE} banned_v6 {{ {', '.join(banned_v6)} }}")
    lines.append("")
    return "\n".join(lines)


def containment_rules() -> str:
    return "\n".join([
        "#!/usr/sbin/nft -f",
        f"flush table inet {CONTAINMENT_TABLE}",
        f"table inet {CONTAINMENT_TABLE} {{",
        " chain input {",
        "  type filter hook input priority -400; policy drop;",
        '  iifname "lo" accept',
        "  ct state established,related accept",
        "  ip protocol icmp accept",
        "  ip6 nexthdr ipv6-icmp accept",
        " }",
        "}",
        "",
    ])


class FirewallActivator:
    def __init__(self, state_dir: Path, nft: str | None = None):
        self.state_dir = state_dir
        self.nft = nft or shutil.which("nft") or "/usr/sbin/nft"
        self.candidate = state_dir / "candidate.nft"
        self.known_good = state_dir / "known-good.nft"

    def table_exists(self, table: str) -> bool:
        result = subprocess.run(
            [self.nft, "list", "table", "inet", table],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=5,
        )
        return result.returncode == 0

    def _prepare_for_current_state(self, rules: str) -> str:
        """Make generated table-local scripts valid when the table is absent.

        Normal policy generation starts with ``flush table inet neutronos``.
        A batch containing only that table is atomic when the table exists. If
        it vanished, stripping that first flush lets the following declarative
        table block recreate it in one nft transaction.
        """
        prepared = rules
        for table in (BASE_TABLE, LIFELINE_TABLE, SECURITY_TABLE, CONTAINMENT_TABLE):
            marker = f"flush table inet {table}\n"
            if marker in prepared and not self.table_exists(table):
                prepared = prepared.replace(marker, "", 1)
        return prepared

    def validate(self, rules: str) -> tuple[bool, str]:
        self.state_dir.mkdir(parents=True, exist_ok=True)
        prepared = self._prepare_for_current_state(rules)
        fd, name = tempfile.mkstemp(prefix="firewall.", suffix=".nft", dir=self.state_dir)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(prepared)
            result = subprocess.run(
                [self.nft, "--check", "--file", name],
                capture_output=True,
                text=True,
                timeout=10,
            )
            return result.returncode == 0, result.stderr.strip()
        finally:
            try:
                os.unlink(name)
            except FileNotFoundError:
                pass

    def apply(self, rules: str, remember: bool = False) -> dict[str, Any]:
        prepared = self._prepare_for_current_state(rules)
        valid, error = self.validate(prepared)
        if not valid:
            return {
                "success": False,
                "error": "syntax-check-failed",
                "detail": error,
                "knownGoodRetained": True,
            }
        self.state_dir.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(prefix="firewall.apply.", suffix=".nft", dir=self.state_dir)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(prepared)
                handle.flush()
                os.fsync(handle.fileno())
            result = subprocess.run(
                [self.nft, "--file", name],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode != 0:
                return {
                    "success": False,
                    "error": "atomic-activation-failed",
                    "detail": result.stderr.strip(),
                    "knownGoodRetained": True,
                }
            if remember:
                temporary = self.known_good.with_suffix(".tmp")
                temporary.write_text(rules, encoding="utf-8")
                os.chmod(temporary, 0o600)
                os.replace(temporary, self.known_good)
            return {"success": True, "knownGoodRetained": not remember}
        finally:
            try:
                os.unlink(name)
            except FileNotFoundError:
                pass

    def _mirror_life_support_known_good(self, rules: str) -> None:
        """Mirror normal policy snapshots into the Security life-support state.

        Existing callers are free to keep their historical state directory. On
        a live NeutronOS system, successful normal policy activation also feeds
        the independent guard so recovery does not depend on the caller staying
        alive. Temporary/test state outside /var/lib/neutronos is never mirrored.
        """
        try:
            state_resolved = self.state_dir.resolve(strict=False)
            live_root = Path("/var/lib/neutronos").resolve(strict=False)
            if state_resolved != live_root and live_root not in state_resolved.parents:
                return
            target_dir = Path(os.environ.get(
                "NEUTRONOS_FIREWALL_LIFE_SUPPORT_DIR", str(CANONICAL_FIREWALL_STATE_DIR)
            ))
            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / "known-good.nft"
            if target.resolve(strict=False) == self.known_good.resolve(strict=False):
                return
            fd, temporary = tempfile.mkstemp(prefix="known-good.", suffix=".nft", dir=target_dir)
            try:
                os.fchmod(fd, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    handle.write(rules)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(temporary, target)
            finally:
                try:
                    os.unlink(temporary)
                except FileNotFoundError:
                    pass
        except OSError:
            # Policy activation already succeeded. Mirroring is a recovery aid
            # and must not convert a valid firewall transaction into a failure.
            pass

    def activate(self, rules: str) -> dict[str, Any]:
        result = self.apply(rules, remember=True)
        if result.get("success"):
            self._mirror_life_support_known_good(rules)
        return result

    def restore_known_good(self) -> dict[str, Any]:
        try:
            rules = self.known_good.read_text(encoding="utf-8")
        except OSError as exc:
            return {"success": False, "error": "known-good-unavailable", "detail": str(exc)}
        return self.apply(rules, remember=False)


def write_status(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    body = dict(payload)
    body.setdefault("schema", 1)
    body.setdefault("updatedAt", utc_now())
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        os.fchmod(fd, 0o640)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(body, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
