from pathlib import Path
import ast, hashlib, importlib.util, json, os, pwd, re, subprocess, sys
from types import SimpleNamespace
from unittest.mock import patch
sys.dont_write_bytecode = True
base=Path(__file__).resolve().parents[2]
checks={}; evidence={}
files=['scripts/neutronos-browser-supervisor.py','scripts/neutronos-game-supervisor.py','scripts/neutronos-privileged-helper-guard.py','scripts/neutronos-appstore-package.py','deployment/usr/local/libexec/neutronos-privileged-helper.real','deployment/usr/local/libexec/neutronos-human-storage-owner.py']
for rel in files:
 ast.parse((base/rel).read_text());checks['syntax:'+rel]=True
# Exercise the public package path API without installing a package or touching a disk.
spec=importlib.util.spec_from_file_location('gemini_package',base/'scripts/neutronos-appstore-package.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
checks['package_paths_canonical']=module.app_store_paths(Path('/NeutronOS/alice'))==(Path('/NeutronOS/alice/apps'),Path('/NeutronOS/alice/apps/installed.json'),Path('/NeutronOS/alice/apps/payload'))
checks['second_human_is_distinct']=module.app_store_paths(Path('/NeutronOS/bob'))[0]==Path('/NeutronOS/bob/apps')
# Pure isolated execution of the actual supervisor validator with supplied NSS/kernel fixtures.
for rel in files[:2]:
 tree=ast.parse((base/rel).read_text());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='verified_human')
 ns={'pwd':pwd,'Path':Path,'re':re,'os':os,'subprocess':subprocess};exec(compile(ast.Module(body=[fn],type_ignores=[]),rel,'exec'),ns)
 human=SimpleNamespace(pw_uid=1000,pw_gid=1000,pw_dir='/NeutronOS/alice',pw_name='alice',pw_shell='/bin/bash');service=SimpleNamespace(pw_uid=999)
 def run_case(home='/NeutronOS/alice',mount=True,exe='/opt/neutronos/build/NeutronShell',cgroup='0::/system.slice/neutronos.service\n',peer_uid=999,human_uid=1000):
  human.pw_uid=human_uid
  with patch('pwd.getpwnam',side_effect=lambda n:service if n=='neutronos' else human),patch('os.path.ismount',return_value=mount),patch.object(Path,'is_symlink',return_value=False),patch.object(Path,'is_dir',return_value=True),patch('subprocess.run',return_value=SimpleNamespace(stdout='321\n')),patch('os.readlink',return_value=exe),patch('os.stat',return_value=SimpleNamespace(st_uid=peer_uid)),patch.object(Path,'read_text',return_value=cgroup):
   try: ns['verified_human']('alice',home);return True
   except ValueError:return False
 cases={'canonical_human_accepted':run_case(),'wrong_home_rejected':not run_case(home='/home/alice'),'unmounted_DATA_rejected':not run_case(mount=False),'foreign_shell_rejected':not run_case(exe='/usr/bin/python3'),'wrong_peer_rejected':not run_case(peer_uid=1000),'foreign_unit_rejected':not run_case(cgroup='0::/other.service\n'),'service_as_human_rejected':not run_case(human_uid=999)}
 checks.update({rel+':'+k:v for k,v in cases.items()})
