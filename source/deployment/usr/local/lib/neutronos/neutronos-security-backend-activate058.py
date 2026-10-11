#!/usr/bin/python3
"""Activate only the authenticated exact security-daemon deployment extension."""
from pathlib import Path
import hashlib,json,os,stat,tempfile,shutil
SOURCE=Path('/usr/local/lib/neutronos/security-update058-r1')
DEST=Path('/usr/local/lib/neutronos/neutronos-update-recovery')
STATE=Path('/var/lib/neutronos/update-recovery/backend-migrations/security058')
PREVIOUS='550d80dbb26c4cb1358b321d91fc104a9561a3733f9ea0f867075f2767b33058'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def immutable(p):
 s=p.lstat()
 if not stat.S_ISREG(s.st_mode) or s.st_uid!=0 or s.st_mode&0o022:raise RuntimeError('Unsafe signed backend extension input')
def install(src,dst,mode):
 fd,tmp=tempfile.mkstemp(prefix='.'+dst.name+'.',dir=dst.parent)
 try:
  with src.open('rb') as inp,os.fdopen(fd,'wb') as out:
   shutil.copyfileobj(inp,out);os.fchown(out.fileno(),0,0);os.fchmod(out.fileno(),mode);out.flush();os.fsync(out.fileno())
  os.replace(tmp,dst)
  directory=os.open(dst.parent,os.O_DIRECTORY)
  try:os.fsync(directory)
  finally:os.close(directory)
 finally:Path(tmp).unlink(missing_ok=True)
def activate():
 if os.geteuid()!=0:raise RuntimeError('Root activation required')
 if STATE.is_symlink():raise RuntimeError('Unsafe migration directory')
 for p in [SOURCE/'integrity.json',SOURCE/'neutronos-update-recovery',DEST]:immutable(p)
 hashes=json.loads((SOURCE/'integrity.json').read_text())
 if set(hashes)!={'neutronos-update-recovery'} or sha(SOURCE/'neutronos-update-recovery')!=hashes['neutronos-update-recovery']:raise RuntimeError('Signed extension integrity failed')
 version=json.loads(Path('/etc/neutronos/version.json').read_text())['version']
 if version not in ('0.5.7','0.5.8'):raise RuntimeError('Security backend extension requires Gemini 0.5.7')
 marker=STATE/'complete.json'
 if marker.exists():
  if sha(DEST)!=hashes['neutronos-update-recovery']:raise RuntimeError('Activated backend changed; refusing automatic replacement')
  return
 if sha(DEST) not in (PREVIOUS,hashes['neutronos-update-recovery']):raise RuntimeError('Canonical backend differs from approved 0.5.7; no replacement performed')
 STATE.mkdir(parents=True,exist_ok=True,mode=0o700)
 original=STATE/'original-backend'
 if not original.exists():install(DEST,original,stat.S_IMODE(DEST.stat().st_mode))
 else:immutable(original)
 try:
  install(SOURCE/'neutronos-update-recovery',DEST,0o755)
  if sha(DEST)!=hashes['neutronos-update-recovery']:raise RuntimeError('Canonical extension verification failed')
  fd,tmp=tempfile.mkstemp(prefix='.complete.',dir=STATE)
  with os.fdopen(fd,'w') as out:
   json.dump({'updateProtocol':2,'securityDaemonDestination':True,'sha256':sha(DEST),'previousSHA256':sha(original)},out);out.flush();os.fsync(out.fileno())
  os.replace(tmp,marker)
 except BaseException:
  install(original,DEST,stat.S_IMODE(original.stat().st_mode));raise
 print('Signed Security Policy v2 update support activated; OS remains '+version)
if __name__=='__main__':activate()
