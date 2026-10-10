from pathlib import Path
import importlib.util
import importlib.machinery
import json
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
def load(name,path):
    loader=importlib.machinery.SourceFileLoader(name,str(path))
    spec=importlib.util.spec_from_loader(name,loader)
    module=importlib.util.module_from_spec(spec);sys.modules[name]=module;loader.exec_module(module);return module
HELPER=load('gemini_helper',ROOT/'deployment/usr/local/libexec/neutronos-privileged-helper.real')
BOOT=load('gemini_bootstrap',ROOT/'deployment/usr/local/libexec/neutronos-security-bootstrap.py')
BT=load('gemini_bt',ROOT/'scripts/neutronos-controller-status-bridge.py')
class Services(unittest.TestCase):
    def test_failed_service_reports_actual_dependency_without_traceback(self):
        def command(args,**kw):
            if 'show' in args:return subprocess.CompletedProcess(args,0,'neutronos-security-bootstrap.service','')
            if 'is-failed' in args:return subprocess.CompletedProcess(args,1,'failed' if 'neutronos-security-bootstrap.service' in args else 'inactive','')
            return subprocess.CompletedProcess(args,0,"AttributeError: missing commissioning API\n",'')
        def failure():raise subprocess.CalledProcessError(1,['/usr/bin/systemctl','start','neutron-securityd.service'],stderr='dependency job failed')
        with patch.object(HELPER.subprocess,'run',side_effect=command):
            with self.assertRaises(SystemExit) as caught:HELPER.preference_step('Start Security Core',failure)
        message=str(caught.exception)
        self.assertIn('Start Security Core failed',message)
        self.assertIn('neutronos-security-bootstrap.service',message)
        self.assertIn('AttributeError: missing commissioning API',message)
        self.assertIn('journalctl -b',message)
        self.assertNotIn('Traceback',message)
    def test_missing_service_interpreter_file_is_actionable(self):
        def command(args,**kw):
            if 'show' in args:return subprocess.CompletedProcess(args,0,'neutronos-security-bootstrap.service','')
            if 'is-failed' in args:return subprocess.CompletedProcess(args,1,'failed' if 'neutronos-security-bootstrap.service' in args else 'inactive','')
            return subprocess.CompletedProcess(args,0,"/usr/bin/python3: can't open file '/run/example.py': [Errno 2] No such file or directory\n",'')
        def failure():raise subprocess.CalledProcessError(1,['/usr/bin/systemctl','start','neutron-securityd.service'],stderr='dependency job failed')
        with patch.object(HELPER.subprocess,'run',side_effect=command):
            with self.assertRaises(SystemExit) as caught:HELPER.preference_step('Start Security Core',failure)
        self.assertIn("can't open file '/run/example.py': [Errno 2]",str(caught.exception))
        self.assertNotIn('Traceback',str(caught.exception))
    def test_service_diagnostic_timeout_keeps_actionable_original_failure(self):
        def failure():raise subprocess.CalledProcessError(1,['/usr/bin/systemctl','start','neutron-securityd.service'],stderr='dependency job failed')
        with patch.object(HELPER.subprocess,'run',side_effect=subprocess.TimeoutExpired('systemctl show',10)):
            with self.assertRaises(SystemExit) as caught:HELPER.preference_step('Start Security Core',failure)
        message=str(caught.exception)
        self.assertIn('Start Security Core failed: dependency job failed',message)
        self.assertIn('diagnostics unavailable',message)
        self.assertIn('journalctl -b',message)
        self.assertNotIn('Traceback',message)
    def test_each_preference_branch_identifies_its_operation(self):
        for label in ['Apply security preferences','Apply performance preferences','Apply remote controller preferences','Stop Security Core','Finalize Security Core state']:
            def failure():raise OSError('fixture operation unavailable')
            with self.assertRaises(SystemExit) as caught:HELPER.preference_step(label,failure)
            self.assertIn(label+' failed',str(caught.exception))
    def test_watchdog_restored_when_finalizer_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            setup=Path(temp);prefs=setup/'preferences.json';prefs.write_text('{}')
            calls=[]
            def command(args,**kw):
                calls.append(args)
                if 'neutronos-security-first-login-finalize.py' in args[-1]:
                    raise subprocess.CalledProcessError(1,args,stderr='fixture reset failure')
                return subprocess.CompletedProcess(args,0,'','')
            with patch.object(HELPER,'SETUP_DIR',setup),patch.object(HELPER,'apply_security'),patch.object(HELPER,'apply_power'),patch.object(HELPER,'configure_remote'),patch.object(HELPER.subprocess,'run',side_effect=command):
                with self.assertRaises(SystemExit) as caught:HELPER.apply_preferences([str(prefs)])
            self.assertIn('Finalize Security Core state failed: fixture reset failure',str(caught.exception))
            self.assertIn(['/usr/bin/systemctl','stop','neutron-securityd.service','neutronos-security-bootstrap.service'],calls)
            actions=[(a[1],a[-1]) for a in calls if a[0]=='/usr/bin/systemctl']
            self.assertEqual(actions,[('is-active','neutron-security-watchdog.service'),('stop','neutron-security-watchdog.service'),('stop','neutronos-security-bootstrap.service'),('start','neutron-security-watchdog.service')])
    def test_bootstrap_uses_real_daemon_api_and_preserves_audit(self):
        from neutronos_ipc.authorization import AuthorizationPolicy
        policy=AuthorizationPolicy.load(ROOT/'config/security-authorization.json',require_root_owner=False)
        actual_load=AuthorizationPolicy.load
        with tempfile.TemporaryDirectory() as temp:
            state=Path(temp)/'core';setup=Path(temp)/'setup';setup.mkdir()
            finalized=setup/'security-finalized-v1';finalized.write_text('{}')
            with patch.multiple(BOOT,STATE_DIR=state,SETUP_DIR=setup,FINALIZED=finalized,
                COMMISSIONED=setup/'security-commissioned-v2',STATE=state/'state.json',
                DAEMON=ROOT/'deployment/usr/local/lib/neutronos/neutron-securityd.py',
                POLICY=ROOT/'config/security-authorization.json',PROJECT=ROOT), \
                patch.object(AuthorizationPolicy,'load',return_value=policy):
                self.assertEqual(BOOT.main(),0)
                result=json.loads((state/'state.json').read_text())
                self.assertTrue(BOOT.state_ready(result));self.assertTrue((setup/'security-commissioned-v2').exists())
                audit=(state/'audit.jsonl').read_bytes()
                self.assertEqual(BOOT.main(),0);self.assertEqual((state/'audit.jsonl').read_bytes(),audit)
    def test_bluez_pair_trust_connect_require_live_properties(self):
        live={'paired':False,'trusted':False,'connected':False}
        calls=[]
        def bluez(verb,address,**kw):
            calls.append((verb,kw.get('agent',False)))
            live[{'pair':'paired','trust':'trusted','connect':'connected'}[verb]]=True
            return subprocess.CompletedProcess([verb],0,'','')
        with patch.object(BT,'bluetooth_info',side_effect=lambda address:dict(live)),patch.object(BT,'bluez_command',side_effect=bluez):
            for verb in ['pair','trust','connect']:self.assertTrue(BT.run_bluez_verified('02:00:00:00:00:01',verb,1))
            self.assertTrue(BT.run_bluez_verified('02:00:00:00:00:01','pair',1))
        self.assertEqual(calls,[('pair',True),('trust',False),('connect',False)])
    def test_bluez_exit_zero_without_bond_is_rejected(self):
        with patch.object(BT,'bluetooth_info',return_value={'paired':False}),patch.object(BT,'bluez_command',return_value=subprocess.CompletedProcess([],0,'','')),patch.object(BT.time,'sleep'):
            self.assertFalse(BT.run_bluez_verified('02:00:00:00:00:01','pair',1))
if __name__=='__main__':unittest.main(verbosity=2)
