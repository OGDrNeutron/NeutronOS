"""Targeted regressions for the actual 0.5.5 trust/session/BlueZ boundaries."""
import importlib.util
import pwd
import subprocess
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from neutronos_ipc.sessions import verify_active_session
from neutronos_ipc.server import PeerCredentials

def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path);obj=importlib.util.module_from_spec(spec);sys.modules[name]=obj;spec.loader.exec_module(obj);return obj

class StabilizationTests(unittest.TestCase):
 def test_trusted_shell_can_read_live_security_for_its_active_human_session(self):
  account=SimpleNamespace(pw_name='fixturehuman',pw_uid=1000,pw_dir='/NeutronOS/fixturehuman',pw_shell='/bin/bash')
  peer=PeerCredentials(4321,999,985)
  session={'id':'fixture','user':account.pw_name}
  props={'Active':'yes','State':'active','User':'1000','Name':account.pw_name,'Remote':'no'}
  def check(**overrides):
   return verify_active_session(peer,session,property_loader=lambda _:dict(props,**overrides),cgroup_loader=lambda _:['/system.slice/neutronos.service'],trusted_system_shell=(999,'neutronos','/opt/neutronos/build/NeutronShell','/system.slice/neutronos.service'))
  with patch('neutronos_ipc.sessions.pwd.getpwnam',return_value=account),patch('neutronos_ipc.sessions.os.readlink',return_value='/opt/neutronos/build/NeutronShell'),patch('neutronos_ipc.sessions.os.stat',return_value=SimpleNamespace(st_uid=999)):
   self.assertTrue(check())
   self.assertFalse(check(Active='no'))
   self.assertFalse(check(User='1001'))
   self.assertFalse(check(Remote='yes'))
   with patch('neutronos_ipc.sessions.os.readlink',return_value='/tmp/attacker'):self.assertFalse(check())
 def test_controller_combo_uses_only_verified_local_display_session(self):
  account=SimpleNamespace(pw_name='fixturehuman',pw_uid=1000,pw_dir='/NeutronOS/fixturehuman',pw_shell='/bin/bash')
  peer=PeerCredentials(4321,999,985)
  props={'Active':'yes','State':'active','User':'999','Name':'neutronos','Remote':'no','Seat':'seat0','Type':'tty','Class':'user-early'}
  def check(**overrides):
   return verify_active_session(peer,{'id':'2','user':account.pw_name},property_loader=lambda _:dict(props,**overrides),cgroup_loader=lambda _:['/system.slice/neutronos.service'],trusted_system_shell=(999,'neutronos','/opt/neutronos/build/NeutronShell','/system.slice/neutronos.service'))
  with patch('neutronos_ipc.sessions.pwd.getpwnam',return_value=account),patch('neutronos_ipc.sessions.os.readlink',return_value='/opt/neutronos/build/NeutronShell'),patch('neutronos_ipc.sessions.os.stat',return_value=SimpleNamespace(st_uid=999)):
   self.assertTrue(check())
   for changes in ({'Active':'no'},{'Remote':'yes'},{'User':'1001'},{'Name':'attacker'},{'Seat':''},{'Class':'manager-early'},{'Type':'unspecified'}):self.assertFalse(check(**changes))
   with patch('neutronos_ipc.sessions.os.readlink',return_value='/tmp/attacker'):self.assertFalse(check())
 def test_bluez_timeout_is_reconciled_before_failure(self):
  bridge=module('gemini055_controller_bridge',ROOT/'scripts/neutronos-controller-status-bridge.py')
  states=[{'connected':False},{'connected':False},{'connected':True}]
  with patch.object(bridge,'bluetooth_info',side_effect=states),patch.object(bridge,'bluez_command',side_effect=subprocess.TimeoutExpired('bluetoothctl',14)),patch.object(bridge.time,'sleep'),patch.object(bridge,'publish') as publish:
   self.assertTrue(bridge.run_bluez_verified('02:00:00:00:00:01','connect',14))
   self.assertFalse(any(c.args[0]=='error' for c in publish.call_args_list))
 def test_legacy_os_rebuild_package_is_blocked_before_install(self):
  package=module('gemini055_package',ROOT/'scripts/neutronos-appstore-package.py')
  manifest={'id':'fixture','version':'1.0','name':'Fixture','platforms':['gemini'],'architectures':['amd64'],'rebuildRequired':True,'buildFiles':[{'source':'build/owned/backend.cpp','destination':'src/package_apps/fixture/backend.cpp'}]}
  with self.assertRaisesRegex(ValueError,'rebuild|precompiled|OS capability'):
   package.validate_manifest(manifest)

if __name__=='__main__':unittest.main()
