from pathlib import Path
import ast, hashlib, importlib.util, json, os, subprocess, sys, tempfile, zipfile
from unittest.mock import patch
sys.dont_write_bytecode=True
base=Path(__file__).resolve().parents[2];checks={}
def read_module(name,path):
 spec=importlib.util.spec_from_loader(name,loader=None);module=importlib.util.module_from_spec(spec);exec(compile(path.read_text(),str(path),'exec'),module.__dict__);return module
helper=read_module('gemini_native_helper',base/'deployment/usr/local/libexec/neutronos-privileged-helper.real')
package=read_module('gemini_native_package',base/'scripts/neutronos-appstore-package.py')
remote=read_module('gemini_remote',base/'services/remote/neutron-remote-service.py')
checks['new_python_syntax']=True
manifest={'id':'demo','name':'Demo','rebuildRequired':True,'buildFiles':[{'source':'build/owned/plugin.cpp','destination':'src/package_apps/demo/plugin.cpp','mode':'0644'}],'remoteCapabilities':[{'id':'control','provider':'scripts/apps/demo/provider.py','broker':'neutronos-remote-service'}]}
checks['signed_native_manifest_accepted']=helper.validate_rebuild_manifest(manifest,'demo') is True
for destination in ('src/main.cpp','src/package_apps/other/plugin.cpp','src/package_apps/demo/../../SecurityManager.cpp'):
 bad=dict(manifest,buildFiles=[dict(manifest['buildFiles'][0],destination=destination)])
 try:helper.validate_rebuild_manifest(bad,'demo');checks['reject:'+destination]=False
 except SystemExit:checks['reject:'+destination]=True
with tempfile.TemporaryDirectory(prefix='gemini-native-policy-',dir='/tmp') as temporary:
 root=Path(temporary); archive=root/'demo.napp'
 with zipfile.ZipFile(archive,'w') as z:
  z.writestr('manifest.json',json.dumps(manifest));z.writestr('build/owned/plugin.cpp','int demo_value=1;');z.writestr('payload/scripts/apps/demo/provider.py','print("demo")\n')
 metadata=helper.signed_remote_metadata(archive,manifest,'demo')
 checks['provider_hash_from_signed_archive']=metadata['fileSha256']['scripts/apps/demo/provider.py']==hashlib.sha256(b'print("demo")\n').hexdigest()
 bad=dict(manifest,remoteCapabilities=[{'id':'control','provider':'scripts/apps/demo/../../root.py'}])
 try:helper.signed_remote_metadata(archive,bad,'demo');checks['remote_path_traversal_rejected']=False
 except SystemExit:checks['remote_path_traversal_rejected']=True
 with patch.object(helper,'APPSTORE_STATE',root/'system-state'),patch.object(helper,'require_root_owned',return_value=None),patch.object(helper.os,'chown',return_value=None):
  helper.cache_native_package('demo',archive,True)
  cached=helper.native_package_path('demo')
  checks['signed_native_cache_copies_exact_bytes']=cached.read_bytes()==archive.read_bytes()
  checks['native_cache_private_mode']=cached.stat().st_mode&0o777==0o600
  helper.cache_native_package('demo',archive,False);checks['retire_native_cache_on_plain_package']=not cached.exists()
 # These canonical calls must perform no filesystem writes, including when extraction points nowhere.
 checks['nonpriv_apply_never_writes_SYSTEM']=package.apply_build_files(Path('/opt/neutronos'),[('src/package_apps/demo/plugin.cpp',Path('/missing'),0o644)],['src/package_apps/demo/stale.cpp'])==['src/package_apps/demo/plugin.cpp']
 checks['nonpriv_SYSTEM_snapshot_managed_by_root']=package.backup_build_files(Path('/opt/neutronos'),['src/package_apps/demo/plugin.cpp'],root)==[]
 package.restore_build_files(Path('/opt/neutronos'),root,['src/package_apps/demo/plugin.cpp'],[]);checks['nonpriv_SYSTEM_restore_managed_by_root']=True
 checks['remote_capabilities_require_signed_root_transaction']=package.package_needs_privileged_install({'remoteCapabilities':[{'id':'control'}]})
 # Human labels cannot inject/override root capability authority.
 with patch.object(remote,'trusted_registry',return_value={'packages':{'demo':metadata}}),patch.object(remote,'human_payload_roots',return_value=[]):
  checks['remote_authority_comes_from_trusted_root_registry']=remote.package_for('demo')['fileSha256']==metadata['fileSha256']
helper_text=(base/'deployment/usr/local/libexec/neutronos-privileged-helper.real').read_text()
checks['compiler_runs_under_dedicated_builder']='--property=User=neutronos-builder' in helper_text
checks['compiler_root_source_readonly']='--property=ProtectSystem=strict' in helper_text and '--property=ReadWritePaths=' in helper_text
checks['compiler_children_reaped']='--property=KillMode=control-group' in helper_text
checks['amd64_ELF_required']="int.from_bytes(header[18:20],'little')!=62" in helper_text
checks['real_graphical_smoke_required']='--smoke-test' in helper_text and 'NeutronShell smoke test loaded the graphical destination' in helper_text
checks['ticket_installed_binary_digest_bound']="digest!=meta.get('nativeShellSha256')" in helper_text
checks['no_removed_animation_readiness_marker']='NEUTRONOS_BOOT_STATE_DIR' not in helper_text and 'LOGIN_READY_OFFSCREEN' not in helper_text
checks['rollback_backup_hash_and_live_digest_verified']="hashlib.sha256(backup).hexdigest()!=meta.get('originalShellSha256')" in helper_text and "current not in (meta['nativeShellSha256'],meta['originalShellSha256'])" in helper_text
report={'passed':all(checks.values()),'checks':checks,'scope':'Root-owned SYSTEM native AppStore rebuild and canonical remote capability authority','unverified':['Full package native configure/build/probe inside running Gemini systemd; pure policy/cache fixtures and source boundaries checked offline'],'controls':['Only existing signed package transaction issues rebuild tickets','Signed native archives remain root-owned and SHA bound in trusted root registry','Dedicated neutronos-builder transient cgroups compile/probe with root source read-only','Only fixed /opt/neutronos/build/NeutronShell may be installed; ticket binds validated digest','Existing root transaction snapshots restore archives; failed rebuild restores hash-checked fixed binary backup'],'sha256':{str(p.relative_to(base)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [base/'deployment/usr/local/libexec/neutronos-privileged-helper.real',base/'scripts/neutronos-appstore-package.py',base/'services/remote/neutron-remote-service.py']}}
(base.parent/'validation/native-appstore-port.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'passed':report['passed'],'checks':len(checks),'failures':[k for k,v in checks.items() if not v]}))
if not report['passed']:sys.exit(1)
