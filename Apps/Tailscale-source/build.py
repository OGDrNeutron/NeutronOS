#!/usr/bin/env python3
"""Deterministic NeutronOS Tailscale NAPP builder and Ed25519 release signer.

Uses the existing official signing credential ONLY when provided explicitly.
Do not commit signing credentials or this file's output containing a secret.
"""
from __future__ import annotations

import argparse
import base64
import ctypes
import ctypes.util
import hashlib
import json
import stat
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
STAMP = (2026, 9, 19, 0, 0, 0)


def build(destination: Path, signing_key: Path | None = None) -> dict:
    manifest = json.loads((ROOT/'manifest.json').read_text(encoding='utf-8'))
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + '.tmp')
    try:
        with zipfile.ZipFile(temporary, 'w') as archive:
            for source in [ROOT/'manifest.json', *sorted((ROOT/'payload').rglob('*'))]:
                if not source.is_file() or '__pycache__' in source.parts or source.suffix == '.pyc':
                    continue
                relative = source.relative_to(ROOT).as_posix()
                info = zipfile.ZipInfo(relative, STAMP)
                info.create_system = 3
                mode = 0o755 if relative.startswith('payload/scripts/apps/') else 0o644
                info.external_attr = (stat.S_IFREG | mode) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, source.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    package = destination.read_bytes()
    metadata = {
        'id': manifest['id'], 'name': manifest['name'], 'version': manifest['version'],
        'developer': manifest['developer'], 'description': manifest['description'],
        'category': manifest['category'], 'architectures': manifest['architectures'],
        'minNeutronOS': manifest['minNeutronOS'],
        'packageUrl': 'https://raw.githubusercontent.com/OGDrNeutron/NeutronOS/main/Apps/'+destination.name,
        'sha256': hashlib.sha256(package).hexdigest(),
        'size': len(package),
        'installedBytes': sum(p.stat().st_size for p in (ROOT/'payload').rglob('*') if p.is_file()),
        'permissions': manifest['permissions'], 'dependencies': manifest['dependencies'],
        'debianDependencies': manifest['debianDependencies'],
        'requiresDeveloperMode': False,
        'icon': 'icons/tailscale-manager.png', 'poster': 'posters/tailscale-manager.png',
    }
    if signing_key:
        text = signing_key.read_text().strip()
        prefix = 'NEUTRONOS-ED25519-SECRET:'
        if not text.startswith(prefix):
            raise ValueError('Unsupported private-key format')
        private = base64.b64decode(text[len(prefix):], validate=True)
        if len(private) != 64:
            raise ValueError('Invalid Ed25519 private-key length')
        sodium = ctypes.CDLL(ctypes.util.find_library('sodium'))
        sodium.sodium_init()
        detached = (ctypes.c_ubyte * 64)()
        signed_len = ctypes.c_ulonglong()
        result = sodium.crypto_sign_detached(detached, ctypes.byref(signed_len),
                                             (ctypes.c_ubyte*len(package)).from_buffer_copy(package),
                                             len(package), (ctypes.c_ubyte*64).from_buffer_copy(private))
        if result or signed_len.value != 64:
            raise RuntimeError('Signing failed')
        signature = base64.b64encode(bytes(detached)).decode()
        metadata['signature'] = signature
        metadata['keyId'] = 'neutronos-release-v1'
        destination.with_suffix(destination.suffix+'.sig').write_text(signature+'\n', encoding='utf-8')
    metadata_path = destination.with_suffix('.catalog-entry.json')
    metadata_path.write_text(json.dumps(metadata, indent=2)+'\n', encoding='utf-8')
    return metadata


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT/'Tailscale-1.0.0-alpha.1.Napp')
    parser.add_argument('--signing-key', type=Path, help='Path to EXISTING official NeutronOS Ed25519 secret key')
    args = parser.parse_args()
    print(json.dumps(build(args.output, args.signing_key), indent=2))
