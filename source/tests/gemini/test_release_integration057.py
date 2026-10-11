"""Real signed updater transactions in its existing isolated test-root seam."""
import base64,hashlib,json,os,runpy,shutil,subprocess,sys,tempfile,unittest,zipfile
from pathlib import Path
W=Path('/gemini');V=W/'validation/integration057';FIX=V/'fixtures'
DEP=W/'source/deployment/usr/local/lib/neutronos'
sys.path.insert(0,str(DEP))
from neutronos_recovery_image import strict_json,valid_asset_url,decode_xz,ImageRecovery

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

class ReleaseIntegration(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(dir=V,prefix='transaction-');self.root=Path(self.temp.name)
  self.tree=self.root/'NeutronOS';self.tree.mkdir();self.write('NeutronOS/config/version.json','{"version":"0.5.6"}\n')
  for rel in ('etc/neutronos/version.json','etc/os-release','etc/issue','etc/issue.net'):
   self.write(rel,'{"version":"0.5.6"}\n' if rel.endswith('.json') else 'VERSION_ID="0.5.6"\n' if rel.endswith('os-release') else 'NeutronOS Gemini 0.5.6\n')
  self.write('NeutronOS/user-games/keep.rom','ORIGINAL USER GAME');self.write('NeutronOS/state/apps/games/library.json','{"favorite":"keep"}')
  os.environ['NEUTRONOS_UPDATE_TEST_ROOT']=str(self.root);os.environ.pop('NEUTRONOS_UPDATE_TEST_PUBLIC_KEY',None)
  self.c=runpy.run_path(str(DEP/'neutronos-update-recovery'),run_name='test_boundary057')
  self.f=self.c['stage_update'].__globals__
 def tearDown(self):self.temp.cleanup();os.environ.pop('NEUTRONOS_UPDATE_TEST_ROOT',None)
 def write(self,rel,data):
  p=self.root/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(data);return p
 def stage(self,name='complete'):
  self.c['stage_update'](FIX/name/'NeutronOS-Gemini-0.5.7.zip',FIX/name/'envelope.json','0.5.7')
 def transaction(self):
  pointer=json.loads((self.root/'state/active-transaction.json').read_text());return self.root/'state/transactions'/pointer['id']
 def apply(self):
  self.write('recovery/recovery-active.json','{"active":true,"mode":"UPDATE"}');self.c['apply_recovery_update']()
 def assert_old(self):
  self.assertEqual(json.loads((self.tree/'config/version.json').read_text())['version'],'0.5.6')
  self.assertIn('0.5.6',(self.root/'etc/os-release').read_text())
  self.assertEqual((self.tree/'user-games/keep.rom').read_text(),'ORIGINAL USER GAME')
 def test_complete_update_updates_all_versions_and_preserves_library(self):
  self.stage();self.assert_old();self.apply()
  for rel in ('NeutronOS/config/version.json','etc/neutronos/version.json','etc/os-release','etc/issue','etc/issue.net'):
   self.assertIn('0.5.7',(self.root/rel).read_text())
  self.assertEqual((self.tree/'user-games/keep.rom').read_text(),'ORIGINAL USER GAME')
  self.assertEqual(json.loads((self.tree/'state/apps/games/library.json').read_text()),{'favorite':'keep'})
  self.assertFalse((self.root/'state/active-transaction.json').exists());self.assertFalse((self.root/'recovery/next-boot.json').exists())
 def test_unmodified_r2_rejects_complete_package_before_any_write(self):
  old=runpy.run_path(str(V/'r2-updater'),run_name='r2_boundary')
  with self.assertRaisesRegex(old['Denied'],'manifest is invalid'):
   old['stage_update'](FIX/'complete/NeutronOS-Gemini-0.5.7.zip',FIX/'complete/envelope.json','0.5.7')
  self.assert_old();self.assertFalse((self.root/'state/active-transaction.json').exists())
 def test_existing_schema1_overlay_remains_supported(self):
  self.stage('overlay');self.apply();self.assertEqual(json.loads((self.tree/'config/version.json').read_text())['version'],'0.5.7')
  self.assertIn('0.5.6',(self.root/'etc/os-release').read_text()) # legacy overlay behavior preserved, not the complete upgrade
 def test_wrong_version_is_denied(self):
  self.write('NeutronOS/config/version.json','{"version":"0.5.5"}\n')
  with self.assertRaisesRegex(self.c['Denied'],'does not permit'):self.stage()
 def test_baseline_preimage_modification_is_denied(self):
  self.write('etc/issue','locally modified banner')
  with self.assertRaisesRegex(self.c['Denied'],'differs from the required baseline'):self.stage()
 def test_unsigned_metadata_is_denied(self):
  envelope=json.loads((FIX/'complete/envelope.json').read_text());raw=bytearray(base64.b64decode(envelope['metadata']));raw[4]^=1;envelope['metadata']=base64.b64encode(raw).decode();path=self.write('bad-envelope.json',json.dumps(envelope))
  with self.assertRaises(self.c['Denied']):self.c['stage_update'](FIX/'complete/NeutronOS-Gemini-0.5.7.zip',path,'0.5.7')
  self.assert_old()
 def test_tampered_package_is_denied(self):
  original=(FIX/'complete/NeutronOS-Gemini-0.5.7.zip').read_bytes();p=self.root/'NeutronOS-Gemini-0.5.7.zip';p.write_bytes(original+b'corrupt')
  with self.assertRaisesRegex(self.c['Denied'],'SHA-256'):self.c['stage_update'](p,FIX/'complete/envelope.json','0.5.7')
  self.assert_old()
 def test_system_allowlist_and_version_payload_are_enforced(self):
  for fixture,reason in [('outside','outside the exact allowlist'),('wrong-payload','Payload OS version')]:
   with self.assertRaisesRegex(self.c['Denied'],reason):self.stage(fixture)
   self.assert_old()
 def test_symlink_destination_is_denied(self):
  p=self.root/'etc/os-release';p.unlink();p.symlink_to(self.tree/'config/version.json')
  with self.assertRaisesRegex(self.c['Denied'],'symlink'):self.stage()
  self.assert_old()
 def test_write_failure_after_rename_rolls_back_including_current_file(self):
  self.stage();real=self.f['atomic_install'];failed=False
  def fail(source,dest,mode):
   nonlocal failed
   real(source,dest,mode)
   if dest==self.root/'etc/os-release' and not failed:
    failed=True;raise OSError('Injected failure after atomic rename')
  self.f['atomic_install']=fail
  with self.assertRaisesRegex(OSError,'Injected failure'):self.apply()
  self.assert_old();self.assertEqual(json.loads((self.transaction()/'apply-journal.json').read_text())['status'],'ROLLED_BACK')
 def test_interruption_restores_baseline_on_restart(self):
  self.stage()
  code='''import os,runpy\nfrom pathlib import Path\nc=runpy.run_path('/gemini/source/deployment/usr/local/lib/neutronos/neutronos-update-recovery',run_name='boundary');g=c['apply_update'].__globals__;real=g['atomic_install']\ndef kill(source,dest,mode):\n real(source,dest,mode)\n if str(dest).endswith('/etc/os-release'):os._exit(91)\ng['atomic_install']=kill\nc['apply_update']()\n'''
  r=subprocess.run([sys.executable,'-c',code],capture_output=True);self.assertEqual(r.returncode,91)
  with self.assertRaisesRegex(self.c['Denied'],'Interrupted update restored'):self.c['apply_update']()
  self.assert_old();self.apply();self.assertIn('0.5.7',(self.root/'etc/os-release').read_text())
 def test_committed_interruption_finalizes_without_reapplying(self):
  self.stage();real=self.f['atomic_json']
  def fail(path,value,*args,**kwargs):
   if path==self.root/'state/last-result.json':raise OSError('Injected finalization interruption')
   return real(path,value,*args,**kwargs)
  self.f['atomic_json']=fail
  with self.assertRaises(OSError):self.apply()
  self.f['atomic_json']=real;self.apply();self.assertEqual(json.loads((self.root/'state/last-result.json').read_text())['status'],'APPLIED')
 def test_real_device_installation_cannot_be_enabled_by_test_environment(self):
  with self.assertRaisesRegex(self.c['Denied'],'disabled in isolated test-root'):ImageRecovery(self.c).offline()
 def test_image_json_and_transport_reject_unsafe_inputs(self):
  with self.assertRaises(ValueError):strict_json('{"schema":1,"schema":2}')
  self.assertTrue(valid_asset_url('https://github.com/OGDrNeutron/NeutronOS/releases/download/gemini-0.5.7-r2/test.img.xz'))
  for url in ('http://github.com/OGDrNeutron/NeutronOS/releases/download/t/test.img.xz','https://github.com/other/NeutronOS/releases/download/t/test.img.xz','https://user:secret@github.com/OGDrNeutron/NeutronOS/releases/download/t/test.img.xz'):
   self.assertFalse(valid_asset_url(url))
 def test_xz_integrity_size_hash_and_trailing_data(self):
  import lzma
  data=b'unit image'*10000;source=self.root/'image.xz';source.write_bytes(lzma.compress(data));raw=self.root/'decoded.img'
  decode_xz(source,raw,len(data),hashlib.sha256(data).hexdigest());self.assertEqual(raw.read_bytes(),data)
  for value,maximum,expected in [(source.read_bytes()+b'trailing',len(data),hashlib.sha256(data).hexdigest()),(source.read_bytes(),100,'0'*64),(source.read_bytes()[:-8],len(data),hashlib.sha256(data).hexdigest())]:
   source.write_bytes(value);raw.unlink()
   with self.assertRaises((ValueError,lzma.LZMAError)):decode_xz(source,raw,maximum,expected)

if __name__=='__main__':unittest.main(verbosity=2)
