# Codex optional App Store test package

The NeutronOS Codex frontend is **not** a base-image app. Its complete
NeutronOS-specific payload is the single archive below; the only external
application dependency is the official Codex CLI/runtime and its official
authentication/session state.

## Canonical artifact

- File: `dist/apps/Codex-1.0.0-alpha.1-arm64.napp`
- App version: `1.0.0-alpha.1`
- Architecture: `aarch64`
- Size: `14862` bytes
- SHA-256: `e2a7f773499c20eb40cd5d8099c1a30af9ab2efdb60a6328304307ff8a389e81`
- Detached signature: `dist/apps/Codex-1.0.0-alpha.1-arm64.napp.sig`
- Publication catalog: `dist/apps/codex-repository-index.json`
- Key ID: `neutronos-codex-test-v1` (restricted to package ID `codex`)

The package owns its QML, metadata, icon/poster, JSON bridge schema, and the
executable JSONL bridge at `scripts/apps/codex/codex-bridge.py`. It does not
load Codex-specific files from `appstore/test-packages/` after installation.
It uses only generic base-system components and `packageAppBridgeManager`.

## Publish to GitHub

1. Create release tag `codex-app-v1.0.0-alpha.1` in
   `OGDrNeutron/NeutronOS`.
2. Upload the canonical `.napp` byte-for-byte as a release asset. The detached
   `.sig` is useful for human/offline verification, while the App Store uses
   the same base64 signature embedded in the catalog entry.
3. Publish/merge the package object from `codex-repository-index.json` into the
   repository index served to NeutronOS clients. Preserve the filename, URL,
   digest, signature, size, and key ID exactly.
4. Ensure clients contain the public test key from
   `config/app-store/defaults/trusted-keys.json` before refreshing the catalog.

## Uninstall after physical test 1

Use the App Store UI, or the same transaction helper:

```sh
python3 /opt/neutronos/scripts/neutronos-appstore-package.py uninstall \
  --root /opt/neutronos --package-id codex
```

This removes only managed Codex frontend payload and
`state/apps/codex`. It intentionally preserves the external Codex executable,
`~/.codex` credentials, sessions/history, repositories, workspaces, and user
files.

## Release-image hygiene

Exclude installed optional payload (`qml/apps/codex`,
`scripts/apps/codex`, its icon/poster/config, registry entry and app state)
from the base image. Retain the generic package bridge, trust metadata, App
Store package format, and catalog support. Sanitize `~/.codex`, API keys,
ChatGPT auth state, Codex session databases/history, shell history, personal
repositories, App Store downloads/staging/rollback data, caches and logs from
the release image. Do not delete those items from this development machine as
part of packaging.

No source backups, design references, historical patch archives, user media,
or unknown files were removed by this hygiene pass.
