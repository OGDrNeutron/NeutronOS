from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location(
    "neutronos_offline_networkd", ROOT / "scripts/neutronos-offline-networkd.py")
NETWORK = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
sys.modules[SPEC.name] = NETWORK
SPEC.loader.exec_module(NETWORK)


class FakeNm:
    def __init__(self) -> None:
        self.active = {"wlan0": "HomeWiFi", "eth0": ""}
        self.down_calls: list[str] = []

    def wifi_device(self, configured=""): return "wlan0"
    def lan_device(self, configured=""): return "eth0"
    def active_is_profile(self, device, profile): return self.active.get(device) == profile
    def active_infrastructure(self, device, hotspot):
        active = self.active.get(device, "")
        return bool(active and active != hotspot), active
    def wifi_radio_enabled(self): return True
    def set_wifi_radio(self, enabled): return True
    def ensure_wifi_profile(self, config, device): return NETWORK.Result(0, "", "")
    def ensure_lan_profile(self, config, device): return NETWORK.Result(0, "", "")
    def active_connection(self, device): return self.active.get(device, "")
    def profile_down(self, name):
        self.down_calls.append(name)
        for device, active in self.active.items():
            if active == name: self.active[device] = ""
        return NETWORK.Result(0, "", "")
    def profile_up(self, name, device, timeout=40):
        self.active[device] = name
        return NETWORK.Result(0, "", "")


class FakeDns:
    def __init__(self): self.active = set()
    def running(self, kind): return kind in self.active
    def stop(self, kind): self.active.discard(kind)
    def start(self, kind, interface, config, global_config):
        self.active.add(kind)
        return True, "started"
    def leases(self, kind): return []
    def close(self): self.active.clear()


class Patch71SecureNetworkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="patch71-")
        base = Path(self.temp.name)
        self.originals = (NETWORK.CONFIG_PATH, NETWORK.RUNTIME_DIR,
                          NETWORK.STATE_PATH, NETWORK.CREDENTIAL_PATH)
        NETWORK.CONFIG_PATH = base / "offline-network.json"
        NETWORK.RUNTIME_DIR = base / "run"
        NETWORK.STATE_PATH = NETWORK.RUNTIME_DIR / "state.json"
        NETWORK.CREDENTIAL_PATH = base / "hotspot.psk"
        config = NETWORK.deep_merge(NETWORK.DEFAULT_CONFIG, {
            "wifi": {"credential_path": str(NETWORK.CREDENTIAL_PATH)}})
        NETWORK.save_config(config)

    def tearDown(self):
        (NETWORK.CONFIG_PATH, NETWORK.RUNTIME_DIR,
         NETWORK.STATE_PATH, NETWORK.CREDENTIAL_PATH) = self.originals
        self.temp.cleanup()

    def controller(self):
        value = NETWORK.Controller()
        value.nm = FakeNm()
        value.dnsmasq = FakeDns()
        return value

    def test_default_is_explicit_normal_mode_and_hotspots_are_off(self):
        config = NETWORK.load_config()
        self.assertEqual(config["mode"], "normal-wifi")
        self.assertFalse(config["offline_roku_enabled"])
        self.assertFalse(config["auto_fallback_enabled"])
        self.assertFalse(config["wifi"]["manual_enabled"])
        self.assertFalse(config["lan"]["manual_enabled"])

    def test_hotspot_requires_first_use_password(self):
        result = self.controller().apply("set-mode", {"mode": "wifi-hotspot"})
        self.assertFalse(result["success"])
        self.assertTrue(result["passwordRequired"])

    def test_password_policy_confirmation_and_private_storage(self):
        controller = self.controller()
        mismatch = controller.apply("set-credential", {
            "password": "abcdefgh", "confirmation": "abcdefgi"})
        self.assertFalse(mismatch["success"])
        with self.assertRaisesRegex(ValueError, "8 to 63"):
            NETWORK.save_wifi_password(NETWORK.load_config(), "short")
        accepted = controller.apply("set-credential", {
            "password": "correct-horse", "confirmation": "correct-horse"})
        self.assertTrue(accepted["success"])
        self.assertEqual(NETWORK.CREDENTIAL_PATH.stat().st_mode & 0o777, 0o600)
        config_text = NETWORK.CONFIG_PATH.read_text(encoding="utf-8")
        self.assertNotIn("correct-horse", config_text)

    def test_normal_mode_never_disconnects_current_wifi(self):
        controller = self.controller()
        result = controller.apply("set-mode", {"mode": "normal-wifi"})
        self.assertTrue(result["success"])
        self.assertEqual(controller.nm.active["wlan0"], "HomeWiFi")
        self.assertEqual(controller.nm.down_calls, [])

    def test_only_explicit_wifi_hotspot_transition_reassigns_wifi(self):
        NETWORK.save_wifi_password(NETWORK.load_config(), "correct-horse")
        controller = self.controller()
        result = controller.apply("set-mode", {"mode": "wifi-hotspot"})
        self.assertTrue(result["success"])
        self.assertIn("HomeWiFi", controller.nm.down_calls)
        self.assertEqual(result["mode"], "wifi-hotspot")

    def test_illegal_cross_hotspot_transition_requires_normal_mode(self):
        config = NETWORK.load_config()
        config["mode"] = "wifi-hotspot"
        NETWORK.save_config(config)
        result = self.controller().apply("set-mode", {"mode": "lan-hotspot"})
        self.assertFalse(result["success"])
        self.assertIn("Illegal transition", result["error"])

    def test_dnsmasq_and_wildcard_dns_are_independent(self):
        controller = self.controller()
        result = controller.apply("set-dns", {
            "target": "lan", "enabled": False, "wildcard": True})
        self.assertTrue(result["success"])
        config = NETWORK.load_config()
        self.assertFalse(config["lan"]["dnsmasq_enabled"])
        self.assertTrue(config["dnsmasq"]["wildcard_dns_to_gateway"])

    def test_secure_ipc_and_redaction_are_canonical(self):
        daemon = (ROOT / "scripts/neutronos-offline-networkd.py").read_text()
        client = (ROOT / "scripts/neutronos-offline-network-control").read_text()
        unit = (ROOT / "systemd/neutronos-offline-network.service").read_text()
        self.assertIn("IpcServer", daemon)
        self.assertIn("verify_active_session", daemon)
        self.assertIn("AuthorizationPolicy", daemon)
        self.assertIn("IpcClient", client)
        self.assertNotIn("json.dumps({\"action\"", client)
        self.assertIn("offline-network-authorization.json", daemon)
        self.assertIn("PYTHONPATH=/usr/local/lib/neutronos", unit)
        self.assertNotIn('"password": "NeutronOS"',
                         (ROOT / "config/offline-network.json").read_text())

    def test_authorization_policy_is_default_deny_and_typed(self):
        policy = json.loads((ROOT / "config/offline-network-authorization.json").read_text())
        self.assertTrue(policy["defaultDeny"])
        credential = policy["operations"]["network.set-wifi-credential"]
        self.assertEqual(credential["arguments"]["properties"]["password"]["minLength"], 8)
        self.assertNotIn("network.destroy", policy["operations"])


if __name__ == "__main__":
    unittest.main()
