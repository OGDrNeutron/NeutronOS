#!/bin/bash
set -euo pipefail
python3 - <<'FIXTURE'
from pathlib import Path
import io,json,hashlib,tarfile,os
root=Path('/opt/neutronos/backups/system');root.mkdir(parents=True,exist_ok=True);root.chmod(0o700)
p=root/'gemini-validation-backup.tar.xz'
payload=b'{"offlineValidation":true}\n';name='payload/root/state/settings/.offline-validation.json'
manifest={'format':'NeutronOS Backup v2','product':'NeutronOS','codename':'Gemini','profile':'settings','created':'2026-10-06T00:00:00Z','NeutVersion':'0.5.0'}
files={'manifest.json':json.dumps(manifest).encode(),name:payload,'payload.sha256':(hashlib.sha256(payload).hexdigest()+'  '+name+'\n').encode()}
with tarfile.open(p,'w:xz') as archive:
 for name,data in files.items():
  info=tarfile.TarInfo(name);info.size=len(data);info.mode=0o600;info.uid=info.gid=0;archive.addfile(info,io.BytesIO(data))
p.chmod(0o600);sidecar=Path(str(p)+'.sha256');sidecar.write_text(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n');sidecar.chmod(0o600)
FIXTURE
/usr/local/lib/neutronos/neutronos-update-recovery stage-backup-restore /opt/neutronos/backups/system/gemini-validation-backup.tar.xz
systemd-run --unit=gemini-recovery-reboot055 --on-active=3s /usr/bin/systemctl reboot
