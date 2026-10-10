#!/usr/bin/env python3
"""Dynamic raw-TLS edge for remote.neutronos.

Tailscale healthy: TailscaleIPv4:443 -> token backend 127.0.0.1:8091
Tailscale unavailable: private LAN IPv4:443 -> PAM backend 127.0.0.1:8092
"""
from __future__ import annotations
import asyncio, ipaddress, json, os, signal, subprocess, sys
from pathlib import Path

TAILSCALE = "/usr/bin/tailscale"
IP = "/usr/sbin/ip" if Path("/usr/sbin/ip").exists() else "/usr/bin/ip"
PRIMARY_PORT = int(os.environ.get("NEUTRONOS_REMOTE_PRIMARY_PORT", "8091"))
FALLBACK_PORT = int(os.environ.get("NEUTRONOS_REMOTE_FALLBACK_PORT", "8092"))
CHECK_SECONDS = float(os.environ.get("NEUTRONOS_REMOTE_FAILOVER_INTERVAL", "5"))
STATUS_PATH = Path("/run/neutronos/remote-edge.json")
PORT_CONFIG_PATH = Path("/var/lib/neutronos/remote/web-controller-port.json")
SYSTEM_DEFAULT_PORT = 443
NM_SHARED_DIR = Path("/etc/NetworkManager/dnsmasq-shared.d")
NM_SHARED_CONF = NM_SHARED_DIR / "99-neutronos-remote.conf"
HOSTNAME = "remote.neutronos"
EXCLUDED_PREFIXES = ("lo", "tailscale", "docker", "veth", "br-", "virbr", "tun", "tap", "wg")


def run_json(argv):
    try:
        p = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=4, check=False)
        if p.returncode != 0:
            return None
        return json.loads(p.stdout)
    except (OSError, ValueError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return None


def external_port():
    try:
        value = json.loads(PORT_CONFIG_PATH.read_text(encoding="utf-8"))
        if isinstance(value, dict) and str(value.get("mode") or "").lower() == "custom":
            port = int(value.get("port") or 0)
            if 1 <= port <= 65535:
                return port
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        pass
    return SYSTEM_DEFAULT_PORT


def tailscale_state():
    value = run_json([TAILSCALE, "status", "--json"])
    if not isinstance(value, dict) or value.get("BackendState") != "Running":
        return False, []
    self_state = value.get("Self") or {}
    if self_state.get("Online") is False:
        return False, []
    ips = []
    for raw in value.get("TailscaleIPs") or []:
        try:
            ip = ipaddress.ip_address(raw)
        except ValueError:
            continue
        if ip.version == 4:
            ips.append(str(ip))
    return bool(ips), ips


def lan_ipv4s():
    value = run_json([IP, "-j", "-4", "addr", "show", "up"])
    found = []
    if not isinstance(value, list):
        return found
    for item in value:
        name = str(item.get("ifname", ""))
        if name.startswith(EXCLUDED_PREFIXES):
            continue
        for info in item.get("addr_info") or []:
            if info.get("family") != "inet" or info.get("scope") != "global":
                continue
            try:
                addr = ipaddress.ip_address(info.get("local", ""))
            except ValueError:
                continue
            if addr.version != 4 or not addr.is_private or addr.is_loopback or addr.is_link_local:
                continue
            found.append((name, str(addr)))
    # Prefer explicit hotspot/shared subnets, then ordinary private LANs.
    found.sort(key=lambda x: (0 if x[1].startswith("10.42.") else 1, x[0], x[1]))
    return found


def nm_shared_dnsmasq():
    results = []
    proc = Path("/proc")
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            raw = (entry / "cmdline").read_bytes().split(b"\0")
            args = [x.decode("utf-8", "replace") for x in raw if x]
        except (OSError, PermissionError):
            continue
        joined = " ".join(args)
        if "/usr/sbin/dnsmasq" not in joined or "--conf-dir=/etc/NetworkManager/dnsmasq-shared.d" not in args:
            continue
        listen = ""
        for arg in args:
            if arg.startswith("--listen-address="):
                listen = arg.split("=", 1)[1]
                break
        if listen:
            results.append((int(entry.name), listen))
    return results


def ensure_local_dns_mapping():
    """Prepare NetworkManager shared-dnsmasq mapping for direct Pi networks.

    Config is written only for a live NM shared dnsmasq. The child is restarted
    once so NetworkManager respawns it with the new conf-dir entry.
    """
    shared = nm_shared_dnsmasq()
    if not shared:
        return None
    pid, listen = shared[0]
    try:
        addr = ipaddress.ip_address(listen)
    except ValueError:
        return None
    if addr.version != 4 or not addr.is_private:
        return None
    desired = f"# Managed by NeutronOS Remote failover\naddress=/{HOSTNAME}/{listen}\n"
    current = ""
    try:
        current = NM_SHARED_CONF.read_text()
    except OSError:
        pass
    if current == desired:
        return listen
    NM_SHARED_DIR.mkdir(parents=True, exist_ok=True)
    tmp = NM_SHARED_CONF.with_suffix(".tmp")
    tmp.write_text(desired)
    os.chmod(tmp, 0o644)
    os.replace(tmp, NM_SHARED_CONF)
    # Do not kill or restart NetworkManager's DHCP/DNS child from an automatic
    # failover path. The mapping is consumed on the next shared-network cycle
    # or reboot; an explicit activation helper is provided for immediate use.
    return listen


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionError, OSError, asyncio.CancelledError):
        pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def proxy_client(reader, writer, backend_port):
    try:
        br, bw = await asyncio.open_connection("127.0.0.1", backend_port)
    except OSError:
        writer.close()
        await writer.wait_closed()
        return
    await asyncio.gather(pipe(reader, bw), pipe(br, writer))


