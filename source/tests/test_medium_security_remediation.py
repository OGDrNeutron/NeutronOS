import importlib.util
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT.parent
RUNTIME_ROOT = Path(os.environ.get("NEUTRONOS_MEDIUM_RUNTIME_ROOT", str(BUNDLE / "runtime")))

sys.path.insert(0, str(ROOT / "scripts"))
from neutronos_remote_security import PairingCodes  # noqa: E402


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class PairingRaceTests(unittest.TestCase):
    def test_pairing_code_is_consumed_once_under_concurrency(self):
        with tempfile.TemporaryDirectory() as tmp:
            codes = PairingCodes(Path(tmp) / "pairing.json", ttl=60)
            code = codes.create(now=100)
            results = []
            lock = threading.Lock()

            def consume():
                result = codes.consume(code, now=101)
                with lock:
                    results.append(result)

            threads = [threading.Thread(target=consume) for _ in range(24)]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()
            self.assertEqual(results.count(True), 1)
            self.assertEqual(results.count(False), 23)


class DurableLimiterTests(unittest.TestCase):
    def test_web_login_lockout_survives_new_limiter_instance(self):
        runtime = load_module(ROOT / "tools/neutron-media-web/security_runtime.py", "media_security_runtime")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "throttle.json"
            limiter = runtime.DurableAuthLimiter(path, source_limit=3, global_limit=100, window=600, lockout=60)
            for stamp in (100.0, 101.0, 102.0):
                limiter.failure("192.0.2.1", now=stamp)
            fresh = runtime.DurableAuthLimiter(path, source_limit=3, global_limit=100, window=600, lockout=60)
            allowed, retry = fresh.allowed("192.0.2.1", now=103.0)
            self.assertFalse(allowed)
            self.assertGreaterEqual(retry, 58)


class BrokerIdentityTests(unittest.TestCase):
    def test_unused_argv_path_does_not_authenticate_as_script(self):
        broker = load_module(
            RUNTIME_ROOT / "usr/local/lib/neutronos/neutron-remote-service.py",
            "neutron_remote_broker",
        )
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "provider.py"
            script.write_text("#!/usr/bin/python3\nimport time\ntime.sleep(10)\n", encoding="utf-8")
            script.chmod(0o700)
            direct = subprocess.Popen([str(script)])
            attack = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(10)", str(script)])
            try:
                time.sleep(0.1)
                self.assertTrue(broker.exact_script_invocation(direct.pid, script))
                self.assertFalse(broker.exact_script_invocation(attack.pid, script))
            finally:
                direct.terminate(); attack.terminate()
                direct.wait(timeout=2); attack.wait(timeout=2)


class SourceContracts(unittest.TestCase):
    def test_controller_transport_uses_safe_atomic_files(self):
        source = (ROOT / "scripts/neutronos-controller-transport.py").read_text()
        self.assertIn("tempfile.mkstemp", source)
        self.assertIn("os.replace", source)
        self.assertIn("O_NOFOLLOW", source)
        self.assertIn("stat.S_ISREG", source)

    def test_remote_controller_has_non_spoofable_pair_bucket_and_bounds(self):
        source = (ROOT / "services/remote/neutronos_remote_controller.py").read_text()
        self.assertNotIn("X-NeutronOS-Device", source)
        for token in ("PAIR_GLOBAL_LIMIT", "BoundedSemaphore", "MAX_CONCURRENT_REQUESTS", "settimeout"):
            self.assertIn(token, source)

    def test_remote_keyboard_is_tls_only(self):
        source = (ROOT / "src/RemoteKeyboardManager.cpp").read_text()
        for token in ("QSslSocket", "TlsV1_2OrLater", "https://", "Secure; HttpOnly", "Strict-Transport-Security"):
            self.assertIn(token, source)
        self.assertNotIn('QByteArray("http://neutronos.local")', source)

    def test_web_admin_paths_are_fail_closed_tls_and_throttled(self):
        media = (ROOT / "tools/neutron-media-web/app.py").read_text()
        subtitle = (ROOT / "tools/neutron-subtitle-web/app.py").read_text()
        media_run = (ROOT / "tools/neutron-media-web/run.py").read_text()
        subtitle_run = (ROOT / "tools/neutron-subtitle-web/run.py").read_text()
        self.assertIn("return bool(PIN) and bool(session.get", media)
        self.assertIn("DurableAuthLimiter", media)
        self.assertIn("DurableAuthLimiter", subtitle)
        self.assertIn('os.getenv("NEUTRON_SUBTITLE_PIN", "")', subtitle)
        self.assertNotIn('os.getenv("NEUTRON_SUBTITLE_PIN", "123456")', subtitle)
        self.assertIn("serve_tls", media_run)
        self.assertIn("serve_tls", subtitle_run)

    def test_update_trust_is_not_restored_from_state(self):
        cpp = (ROOT / "src/UpdateRecoveryManager.cpp").read_text()
        helper = (ROOT / "scripts/neutronos-update-recovery.sh").read_text()
        self.assertNotIn('value(QStringLiteral("packageVerified")).toBool', cpp)
        self.assertIn("m_packageVerified = false", cpp)
        self.assertIn("m_manifestEnvelopePath", cpp)
        self.assertIn("verify_signed_update", helper)
        self.assertIn("/etc/neutronos/update-public-key", helper)
        self.assertIn('return QStringLiteral("/etc/neutronos/update-public-key")', cpp)
        self.assertNotIn("config/update-public-key", cpp)
        self.assertIn("/usr/local/lib/neutronos/neutronos-update-recovery", cpp)
        self.assertIn('ROOT="/opt/neutronos"', helper)
        self.assertIn('cmake --build "$build" -j2', helper)
        self.assertNotIn('EXPECTED="${2:?Expected SHA-256 is required}"', helper)

    def test_package_helpers_are_fail_closed_sandboxed(self):
        source = (ROOT / "src/PackageAppBridgeManager.cpp").read_text()
        for token in ("bwrap", "--unshare-all", "--cap-drop", "--clearenv",
                      "RLIMIT_NOFILE", "RLIMIT_FSIZE", "RLIMIT_CORE"):
            self.assertIn(token, source)
        # RLIMIT_NPROC is per real UID, not per package, and a hardcoded 64
        # prevents Bubblewrap from creating namespaces on a busy desktop.
        self.assertNotIn("::setrlimit(RLIMIT_NPROC", source)
        self.assertNotIn("QProcessEnvironment::systemEnvironment()", source)
        self.assertIn("remote-service-admin.sock", source)
        self.assertIn("remote-service-provider.sock", source)

    def test_broker_uses_separate_restricted_sockets_and_kernel_identity(self):
        source = (RUNTIME_ROOT / "usr/local/lib/neutronos/neutron-remote-service.py").read_text()
        self.assertIn("remote-service-admin.sock", source)
        self.assertIn("remote-service-provider.sock", source)
        self.assertIn("SO_PEERCRED", source)
        self.assertIn("peer_in_neutronos_service", source)
        self.assertIn("os.chmod(path, 0o660)", source)
        self.assertNotIn("os.chmod(SOCKET_PATH, 0o666)", source)
        self.assertNotIn("def peer_paths", source)


if __name__ == "__main__":
    unittest.main()
