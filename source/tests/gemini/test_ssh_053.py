from pathlib import Path
import contextlib, importlib.util, importlib.machinery, io, os, stat, subprocess, tempfile, unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
loader=importlib.machinery.SourceFileLoader("ssh_guard_053",str(ROOT/"deployment/usr/local/sbin/neutronos-privileged-helper"))
spec=importlib.util.spec_from_loader(loader.name,loader)
guard=importlib.util.module_from_spec(spec);spec.loader.exec_module(guard)
class SSHAuthentication(unittest.TestCase):
    def test_deployed_guard_matches_authoritative_script(self):
        self.assertEqual((ROOT/"deployment/usr/local/sbin/neutronos-privileged-helper").read_bytes(),(ROOT/"scripts/neutronos-privileged-helper-guard.py").read_bytes())
    def effective(self, directory):
        config=directory/"sshd_config"
        key=directory/"fixture_host_key"
        subprocess.run(["ssh-keygen","-q","-t","ed25519","-N","","-f",str(key)],check=True)
        config.write_text("Include "+str(directory/"*.conf")+"\nHostKey "+str(key)+"\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nUsePAM yes\n")
        return subprocess.check_output(["/usr/sbin/sshd","-T","-f",str(config)],text=True)
    def test_cloud_policy_gap_is_reproduced(self):
        with tempfile.TemporaryDirectory() as td:
            self.assertIn("passwordauthentication no",self.effective(Path(td)))
    def test_setup_account_password_is_accepted_by_actual_sshd_configuration(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)
            with patch.object(guard,"SSH_SETUP_CONFIG",root/"99-neutronos-setup-ssh.conf"):
                guard._prepare_ssh_account_authentication()
            effective=self.effective(root)
            self.assertIn("passwordauthentication yes",effective)
            self.assertIn("permitrootlogin no",effective)
            self.assertIn("permitemptypasswords no",effective)
            self.assertEqual(stat.S_IMODE((root/"99-neutronos-setup-ssh.conf").stat().st_mode),0o600)
    def test_security_key_only_hardening_still_precedes_setup_policy(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)
            (root/"99-neutronos-security.conf").write_text("PasswordAuthentication no\nKbdInteractiveAuthentication no\n")
            with patch.object(guard,"SSH_SETUP_CONFIG",root/"99-neutronos-setup-ssh.conf"):
                guard._prepare_ssh_account_authentication()
            self.assertIn("passwordauthentication no",self.effective(root))
    def test_config_symlink_is_rejected_without_modifying_target(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);target=root/"protected";target.write_text("unchanged")
            link=root/"config.conf";link.symlink_to(target)
            with patch.object(guard,"SSH_SETUP_CONFIG",link),contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit):guard._prepare_ssh_account_authentication()
            self.assertEqual(target.read_text(),"unchanged")
    def test_reenable_restores_runtime_before_sshd_preflight(self):
        from types import SimpleNamespace
        commands=[]
        states=iter(["enabled\n","active\n"])
        with patch.object(guard,"_unit_load_state",return_value="loaded"),patch.object(guard,"_ensure_ssh_host_keys"),patch.object(guard,"_prepare_ssh_account_authentication"),patch.object(guard,"_verify_ssh_listener"),patch.object(guard,"SSHD_NOT_TO_BE_RUN",Path("/nonexistent-gemini-test-disabled-marker")),patch.object(guard,"_run_command",side_effect=lambda command,label,**kw:commands.append(command)),patch.object(guard.subprocess,"run",side_effect=lambda *a,**k:SimpleNamespace(stdout=next(states))):
            guard._apply_ssh_enabled(True)
        prepare=["/usr/bin/systemd-tmpfiles","--create","--prefix=/run/sshd"]
        self.assertIn(prepare,commands)
        self.assertLess(commands.index(prepare),commands.index(["/usr/sbin/sshd","-t"]))
        self.assertLess(commands.index(["/usr/sbin/sshd","-t"]),commands.index(["/usr/bin/systemctl","start","ssh.service"]))
    def test_loopback_only_listener_does_not_report_remote_readiness(self):
        table="header\n 0: 0100007F:0016 00000000:0000 0A\n"
        with patch.object(Path,"read_text",return_value=table),contextlib.redirect_stdout(io.StringIO()) as output:
            with self.assertRaises(SystemExit):guard._verify_ssh_listener()
        self.assertIn("no non-loopback TCP/22 listener",output.getvalue())
    def test_active_listener_with_non_ssh_service_does_not_pass(self):
        table="header\n 0: 00000000:0016 00000000:0000 0A\n"
        class Connection:
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def recv(self,count):return b"HTTP/1.1 unexpected service"
        with patch.object(Path,"read_text",return_value=table),patch.object(guard.socket,"create_connection",return_value=Connection()),contextlib.redirect_stdout(io.StringIO()) as output:
            with self.assertRaises(SystemExit):guard._verify_ssh_listener()
        self.assertIn("did not answer an SSH handshake",output.getvalue())
if __name__=="__main__":unittest.main(verbosity=2)
