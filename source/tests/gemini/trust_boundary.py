#!/usr/bin/python3
"""Exercise installed Update/Recovery verification without staging or applying."""
from pathlib import Path
import importlib.util,importlib.machinery,json,tempfile,shutil
p=Path('/usr/local/lib/neutronos/neutronos-update-recovery');loader=importlib.machinery.SourceFileLoader('release_boundary',str(p));spec=importlib.util.spec_from_loader(loader.name,loader);m=importlib.util.module_from_spec(spec);loader.exec_module(m)
d=Path('/opt/neutronos/tests/trust/fixtures');package=d/'gemini-release-disposable.nosupdate';tests={}
tests['officialValidSignedArtifactAccepted']=m.verify_release(package,d/'valid-envelope.json','0.5.5','0.5.4')['algorithm']=='OpenPGP'
for name in ['unsigned-envelope.json','bad-signature-envelope.json','unknown-envelope.json','hash-mismatch-envelope.json','manifest-disagreement-envelope.json']:
 try:m.verify_release(package,d/name,'0.5.5','0.5.4');tests[name+'Rejected']=False
 except m.Denied:tests[name+'Rejected']=True
with tempfile.TemporaryDirectory(prefix='neutronos-trust-negative-') as temp:
 changed=Path(temp)/package.name;shutil.copy2(package,changed);changed.write_bytes(changed.read_bytes()+b'changed')
 try:m.verify_release(changed,d/'valid-envelope.json','0.5.5','0.5.4');tests['modifiedPayloadRejected']=False
 except m.Denied:tests['modifiedPayloadRejected']=True
assert all(tests.values()),tests
print(json.dumps({'passed':True,'checks':tests,'productionRootBoundary':True,'sharedUpdateRecoveryTrustSource':str(m.PUBLIC_KEY),'privateKeyUsed':False},sort_keys=True))
