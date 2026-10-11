#!/usr/bin/python3
"""One-shot activation of the signed App Store backend prerequisite.

Installed canonical backend files become OS-owned, rather than uninstallable
App Store payloads. Only independently root-owned, immutable library inputs are
accepted. The backend is committed last; the original R2 backend is retained.
"""
from pathlib import Path
import hashlib,json,os,shutil,stat,subprocess,tempfile
SOURCE=Path('/usr/local/lib/neutronos/update-recovery-protocol2-r3')
DEST=Path('/usr/local/lib/neutronos')
STATE=Path('/var/lib/neutronos/update-recovery/backend-migrations/protocol2')
NAMES=('neutronos_recovery_image.py','neutronos-update-recovery')

def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def immutable(p):
 info=p.lstat()
 if not stat.S_ISREG(info.st_mode) or info.st_uid!=0 or info.st_mode&0o022:raise RuntimeError('Unsafe backend prerequisite input')

def atomic_copy(source,dest,mode):
 dest.parent.mkdir(parents=True,exist_ok=True)
 fd,temporary=tempfile.mkstemp(prefix='.'+dest.name+'.',dir=dest.parent)
 try:
  with source.open('rb') as inp,os.fdopen(fd,'wb') as out:
   shutil.copyfileobj(inp,out);out.flush();os.fchmod(out.fileno(),mode);os.fchown(out.fileno(),0,0);os.fsync(out.fileno())
  os.replace(temporary,dest)
  directory=os.open(dest.parent,os.O_DIRECTORY)
  try:os.fsync(directory)
  finally:os.close(directory)
 finally:
  Path(temporary).unlink(missing_ok=True)

def activate():
 if os.geteuid()!=0:raise RuntimeError('Root activation is required')
 if STATE.is_symlink():raise RuntimeError('Unsafe migration state')
 marker=STATE/'complete.json'
 if marker.exists():return
 version=json.loads(Path('/etc/neutronos/version.json').read_text())['version']
 if version!='0.5.6':
  result=subprocess.run([str(DEST/'neutronos-update-recovery'),'protocol-version'],capture_output=True,text=True,check=True,timeout=10)
  if json.loads(result.stdout).get('updateProtocol',0)>=2:
   STATE.mkdir(parents=True,exist_ok=True,mode=0o700)
   fd,temporary=tempfile.mkstemp(prefix='.compatible.',dir=STATE)
   with os.fdopen(fd,'w') as out:
    json.dump({'updateProtocol':2,'imageProtocol':1,'existingCompatibleBackendPreserved':True},out);out.flush();os.fsync(out.fileno())
   os.replace(temporary,marker)
   print('Compatible OS-owned backend is already installed; no downgrade or replacement performed.');return
  raise RuntimeError('Backend migration requires unchanged Gemini 0.5.6')
 immutable(SOURCE/'integrity.json');hashes=json.loads((SOURCE/'integrity.json').read_text())
 if set(hashes)!=set(NAMES):raise RuntimeError('Incomplete prerequisite integrity inventory')
 for name in NAMES:
  immutable(SOURCE/name)
  if digest(SOURCE/name)!=hashes[name]:raise RuntimeError('Prerequisite integrity check failed')
 STATE.mkdir(parents=True,exist_ok=True,mode=0o700)
 snapshots=STATE/'originals';snapshots.mkdir(exist_ok=True,mode=0o700)
 # Preserve original data once; retry after power loss never replaces the original.
 for name in NAMES:
  original=snapshots/name;absent=snapshots/(name+'.absent');dest=DEST/name
  if not original.exists() and not absent.exists():
   if dest.exists():immutable(dest);atomic_copy(dest,original,stat.S_IMODE(dest.stat().st_mode))
   else:absent.touch(mode=0o600)
 # The importing backend is committed after its fully verified companion.
 try:
  for name in NAMES:atomic_copy(SOURCE/name,DEST/name,0o755 if name.endswith('neutronos-update-recovery') else 0o644)
 except BaseException:
  for name in reversed(NAMES):
   original=snapshots/name
   if original.exists():atomic_copy(original,DEST/name,stat.S_IMODE(original.stat().st_mode))
   else:(DEST/name).unlink(missing_ok=True)
  raise
 for name in NAMES:
  if digest(DEST/name)!=hashes[name]:raise RuntimeError('Canonical backend verification failed')
 fd,temporary=tempfile.mkstemp(prefix='.complete.',dir=STATE)
 with os.fdopen(fd,'w') as out:
  json.dump({'updateProtocol':2,'imageProtocol':1,'hashes':hashes,'originalBackendPreserved':True},out);out.write('\n');out.flush();os.fsync(out.fileno())
 os.replace(temporary,marker)
 print('Signed Update/Recovery prerequisite activated; OS version remains 0.5.6 until the complete OS update.')

if __name__=='__main__':activate()
