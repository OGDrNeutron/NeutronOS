#!/usr/bin/python3
"""Verify a Gemini NAPP against the OS-owned OpenPGP release trust root."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import runpy
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath

RELEASE_VERIFIER = Path('/usr/local/libexec/neutronos-release-verify')
TRUSTED_KEY = Path('/etc/neutronos/keys/neutronos-release.gpg')
PLATFORM_ARCH = {'gemini': 'amd64', 'apollo': 'aarch64'}
ID = re.compile(r'^[a-z0-9][a-z0-9._-]{0,95}$')

class Rejected(ValueError):
    pass

def canonical_arch(value: str) -> str:
    return {'x86_64': 'amd64', 'arm64': 'aarch64'}.get(value.strip().lower(), value.strip().lower())

def running_platform(os_release: Path = Path('/etc/os-release')) -> tuple[str, str]:
    data = {}
    try:
        for line in os_release.read_text().splitlines():
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                data[key] = value.strip().strip('"')
    except OSError:
        raise Rejected('NeutronOS platform identity is unavailable') from None
    platform = data.get('VARIANT_ID', '').lower()
    if data.get('ID') != 'neutronos' or platform not in PLATFORM_ARCH:
        raise Rejected('Unknown NeutronOS platform identity')
    machine = canonical_arch(__import__('platform').machine())
    if machine != PLATFORM_ARCH[platform]:
        raise Rejected('OS variant and CPU architecture disagree')
    return platform, machine

def validate_os_requirements(manifest: dict, *, version_path=Path('/etc/neutronos/version.json'), capability_path=Path('/etc/neutronos/app-capabilities.json'), require_owner=True) -> None:
    requirements = manifest.get('osRequirements', {})
    if not isinstance(requirements, dict) or set(requirements)-{'minimumVersion','capabilities','qtVersion'}:
        raise Rejected('Invalid signed OS requirements')
    if not requirements:
        return
    def trusted_json(path):
        try:
            info=path.lstat()
            if not stat.S_ISREG(info.st_mode) or (require_owner and (info.st_uid!=0 or info.st_mode & 0o022)):
                raise Rejected('OS capability metadata is not trusted')
            return json.loads(path.read_bytes())
        except (OSError, ValueError):
            raise Rejected('Required OS capability metadata is unavailable') from None
    def version(value):
        if not isinstance(value,str) or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',value):
            raise Rejected('Invalid OS requirement version')
        return tuple(map(int,value.split('.')))
    minimum=requirements.get('minimumVersion')
    if minimum and version(trusted_json(version_path).get('version')) < version(minimum):
        raise Rejected('Requires NeutronOS '+minimum+' or newer; install an authenticated OS update first')
    requested=requirements.get('capabilities',{})
    if not isinstance(requested,dict) or any(not isinstance(k,str) or not ID.fullmatch(k) or type(v)!=int or v<1 for k,v in requested.items()):
        raise Rejected('Invalid signed capability requirements')
    if requested or requirements.get('qtVersion'):
        available=trusted_json(capability_path)
        if available.get('schema')!=1 or not isinstance(available.get('capabilities'),dict):
            raise Rejected('OS capability metadata is invalid')
        for name,required in requested.items():
            actual=available['capabilities'].get(name,0)
            if type(actual)!=int or actual<required:
                raise Rejected('Missing OS capability: '+name+'; install an authenticated OS update first')
        qt=requirements.get('qtVersion')
        if qt is not None and (not isinstance(qt,str) or qt!=available.get('qtVersion')):
            raise Rejected('Packaged native backend requires a different Qt ABI')

def verify_napp(path: Path, *, expected_sha: str = '', expected_id: str = '',
                expected_version: str = '', platform: str | None = None,
                architecture: str | None = None, key_path: Path = TRUSTED_KEY,
                release_verifier: Path = RELEASE_VERIFIER, require_owner: bool = True,
                version_path: Path = Path('/etc/neutronos/version.json'), capability_path: Path = Path('/etc/neutronos/app-capabilities.json')) -> dict:
    platform, architecture = (platform, architecture) if platform and architecture else running_platform()
    if platform not in PLATFORM_ARCH or canonical_arch(architecture) != PLATFORM_ARCH[platform]:
        raise Rejected('Inconsistent platform and architecture')
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if expected_sha and digest != expected_sha.lower():
        raise Rejected('NAPP package hash differs from authenticated catalog')
    try:
        with zipfile.ZipFile(path) as archive:
            entries = archive.infolist()
            names = [entry.filename for entry in entries]
            if len(names) != len(set(names)) or 'manifest.json' not in names or 'manifest.json.sig' not in names:
                raise Rejected('NAPP has duplicate names or lacks its signed manifest')
            payload_names = []
            for entry in entries:
                name = entry.filename
                parts = PurePosixPath(name).parts
                if not name or name.startswith('/') or '\\' in name or '..' in parts or entry.is_dir():
                    raise Rejected('NAPP contains an unsafe archive member')
                if stat.S_IFMT(entry.external_attr >> 16) == stat.S_IFLNK:
                    raise Rejected('NAPP contains a symbolic link')
                if name not in ('manifest.json', 'manifest.json.sig'):
                    payload_names.append(name)
            if archive.getinfo('manifest.json').file_size > 1024 * 1024 or archive.getinfo('manifest.json.sig').file_size > 16384:
                raise Rejected('Signed NAPP metadata is oversized')
            metadata = archive.read('manifest.json')
            signature = archive.read('manifest.json.sig')
            verify = runpy.run_path(str(release_verifier), run_name='neutronos_napp_library')['verify']
            try:
                identity = verify(metadata, signature, key_path=key_path, require_owner=require_owner)
            except Exception as error:
                raise Rejected(f'NAPP release signature rejected: {error}') from None
            manifest = json.loads(metadata)
            if not isinstance(manifest, dict) or type(manifest.get('schema')) is not int or manifest.get('schema') != 1:
                raise Rejected('NAPP manifest schema is invalid')
            if manifest.get('rebuildRequired') or manifest.get('buildFiles'):
                raise Rejected('OS rebuild packages are unsupported; a precompiled NAPP is required')
            package_id = manifest.get('id')
            version = manifest.get('version')
            if not isinstance(package_id, str) or not ID.fullmatch(package_id) or not isinstance(version, str) or not version:
                raise Rejected('NAPP identity/version is invalid')
            if expected_id and package_id != expected_id:
                raise Rejected('NAPP ID differs from authenticated catalog')
            if expected_version and version != expected_version:
                raise Rejected('NAPP version differs from authenticated catalog')
            platforms = manifest.get('platforms')
            architectures = manifest.get('architectures')
            if (not isinstance(platforms, list) or not platforms or
                any(not isinstance(p, str) or p not in PLATFORM_ARCH for p in platforms) or len(set(platforms)) != len(platforms) or
                platform not in platforms):
                raise Rejected('NAPP is not signed for this NeutronOS platform')
            if (not isinstance(architectures, list) or not architectures or
                any(canonical_arch(a) not in PLATFORM_ARCH.values() for a in architectures if isinstance(a,str)) or
                any(not isinstance(a,str) for a in architectures) or
                len(set(architectures)) != len(architectures) or
                canonical_arch(architecture) not in [canonical_arch(a) for a in architectures]):
                raise Rejected('NAPP is not signed for this CPU architecture')
            validate_os_requirements(manifest, version_path=version_path, capability_path=capability_path, require_owner=require_owner)
            hashes = manifest.get('fileHashes')
            if not isinstance(hashes, dict) or set(hashes) != set(payload_names):
                raise Rejected('Signed NAPP file list differs from archive contents')
            for name in payload_names:
                expected = hashes[name]
                if not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected):
                    raise Rejected(f'Invalid signed file digest: {name}')
                if hashlib.sha256(archive.read(name)).hexdigest() != expected:
                    raise Rejected(f'NAPP payload hash mismatch: {name}')
            libraries=manifest.get('nativeLibraries',[])
            if not isinstance(libraries,list) or len(set(libraries))!=len(libraries):
                raise Rejected('Invalid native library declaration')
            for library in libraries:
                if not isinstance(library,str) or not library.startswith(f'qml/apps/{package_id}/native/') or not library.endswith('.so') or 'payload/'+library not in payload_names:
                    raise Rejected('Native library is outside this application package')
                binary=archive.read('payload/'+library)
                machine=62 if canonical_arch(architecture)=='amd64' else 183
                if len(binary)<64 or binary[:6]!=b'\x7fELF\x02\x01' or int.from_bytes(binary[16:18],'little')!=3 or int.from_bytes(binary[18:20],'little')!=machine:
                    raise Rejected('Native library is not a compatible compiled shared object')
            undeclared=[n[8:] for n in payload_names if n.startswith('payload/') and n.endswith('.so') and n[8:] not in libraries]
            if undeclared:
                raise Rejected('Undeclared application-native library')
            app_manifest_name = f'payload/qml/apps/{package_id}/app.json'
            main_name = f'payload/qml/apps/{package_id}/Main.qml'
            if app_manifest_name not in payload_names or main_name not in payload_names:
                raise Rejected('NAPP lacks its declared application entrypoint')
            app_manifest = json.loads(archive.read(app_manifest_name))
            if not isinstance(app_manifest, dict) or app_manifest.get('id') != package_id or app_manifest.get('version') != version:
                raise Rejected('Signed NAPP identity disagrees with application metadata')
            if app_manifest.get('osRequirements',{}) != manifest.get('osRequirements',{}):
                raise Rejected('Application and signed package OS requirements disagree')
            for name in payload_names:
                if not name.startswith(('payload/qml/apps/', 'payload/themes/Default/apps/icons/',
                    'payload/themes/Default/apps/posters/', 'payload/config/apps/',
                    'payload/scripts/apps/', 'system/owned/', 'system/shared/', 'build/owned/')):
                    raise Rejected('NAPP archive member is outside the package format')
            return {'success': True, 'id': package_id, 'version': version,
                    'platforms': platforms, 'architectures': architectures,
                    'sha256': digest, 'files': len(payload_names),
                    'signer': identity['fingerprint'], 'manifest': manifest}
    except (zipfile.BadZipFile, KeyError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise Rejected(f'Invalid signed NAPP archive: {type(error).__name__}') from None

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['verify'])
    parser.add_argument('package', type=Path)
    parser.add_argument('--expected-sha', default='')
    parser.add_argument('--expected-id', default='')
    parser.add_argument('--expected-version', default='')
    args = parser.parse_args()
    try:
        print(json.dumps(verify_napp(args.package, expected_sha=args.expected_sha,
            expected_id=args.expected_id, expected_version=args.expected_version),
            sort_keys=True, separators=(',', ':')))
        return 0
    except (Rejected, OSError) as error:
        print('NeutronOS NAPP verification failed: ' + str(error), file=sys.stderr)
        return 78
if __name__ == '__main__':
    raise SystemExit(main())