async def main_loop():
    servers = {}
    last_mode = None
    while True:
        healthy, tsips = tailscale_state()
        port = external_port()
        if healthy:
            mode = "tailscale"
            desired = {(ip, port, PRIMARY_PORT) for ip in tsips}
        else:
            mode = "lan-fallback"
            ensure_local_dns_mapping()
            desired = {(ip, port, FALLBACK_PORT) for _ifname, ip in lan_ipv4s()}

        for key in list(servers):
            if key not in desired:
                servers.pop(key).close()
        for server in list(servers.values()):
            await server.wait_closed() if server.is_serving() is False else asyncio.sleep(0)

        for key in sorted(desired):
            if key in servers:
                continue
            host, port, backend = key
            try:
                server = await asyncio.start_server(lambda r,w,b=backend: proxy_client(r,w,b), host, port, reuse_address=True)
            except OSError as exc:
                print(f"[remote-edge] cannot bind {host}:{port}: {exc}", flush=True)
                continue
            servers[key] = server
            print(f"[remote-edge] {mode}: {host}:{port} -> 127.0.0.1:{backend}", flush=True)

        status = {"mode": mode, "tailscaleHealthy": healthy, "tailscaleIPv4": tsips,
                  "configuredPort": port,
                  "listeners": [{"address":h,"port":p,"backendPort":b} for h,p,b in sorted(servers)]}
        try:
            tmp = STATUS_PATH.with_suffix(".tmp")
            tmp.write_text(json.dumps(status, separators=(",", ":")) + "\n")
            os.chmod(tmp, 0o644)
            os.replace(tmp, STATUS_PATH)
        except OSError:
            pass
        if mode != last_mode:
            # A mode transition invalidates all emergency PAM web sessions by
            # restarting only the localhost fallback backend. This does not
            # touch NeutronShell or the primary Tailscale backend.
            if last_mode is not None:
                try:
                    subprocess.run(["/usr/bin/systemctl", "try-restart", "neutronos-remote-controller-fallback.service"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10, check=False)
                except (OSError, subprocess.TimeoutExpired):
                    pass
            print(f"[remote-edge] mode={mode}", flush=True)
            last_mode = mode
        await asyncio.sleep(CHECK_SECONDS)


def self_test():
    assert ipaddress.ip_address("10.42.1.1").is_private
    assert not ipaddress.ip_address("127.0.0.1").is_link_local
    print("remote edge self-test passed")

if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
        raise SystemExit(0)
    if "--sync-local-dns" in sys.argv:
        value = ensure_local_dns_mapping()
        print(value or "no NetworkManager shared dnsmasq detected")
        raise SystemExit(0)
    asyncio.run(main_loop())
