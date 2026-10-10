"""Exercise real local filesystem/configuration paths. Real FUSE/Wine tests run separately in the VM."""
import importlib.util,json,os,shutil,struct,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('games_manager',Path(__file__).resolve().parents[1]/'scripts/games_manager.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class ManagerTests(unittest.TestCase):
 def setUp(self):
  self.temporary=tempfile.TemporaryDirectory(prefix='manager-',dir=ROOT/'build/tmp');self.home=Path(self.temporary.name);self.manager=m.Manager(self.home);self.folder=self.home/'Existing Game';self.folder.mkdir();self.exe=self.folder/'game.exe';self.exe.write_bytes(self.pe());self.config={'runtime':'wine','arguments':['--safe','a b'],'environment':{'WINEDEBUG':'-all'}}
 def tearDown(self):self.temporary.cleanup()
 @staticmethod
 def pe():
  b=bytearray(128);b[:2]=b'MZ';b[60:64]=struct.pack('<I',64);b[64:70]=b'PE\0\0\x64\x86';return b
 def imported(self):return self.manager.register({'path':str(self.exe),'configuration':self.config})['game']
 def test_discovery_does_not_execute_local_user_runtime(self):
  binary=self.home/'.wine-versions/untrusted/bin/wine';binary.parent.mkdir(parents=True);marker=self.home/'executed';binary.write_text('#!/bin/sh\ntouch "'+str(marker)+'"\n');binary.chmod(0o755)
  rows=self.manager.discover();self.assertFalse(marker.exists());self.assertTrue(any(r['program']==str(binary) and 'unverified' in r['version'] for r in rows))
 def test_fresh_wine_prefix_has_safe_standard_drive_mappings(self):
  prefix=self.manager.safe_state('prefixes/'+'c'*64);devices=self.manager.prepare_wine_drives(prefix)
  self.assertEqual((devices/'c:').resolve(),prefix/'drive_c');self.assertEqual((devices/'z:').resolve(),Path('/'));self.manager.prepare_wine_drives(prefix)
  (devices/'c:').unlink();(devices/'c:').symlink_to(self.folder)
  with self.assertRaisesRegex(ValueError,'redirected'):self.manager.prepare_wine_drives(prefix)
  self.assertTrue(self.exe.exists())
 def test_import_missing_runtime_is_persistent_without_install(self):
  before=self.exe.read_bytes();g=self.imported();self.assertEqual(g['configuration']['runtime'],'wine');self.assertEqual(m.Manager(self.home).load()[g['id']]['path'],str(self.exe));self.assertEqual(self.exe.read_bytes(),before);self.assertFalse((self.manager.state/'prefixes').exists())
 def test_configuration_keeps_runtime_arguments_environment_and_directory(self):
  g=self.imported();self.manager.configure({'id':g['id'],'configuration':{**self.config,'arguments':['--renderer','legacy'],'workingDirectory':str(self.folder),'environment':{'WINEDLLOVERRIDES':'ddraw=n,b'}}});c=self.manager.load()[g['id']]['configuration'];self.assertEqual(c['arguments'],['--renderer','legacy']);self.assertEqual(c['environment']['WINEDLLOVERRIDES'],'ddraw=n,b')
 def test_protected_paths_symlinks_and_bad_configuration_are_rejected(self):
  for p in ('/etc/passwd','/usr/bin/python3'):
   with self.assertRaises(ValueError):self.manager.authorized(p)
  (self.folder/'escape').symlink_to('/etc');
  with self.assertRaises(ValueError):self.manager.authorized(self.folder/'escape/passwd')
  for configuration in ({'runtime':'wine','arguments':'-bad'},{'runtime':'wine','environment':{'LD_PRELOAD':'/tmp/evil.so'}},{'runtime':'wine','workingDirectory':str(self.home)}):
   with self.assertRaises(ValueError):self.manager.register({'path':str(self.exe),'configuration':configuration})
 def test_iso_exe_msi_detection_rejects_unsupported_formats(self):
  self.assertEqual(m.file_kind(self.exe),'exe');msi=self.home/'game.msi';msi.write_bytes(bytes.fromhex('d0cf11e0a1b11ae1')+bytes(512));self.assertEqual(m.file_kind(msi),'msi')
  iso=self.home/'disc.iso';data=bytearray(65536);data[32769:32774]=b'CD001';iso.write_bytes(data);self.assertEqual(m.file_kind(iso),'iso9660');data[32769:32774]=b'BEA01';iso.write_bytes(data)
  with self.assertRaisesRegex(ValueError,'Unsupported disc format'):m.file_kind(iso)
  invalid=self.home/'fake.exe';invalid.write_text('not PE');
  with self.assertRaises(ValueError):m.file_kind(invalid)
 def test_multiple_installers_are_listed_not_automatically_chosen(self):
  for n in ('setup.exe','install.exe'): (self.folder/n).write_bytes(self.pe())
  listing=self.manager.inspect({'path':str(self.folder)})['candidates'];self.assertEqual({c['name'] for c in listing},{'game.exe','setup.exe','install.exe'})
 def test_runtime_missing_install_does_not_create_prefix_or_approve_install(self):
  with self.assertRaisesRegex(ValueError,'approval'):self.manager.install({'path':str(self.exe)})
  result=self.manager.install({'path':str(self.exe),'configuration':{'runtime':'wine','runtimeProgram':str(self.home/'absent/wine')},'approved':True});self.assertTrue(result['runtimeMissing']);self.assertFalse((self.manager.state/'prefixes').exists());self.assertEqual(m.Manager(self.home).load()[result['game']['id']]['status'],'runtime-missing');self.assertEqual(result['game']['mode'],'pending-installation');self.assertEqual(self.exe.read_bytes(),self.pe())
 def test_pending_installation_cannot_be_misclassified_as_a_ready_import(self):
  result=self.manager.install({'path':str(self.exe),'configuration':{'runtime':'wine','runtimeProgram':str(self.home/'absent/wine')},'approved':True});game=result['game']
  with self.assertRaisesRegex(ValueError,'pending installation'):self.manager.configure({'id':game['id'],'configuration':self.config,'executable':str(self.exe)})
  self.manager.remove({'id':game['id'],'approved':True});self.assertTrue(self.exe.exists());self.assertFalse((self.manager.state/'prefixes').exists())
 def test_patch_requires_content_bound_confirmation_and_rolls_back(self):
  g=self.imported();patch=self.home/'replacement.exe';patch.write_bytes(self.pe()+b'fix');original=self.exe.read_bytes();r={'id':g['id'],'source':str(patch),'target':str(self.exe)};preview=self.manager.patch_preview(r)['preview'];self.assertEqual(preview['originalSHA256'],m.digest(self.exe))
  with self.assertRaises(ValueError):self.manager.patch_apply({**r,'token':preview['token']})
  patch.write_bytes(patch.read_bytes()+b'changed');
  with self.assertRaisesRegex(ValueError,'changed'):self.manager.patch_apply({**r,'token':preview['token'],'approved':True})
  preview=self.manager.patch_preview(r)['preview'];self.manager.patch_apply({**r,'token':preview['token'],'approved':True});self.assertEqual(self.exe.read_bytes(),patch.read_bytes());self.assertTrue(self.manager.patches(g['id'])[0]['active']);self.manager.patch_restore({'id':g['id'],'target':str(self.exe),'approved':True});self.assertEqual(self.exe.read_bytes(),original)
 def test_patch_never_overwrites_later_user_changes(self):
  g=self.imported();patch=self.home/'patch.exe';patch.write_bytes(self.pe()+b'fix');r={'id':g['id'],'source':str(patch),'target':str(self.exe)};preview=self.manager.patch_preview(r)['preview'];self.manager.patch_apply({**r,'token':preview['token'],'approved':True});self.exe.write_bytes(b'new-user-change')
  with self.assertRaisesRegex(ValueError,'changed'):self.manager.patch_restore({'id':g['id'],'target':str(self.exe),'approved':True})
  self.assertEqual(self.exe.read_bytes(),b'new-user-change')
 def test_patch_cannot_touch_another_game(self):
  g=self.imported();other=self.home/'other.exe';other.write_bytes(self.pe())
  with self.assertRaisesRegex(ValueError,'inside this game'):self.manager.patch_preview({'id':g['id'],'source':str(self.exe),'target':str(other)})
 def test_removal_preserves_files_saves_and_prefixes(self):
  g=self.imported();save=self.folder/'save.dat';save.write_bytes(b'valuable save');prefix=self.manager.state/'prefixes'/g['id'];prefix.mkdir(parents=True);(prefix/'save').write_bytes(b'prefix save')
  with self.assertRaises(ValueError):self.manager.remove({'id':g['id']})
  self.manager.remove({'id':g['id'],'approved':True});self.assertEqual(self.manager.load(),{});self.assertTrue(self.exe.is_file());self.assertEqual(save.read_bytes(),b'valuable save');self.assertEqual((prefix/'save').read_bytes(),b'prefix save')
 def test_folder_browser_respects_access_and_reports_long_paths(self):
  nested=self.folder/('Long Game Folder '*8);nested.mkdir();listing=self.manager.browse(str(self.folder));self.assertTrue(any(x['path']==str(nested) for x in listing['entries']));self.assertTrue(any(x['path']==str(self.exe) for x in listing['entries']))
  with self.assertRaises(ValueError):self.manager.browse('/etc')
 def test_dos_detection_and_explicit_dosbox_selection(self):
  dos=self.folder/'legacy.exe';dos.write_bytes(b'MZ'+bytes(126));self.assertEqual(m.file_kind(dos),'dos')
  with self.assertRaises(ValueError):self.manager.register({'path':str(dos),'configuration':{'runtime':'wine'}})
  game=self.manager.register({'path':str(dos),'configuration':{'runtime':'dosbox'}})['game'];self.assertEqual(game['kind'],'dos')
 def test_scummvm_data_folder_import_keeps_original_data(self):
  data=self.folder/'monkey.000';data.write_bytes(b'user game data')
  g=self.manager.register({'path':str(self.folder),'configuration':{'runtime':'scummvm','scummvmGameId':'monkey'}})['game'];self.assertEqual(g['kind'],'scummvm');self.assertEqual(data.read_bytes(),b'user game data');self.assertEqual(self.manager.load()[g['id']]['root'],str(self.folder))
 def test_managed_uninstall_removes_only_unchanged_owned_assets(self):
  identity='a'*64;root=self.manager.state/'prefixes'/identity/'drive_c';root.mkdir(parents=True)
  (root/'game.exe').write_bytes(self.pe());(root/'game.pak').write_bytes(b'owned asset');(root/'save.dat').write_bytes(b'precious save')
  inventory=self.manager.inventory(root);(root/'user-note.txt').write_bytes(b'unrelated user data');(root/'game.pak').write_bytes(b'user modification')
  game={'id':identity,'mode':'managed','root':str(root),'path':str(root/'game.exe'),'installedFiles':inventory,'status':'ready'};self.manager.save({identity:game})
  plan=self.manager.uninstall_plan({'id':identity})['uninstallPlan'];self.assertEqual([p['path'] for p in plan['remove']],[str(root/'game.exe')])
  with self.assertRaises(ValueError):self.manager.uninstall({'id':identity,'token':plan['token']})
  self.manager.uninstall({'id':identity,'token':plan['token'],'approved':True});self.assertFalse((root/'game.exe').exists());self.assertEqual((root/'save.dat').read_bytes(),b'precious save');self.assertEqual((root/'user-note.txt').read_bytes(),b'unrelated user data');self.assertEqual((root/'game.pak').read_bytes(),b'user modification')
 def test_managed_prefix_redirection_is_blocked_before_patch_or_uninstall(self):
  identity='b'*64;prefix=self.manager.state/'prefixes'/identity;prefix.mkdir(parents=True);(prefix/'drive_c').symlink_to(self.folder)
  game={'id':identity,'mode':'managed','root':str(prefix/'drive_c'),'path':str(self.exe),'configuration':{'runtime':'wine'}};self.manager.save({identity:game})
  patch=self.home/'local.dat';patch.write_bytes(b'patch')
  for operation in (lambda:self.manager.patch_preview({'id':identity,'source':str(patch),'target':str(self.exe)}),lambda:self.manager.uninstall_plan({'id':identity})):
   with self.assertRaises(ValueError):operation()
  self.assertEqual(self.exe.read_bytes(),self.pe())
if __name__=='__main__':unittest.main(verbosity=2)
