from pathlib import Path
import contextlib, importlib.util, importlib.machinery, io, json, os, subprocess, tempfile, unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
loader=importlib.machinery.SourceFileLoader('finalize056',str(ROOT/'deployment/usr/local/sbin/neutronos-privileged-helper'))
spec=importlib.util.spec_from_loader(loader.name,loader);guard=importlib.util.module_from_spec(spec);loader.exec_module(guard)
class Finalization(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.setup=self.root/'setup';self.core=self.root/'security-core';self.setup.mkdir(mode=0o750);self.core.mkdir(mode=0o750)
  self.state=self.setup/'setup.json';self.request=self.setup/'finalize-request';self.stamp=self.core/'account-handoff-finalized-v1';self.banner=self.root/'rename_user.conf'
  self.paths=patch.multiple(guard,SETUP_DIR=self.setup,SETUP_STATE=self.state,ACCOUNT_HANDOFF_FINALIZED=self.stamp,RENAME_USER_CONF=self.banner);self.paths.start()
  self.calls=[]
  self.run=patch.object(guard,'_run_command',side_effect=lambda args,label:self.calls.append(args));self.run_mock=self.run.start()
  self.units=patch.object(guard,'_unit_load_state',return_value='not-found');self.units.start()
  self.command=patch.object(guard.subprocess,'run',return_value=subprocess.CompletedProcess([],3,'inactive\n',''));self.command_mock=self.command.start()
  self.owner=patch.object(guard.os,'geteuid',return_value=0)
  # Production requires root-owned stamp and directory. Fixture ownership is
  # verified separately below because tests run without privileges on the host.
  self.trust=patch.object(guard,'require_root_owned',side_effect=self.check_trust);self.trust.start()
 def check_trust(self,path,*,directory):
  if path.is_symlink() or (directory and not path.is_dir()) or (not directory and not path.is_file()) or path.stat().st_mode & 0o022:guard.fail('invalid trusted finalization path')
 def tearDown(self):
  self.trust.stop();self.command.stop();self.units.stop();self.run.stop();self.paths.stop();self.temp.cleanup()
 def invoke(self):
  with contextlib.redirect_stdout(io.StringIO()) as output:
   code=guard.finalize_setup_if_complete([])
  self.assertEqual(code,0);return json.loads(output.getvalue())
 def complete(self):self.state.write_text('{"completed":true}');self.request.write_text('finalize-v1\n')
 def test_fresh_and_incomplete_boot_are_expected(self):
  self.assertFalse(self.invoke()['finalized']);self.state.write_text('{"completed":false}');self.assertFalse(self.invoke()['finalized']);self.assertFalse(self.stamp.exists())
 def test_once_completed_removes_trigger_and_is_idempotent(self):
  self.complete();self.banner.write_text('Banner '+guard.RPI_SSH_BANNER+'\n');self.banner.chmod(0o644)
  # Emulate the root-owned file metadata required in the actual service.
  original=Path.stat
  def trusted_stat(path,*args,**kw):
   result=original(path,*args,**kw)
   if path==self.banner:
    data=list(result);data[4]=0;return os.stat_result(data)
   return result
  with patch.object(Path,'stat',trusted_stat):result=self.invoke()
  self.assertTrue(result['finalized']);self.assertFalse(self.request.exists());self.assertFalse(self.banner.exists());self.assertTrue(self.stamp.exists())
  self.request.write_text('finalize-v1\n');before=self.stamp.read_bytes();self.assertTrue(self.invoke()['alreadyFinalized']);self.assertEqual(self.stamp.read_bytes(),before);self.assertFalse(self.request.exists())
 def test_invalid_state_and_premature_request_fail_visibly(self):
  for state in ['broken','[]','{"completed":false}']:
   self.state.write_text(state);self.request.write_text('finalize-v1\n')
   with contextlib.redirect_stdout(io.StringIO()) as output,self.assertRaises(SystemExit):guard.finalize_setup_if_complete([])
   self.assertFalse(json.loads(output.getvalue())['success']);self.assertTrue(self.request.exists());self.assertFalse(self.stamp.exists())
 def test_unexpected_ssh_config_is_preserved(self):
  self.complete();self.banner.write_text('PasswordAuthentication yes\n')
  with contextlib.redirect_stdout(io.StringIO()),self.assertRaises(SystemExit):guard.finalize_setup_if_complete([])
  self.assertTrue(self.banner.exists());self.assertTrue(self.request.exists());self.assertFalse(self.stamp.exists())
 def test_ssh_failure_never_stamps_success_and_retry_validates(self):
  self.complete();self.command_mock.return_value=subprocess.CompletedProcess([],0,'active\n','');self.run_mock.side_effect=OSError('sshd preflight failure')
  with self.assertRaises(OSError):self.invoke()
  self.assertTrue(self.request.exists());self.assertFalse(self.stamp.exists())
  self.run_mock.side_effect=lambda args,label:self.calls.append(args);self.assertTrue(self.invoke()['finalized']);self.assertIn(['/usr/sbin/sshd','-t'],self.calls)
 def test_stamp_symlink_rejected(self):
  self.complete();target=self.root/'untrusted';target.write_text('account-handoff-finalized-v1\n');self.stamp.symlink_to(target)
  with contextlib.redirect_stdout(io.StringIO()),self.assertRaises(SystemExit):self.invoke()
  self.assertTrue(self.request.exists())
if __name__=='__main__':unittest.main(verbosity=2)
