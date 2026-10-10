#!/usr/bin/python3
"""Exercise the installed SSH preference boundary after an explicit runtime loss."""
from pathlib import Path
import json,socket,subprocess,time

def run(args):return subprocess.run(args,capture_output=True,text=True,check=True,timeout=240)
def active(unit):return subprocess.run(['systemctl','is-active','--quiet',unit]).returncode==0
def listeners():
 rows=[]
 for table in ['/proc/net/tcp','/proc/net/tcp6']:
  for line in Path(table).read_text().splitlines()[1:]:
   f=line.split()
   if f[3]=='0A' and int(f[1].split(':')[1],16)==22:rows.append(f[1])
 return rows
assert next(Path('/sys/firmware/efi/efivars').glob('SecureBoot-*')).read_bytes()[4]==1
assert any(m in Path('/sys/kernel/security/lockdown').read_text() for m in ['[integrity]','[confidentiality]'])
for attempt in range(120):
 try:
  p=run(['runuser','-u','neutronos','--','/usr/local/libexec/gemini-network-probe','status']);network=json.loads(p.stdout)
  if network['state']=='CONNECTED' and network['ssid']=='GeminiRegression':break
 except Exception:pass
 time.sleep(1)
else:raise AssertionError('Saved Wi-Fi must be connected before the SSH continuation')
report={'passed':False,'signedUEFI':True,'kernelLockdown':True,'wifiBootReconnect':True,'reproducedMissingRuntimeBeforeEachEnable':True,'operations':[],'initialRuntimeRemovedOnlyWhileSshStopped':False}
p=Path('/tmp/gemini-ssh-runtime.json')
for enabled in [False,True,False,True]:
 if enabled:assert not Path('/run/sshd').exists()
 result=run(['runuser','-u','neutronos','--','/usr/local/libexec/gemini-setup-probe','finalize-ssh-'+('on' if enabled else 'off')]);print(result.stdout,flush=True)
 found=listeners();assert active('ssh.service')==enabled and bool(found)==enabled
 assert active('neutron-securityd.service') and active('neutron-security-watchdog.service')
 if enabled:
  assert Path('/run/sshd').is_dir()
  assert subprocess.run(['systemctl','is-enabled','--quiet','ssh.service']).returncode==0
  with socket.create_connection(('127.0.0.1',22),timeout=5) as s:assert s.recv(512).startswith(b'SSH-2.0-OpenSSH_')
 else:
  assert not active('ssh.socket')
  # On a boot where ssh.service was never active, tmpfiles may have created
  # this directory independently. Remove ONLY this empty disposable runtime
  # after proving both SSH units and TCP/22 are inactive, to reproduce loss.
  runtime=Path('/run/sshd')
  if runtime.exists():
   assert runtime.is_dir() and not runtime.is_symlink() and not list(runtime.iterdir())
   assert runtime.stat().st_uid==0
   runtime.rmdir();report['initialRuntimeRemovedOnlyWhileSshStopped']=True
  assert not runtime.exists()
 report['operations'].append({'sshEnabled':enabled,'active':enabled,'listeners':found});p.write_text(json.dumps(report,indent=2)+'\n')
for attempt in range(120):
 if active('neutronos-recovery-ui.service') and active('neutronos-compositor.service'):break
 time.sleep(1)
else:raise AssertionError('Actual Recovery presentation must be running')
assert not active('neutronos.service')
s=json.loads(run(['runuser','-u','neutronos','--','sudo','-n','/usr/local/sbin/neutronos-privileged-helper','recovery-status']).stdout)
assert s['success'] and s['active'] and s['mode']=='BACKUP_RESTORE'
assert any(row['verified'] and row['name']=='gemini-validation-backup.tar.xz' for row in s['recoveryPoints'])
assert s['transaction']['status']=='RECOVERY_STARTED'
Path('/tmp/gemini-recovery-status.json').write_text(json.dumps(s,indent=2)+'\n')
report['passed']=True;report['realRecoveryHelperAndPresentation']=True;p.write_text(json.dumps(report,indent=2)+'\n')
print('GEMINI_VM_SETUP_COMPLETION_BACKEND_PASS',flush=True)
print('GEMINI_VM_RECOVERY_HELPER_PASS',flush=True)
print('GEMINI_VM_RECOVERY_READY',flush=True)
