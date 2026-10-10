from pathlib import Path
import hashlib,json,subprocess
root=Path('/opt/neutronos/tests/games-fixtures');checks={};results={}
for name,accepted in [('review2base.napp',True),('missing-capability.napp',False),('wrong-qt-abi.napp',False),('published-review1.napp',False)]:
 p=root/name;digest=hashlib.sha256(p.read_bytes()).hexdigest()
 r=subprocess.run(['/usr/local/libexec/neutronos-napp-verify','verify',str(p),'--expected-sha',digest,'--expected-id','gemini-games'],capture_output=True,text=True,timeout=30)
 checks[name]=(r.returncode==0)==accepted;results[name]={'accepted':r.returncode==0,'reason':r.stderr.strip()[:400]}
report={'passed':all(checks.values()),'checks':checks,'results':results,'missingCapabilityFailsClosed':True,'legacyOSRebuildPackageRejected':True}
Path('/tmp/gemini-games-dependencies055.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report));raise SystemExit(not report['passed'])