# Canonical migration must retain authoritative hostkey/controller implementation bodies.
# AST hashes captured read-only from installed authoritative Apollo 1.0.0 helper.
expected_baseline={'_valid_ssh_host_key': '969a16ea9eee5402fe0b4dc94295adfb885d6e3589bfbe5edcde2853cbc6ba5b', '_ssh_hostkey_diagnostic': '02c4fd1fc7a60389289305d2abb9f72c0d999811038bcfb7a13745688a86b917', '_clean_ssh_host_keys': '0f7de14f11a25b722857a0dfca4b835b28d86be6e9895b089a79f8a5ac9552cf', '_generate_ssh_host_keys': 'e2a1d1d1c62f3d7e5199ed9a1eb5f21c32f5f79e333bb8120d151ed9f296379b', '_verify_ssh_host_keys': 'c808641585705ddafd8956bd1650cc22e8627f1dbb21496df03460579336a89f', 'prepare_ssh_host_keys': 'd9304c64d47434ab9d7876f9c0795874b13e8145b9fea5cdb52b4c4e2d709ba6', 'generate_ssh_host_keys': '649bfbc438b869a0bdd12074fc3829842c6033b46665d4c5268dbc746c2cc6e5', 'verify_ssh_host_keys': '06c881904f0acba625cc119e5750c2c59aaa05b20403543906d13817578cb6e5', '_ensure_ssh_host_keys': 'cca480628a74393f243796546b08607028c868225034fbc562f78f0a5509cf7a', 'prepare_controller_bluetooth': 'ccf3762f5a1f0fc38827ac303e4f5e38bc7d881667fc010b765b56fc8223638a', 'apply_ssh_preferences': '72c67e6b824e0ce35e108df53dcf6a6537fd40c1b80f8530bf939307f8d91328', 'prepare_ssh_preferences': '0fe2bcd958a3cb29db5f4c0a93e32d614bbafb8035689e72629a5b40c41977d8'}
current={n.name:hashlib.sha256(ast.dump(n,include_attributes=False).encode()).hexdigest() for n in ast.parse((base/'scripts/neutronos-privileged-helper-guard.py').read_text()).body if isinstance(n,ast.FunctionDef)}
names=list(expected_baseline)
checks['authoritative_ssh_controller_bodies_preserved']=all(expected_baseline[n]==current[n] for n in names)
evidence['preserved_functions']=names
for rel in files:
 evidence.setdefault('sha256',{})[rel]=hashlib.sha256((base/rel).read_bytes()).hexdigest()
result=subprocess.run([sys.executable,str(base/'scripts/neutronos-privileged-helper-guard.py'),'--self-test'],capture_output=True,text=True)
checks['privileged_security_policy_selftest']=result.returncode==0 and json.loads(result.stdout)['ok']
for rel in ['scripts/neutronos-browser-launch','scripts/neutronos-browser-runtime']:
 result=subprocess.run(['/bin/bash','-n',str(base/rel)],capture_output=True,text=True);checks['shell_syntax:'+rel]=result.returncode==0
checks['no_VT_switch_or_openvt_runtime']=not any(re.search(r'[\'\"](?:/usr/bin/)?(?:chvt|openvt)[\'\"]', (base/rel).read_text()) for rel in files[:2])
checks['wayland_browser_runtime']='QT_QPA_PLATFORM=wayland' in (base/'scripts/neutronos-browser-runtime').read_text() and 'QT_QPA_EGLFS_' not in (base/'scripts/neutronos-browser-runtime').read_text()
checks['system_root_preserved']= 'NEUTRON_ROOT = Path("/opt/neutronos")' in (base/'scripts/neutronos-privileged-helper-guard.py').read_text()
checks['trusted_root_registry_retained']='ROOT_REGISTRY = Path("/var/lib/neutronos/app-store/root-installed.json")' in (base/'scripts/neutronos-privileged-helper-guard.py').read_text()
report={'scope':'Gemini canonical human storage and supervised application runtime port','passed':all(checks.values()),'checks':checks,'evidence':evidence,'unverified':['Combined amd64 C++ build and rootfs deployment by coordinator','Physical login/controller/Wayland fullscreen behavior'],'authorization':'Preserves authenticated selected-human semantics in NeutronShell. Supervisors require service-owned requests and NSS canonical human HOME on mounted DATA, verified running NeutronShell service UID/executable/cgroup; no new logind/PAM login requirement introduced.','provenance':'Minimal inspected canonical-storage deltas adapted from apollo-1.0.1-working only; authoritative source/archive+installed image remains primary baseline. No experimental QML or Setup flow imported.'}
p=base.parent/'validation/userdata-port.json';p.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'passed':report['passed'],'checks':len(checks),'failures':[k for k,v in checks.items() if not v]},indent=2))
if not report['passed']:sys.exit(1)
