import tempfile, unittest
from pathlib import Path
from unittest import mock
from scripts.neutronos_firewall import FirewallActivator, FirewallPolicyError, generate


def policy(mode="normal-wifi", services=None):
    return {"mode": mode,
            "interfaces": {"lan": "wlan0", "ethernet": "eth0", "hotspot-wifi": "wlan0",
                           "lan-hotspot": "eth0", "offline-roku": "wlan0", "tailscale": "tailscale0"},
            "services": services or {},
            "management": {"interface": "tailscale0", "source": "100.64.1.2"}}


class GeneratorTests(unittest.TestCase):
    def test_modes_generate_complete_restrictive_rules(self):
        for mode in ("normal-wifi", "ethernet", "wifi-hotspot", "lan-hotspot", "offline-roku"):
            rules = generate(policy(mode))
            self.assertIn("flush table inet neutronos", rules)
            self.assertIn("policy drop", rules)
            self.assertIn("preserve-admin", rules)
            if mode == "offline-roku": self.assertNotIn("explicit-forwarding", rules)

    def test_services_are_interface_specific(self):
        rules = generate(policy(services={"ssh": ["tailscale"], "jellyfin": ["offline-roku"],
                                          "remote-controller": ["lan"], "media-optimizer": ["ethernet"],
                                          "tailscale": ["lan"]}))
        self.assertIn('iifname "tailscale0" tcp dport 22', rules)
        self.assertIn('iifname "wlan0" tcp dport 8096', rules)
        self.assertNotIn("tcp dport 22 accept everywhere", rules)

    def test_unknown_fields_services_and_interfaces_fail_closed(self):
        for mutation in ({"unknown": True}, {"services": {"telnet": ["lan"]}},
                         {"interfaces": {"lan": "bad interface"}}):
            value = policy(); value.update(mutation)
            with self.assertRaises(FirewallPolicyError): generate(value)

    @mock.patch("scripts.neutronos_firewall.subprocess.run")
    def test_syntax_failure_retains_known_good_and_never_activates(self, run):
        run.return_value = mock.Mock(returncode=1, stderr="bad syntax")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); known = root / "known-good.nft"; known.write_text("known")
            result = FirewallActivator(root, "/usr/sbin/nft").activate(generate(policy()))
            self.assertFalse(result["success"]); self.assertTrue(result["knownGoodRetained"])
            self.assertEqual(known.read_text(), "known")
            self.assertEqual(run.call_count, 1)

    @mock.patch("scripts.neutronos_firewall.subprocess.run")
    def test_valid_candidate_uses_check_then_single_atomic_batch(self, run):
        run.side_effect = [mock.Mock(returncode=0, stderr=""), mock.Mock(returncode=0, stderr="")]
        with tempfile.TemporaryDirectory() as temp:
            result = FirewallActivator(Path(temp), "/usr/sbin/nft").activate(generate(policy()))
            self.assertTrue(result["success"]); self.assertEqual(run.call_count, 2)
            self.assertIn("--check", run.call_args_list[0].args[0])
            self.assertNotIn("add rule", " ".join(run.call_args_list[1].args[0]))

    def test_hotspot_dns_is_scoped_and_wildcard_does_not_enable_forwarding(self):
        rules = generate(policy("wifi-hotspot"))
        self.assertIn("hotspot-wifi-dhcp-dns", rules)
        self.assertNotIn("explicit-forwarding", rules)


if __name__ == "__main__": unittest.main()
