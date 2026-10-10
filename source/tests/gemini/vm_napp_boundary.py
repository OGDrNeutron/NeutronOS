#!/usr/bin/python3
"""Exercise installed NAPP CLI and privileged verification on disposable packages."""
from pathlib import Path
import hashlib,json,runpy,shutil,subprocess
fixtures=Path('/opt/neutronos/tests/appstore/fixtures')
helper=runpy.run_path('/usr/local/libexec/neutronos-privileged-helper.real',run_name='gemini_validation')
stage=Path('/run/neutronos-appstore-guard');stage.mkdir(mode=0o700,exist_ok=True);stage.chmod(0o700)
checks={};errors={}
positive={'valid-gemini.napp','valid-gemini-update.napp'}
for p in sorted(fixtures.glob('*.napp')):
 digest=hashlib.sha256(p.read_bytes()).hexdigest()
 result=subprocess.run(['/usr/local/libexec/neutronos-napp-verify','verify',str(p),'--expected-sha',digest,'--expected-id','gemini-trust-test'],capture_output=True,text=True,timeout=30)
 wanted=p.name in positive
 checks['installedCLI:'+p.name]=(result.returncode==0)==wanted
 if result.returncode==0:
  parsed=json.loads(result.stdout);checks['signer:'+p.name]=parsed['signer']=='F1A1E10BD2DB35060D6E61187CEB773D5ABD64B0'
 target=stage/('gemini-validation-'+p.name);assert not target.exists()
 try:
  shutil.copyfile(p,target);target.chmod(0o600)
  try:
   package,manifest=helper['verify_signed_napp'](str(target),digest,'gemini-trust-test');accepted=True
  except SystemExit as exc:
   accepted=False;errors[p.name]=str(exc)[:400]
  checks['rootBoundary:'+p.name]=accepted==wanted
 finally:target.unlink(missing_ok=True)
key=Path('/etc/neutronos/keys/neutronos-release.gpg')
checks['sharedPublicTrustRoot']=key.exists() and key.stat().st_uid==0 and not key.stat().st_mode&0o022
checks['obsoleteAppStoreKeyAbsent']=not Path('/etc/neutronos/app-store-trusted-keys.json').exists()
report={'passed':all(checks.values()),'checks':checks,'rejectionReasons':errors,'installedBoundary':True,'usesSharedReleasePublicKey':True,'privateKeyUsed':False}
Path('/tmp/gemini-napp-installed-boundary.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'passed':report['passed'],'checks':len(checks)}));raise SystemExit(0 if report['passed'] else 1)
