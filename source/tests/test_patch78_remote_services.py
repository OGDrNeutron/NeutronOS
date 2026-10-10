import json, tempfile, unittest
from pathlib import Path
from unittest import mock
from scripts.neutronos_remote_security import AuditLog, PairingCodes, RateLimiter, ReplayGuard, TokenStore, resolve_inside


class TokenTests(unittest.TestCase):
    def setUp(self): self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def test_strong_token_expiry_rotation_and_revocation(self):
        store=TokenStore(self.root/"tokens.json", lifetime=10)
        token,record=store.issue("phone",now=100)
        self.assertGreaterEqual(len(token),64); self.assertNotIn(token,(self.root/"tokens.json").read_text())
        self.assertEqual(store.authenticate(token,now=105)["deviceId"],"phone")
        self.assertIsNone(store.authenticate(token,now=111))
        new,new_record=store.rotate(record["id"],"phone")
        self.assertIsNone(store.authenticate(token)); self.assertIsNotNone(store.authenticate(new))
        self.assertTrue(store.revoke(new_record["id"])); self.assertIsNone(store.authenticate(new))
    def test_pairing_is_one_time_and_offline(self):
        codes=PairingCodes(self.root/"pair.json",ttl=30)
        with mock.patch("scripts.neutronos_remote_security.secrets.randbelow",return_value=123): code=codes.create(now=10)
        self.assertEqual(code,"000123"); self.assertTrue(codes.consume(code,now=20)); self.assertFalse(codes.consume(code,now=20))
    def test_rate_limit_backoff_and_recovery(self):
        limiter=RateLimiter(2,60,10); self.assertEqual(limiter.failure("x",now=1),0); self.assertGreater(limiter.failure("x",now=2),0)
        self.assertFalse(limiter.allowed("x",now=2)[0]); limiter.success("x"); self.assertTrue(limiter.allowed("x",now=2)[0])
    def test_replay_and_stale_requests_are_rejected(self):
        guard=ReplayGuard(window_seconds=30)
        self.assertTrue(guard.accept("device","nonce",100000,now=100))
        self.assertFalse(guard.accept("device","nonce",100000,now=100))
        self.assertFalse(guard.accept("device","other",1000,now=100))
    def test_audit_redacts_tokens(self):
        audit=AuditLog(self.root/"audit"); audit.write("test",{"token":"secret","result":"denied"})
        text=(self.root/"audit").read_text(); self.assertNotIn("secret",text); self.assertIn("REDACTED",text)


class MediaRootTests(unittest.TestCase):
    def setUp(self): self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name); (self.root/"movie.mkv").write_text("x")
    def tearDown(self): self.temp.cleanup()
    def test_allowed_and_denied_paths(self):
        self.assertEqual(resolve_inside(self.root,"movie.mkv"),self.root/"movie.mkv")
        for attack in ("../etc/passwd","/etc/passwd","\x00bad"):
            with self.assertRaises((ValueError,PermissionError,FileNotFoundError)): resolve_inside(self.root,attack)
    def test_symlink_escape_denied(self):
        (self.root/"escape").symlink_to("/etc/passwd")
        with self.assertRaises(PermissionError): resolve_inside(self.root,"escape")


class SourceContracts(unittest.TestCase):
    def test_remote_controller_requires_tls_pairing_bounds_and_no_raw_token_log(self):
        source=Path("services/remote/neutronos_remote_controller.py").read_text()
        for token in ("ssl.SSLContext","/api/pair","TokenStore","RateLimiter","MAX_BODY_BYTES","AUDIT.write"):
            self.assertIn(token,source)
        self.assertNotIn("print(token",source)
        client=Path("services/remote/Static/controller.js").read_text()
        self.assertNotIn("new WebSocket",client); self.assertIn("crypto.randomUUID",client)
    def test_media_optimizer_tls_and_constrained_roots(self):
        run=Path("remote-media-optimizer/run.py").read_text(); engine=Path("remote-media-optimizer/optimizer/media_engine.py").read_text(); gateway=Path("remote-media-optimizer/gateway.py").read_text()
        self.assertIn("ssl_context",run); self.assertIn("PairingCodes",gateway); self.assertNotIn('Path("/home")',engine)
    def test_firewall_declares_interface_scoped_services(self):
        firewall=Path("scripts/neutronos_firewall.py").read_text()
        self.assertIn('"remote-controller"',firewall); self.assertIn('"media-optimizer"',firewall); self.assertIn("iifname",firewall)

if __name__=="__main__": unittest.main()
