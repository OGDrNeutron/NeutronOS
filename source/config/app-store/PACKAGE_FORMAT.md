# NeutronOS `.napp` package format — schema 1

Gemini 0.5.4 uses the NeutronOS OpenPGP release identity
`F1A1E10BD2DB35060D6E61187CEB773D5ABD64B0` for catalogs and NAPP manifests.
The sole installed trust root is `/etc/neutronos/keys/neutronos-release.gpg`.
The private key stays external on the trusted publishing system. Debian Secure
Boot is independent and unchanged.

A `.napp` file is a ZIP archive containing `manifest.json`, its detached
`manifest.json.sig`, and the declared application files. The exact manifest
bytes are signed. `fileHashes` names every remaining archive file and its
SHA-256. Signed `platforms` and `architectures` are mandatory. Gemini accepts
only an explicit `gemini` platform and `amd64`/`x86_64` architecture; missing or
unknown compatibility fails closed. The manifest ID/version must match the
application's `app.json`.

The catalog `index.json` is authenticated by adjacent `index.json.sig` before
any entry can supply an Install or Update action. Its NAPP SHA-256 binds the
complete package, and package identity/version/platform/architecture are
checked against the authenticated catalog. After download, the shared NAPP
verifier authenticates the internal manifest, checks every file hash and
archive structure, and only then permits transactional installation. The
installer repeats verification on a temporary byte snapshot; the privileged
Security guard creates a root-owned immutable snapshot, and the root broker
repeats verification before any privileged operation.

Unsigned Developer Mode installation is unavailable on Gemini. Public keys
embedded in packages are never imported or trusted. Legacy packages signed by
the unavailable dedicated App Store Ed25519 key are incompatible with Gemini
0.5.4. Existing Apollo code/catalog/package paths remain untouched.

There is no automatic release-key rotation. A future key change requires an
explicit authenticated trust-root migration; arbitrary catalog/package keys
are rejected. The new Gemini publication path is `Apps/Gemini/index.json` in
the existing repository, alongside the preserved Apollo `Apps/index.json`.
See `repository/Gemini/PUBLISHING.md` for the external signing procedure.

## Base archive layout

```text
manifest.json
manifest.json.sig
payload/qml/apps/<package-id>/Main.qml
payload/qml/apps/<package-id>/app.json
payload/themes/Default/apps/icons/<package-id>.png       # optional
payload/themes/Default/apps/posters/<package-id>.png     # optional
payload/config/apps/<package-id>.json                    # optional
payload/scripts/apps/<package-id>/...                    # optional
```

Package payloads cannot write outside the allowed NeutronOS App Store overlay,
cannot contain symbolic links, and cannot execute package-provided install or
uninstall scripts.

The normal writable application overlay is:

```text
/var/lib/neutronos/app-store/payload/
```

`AppManager` discovers QML applications and assets from that overlay without
requiring them to be copied into the mutable NeutronOS source tree.

## Declarative Debian dependencies

A trusted repository package may declare Debian package dependencies in
`manifest.json`:

```json
{
  "debianDependencies": ["python3", "dnsmasq"]
}
```

The privileged package broker checks each dependency with `dpkg-query` first.
Only packages that are missing are passed to `apt-get install --no-install-recommends`.
Dependencies are shared system components and are never removed automatically
when an app is uninstalled.

Unsigned Developer Mode packages may not request Debian dependency installation.

## Declarative privileged system files

A trusted package may contain signed system members outside `payload/` only when
they are declared in `manifest.json` under `systemFiles`.

Supported archive prefixes:

```text
system/owned/...
system/shared/...
```

Supported destination roots are intentionally narrow:

```text
/etc/systemd/system/
/usr/local/lib/neutronos/
```

Example:

```json
{
  "systemFiles": [
    {
      "source": "system/owned/etc/systemd/system/example.service",
      "destination": "/etc/systemd/system/example.service",
      "ownership": "package",
      "mode": "0644",
      "enableNow": true
    },
    {
      "source": "system/shared/usr/local/lib/neutronos/example-bridge.py",
      "destination": "/usr/local/lib/neutronos/example-bridge.py",
      "ownership": "shared",
      "mode": "0755",
      "enableNow": false
    }
  ]
}
```

`ownership: "package"` means the file is registered to that App Store package
and is removed by transactional uninstall. `ownership: "shared"` means the
file is a dependency. It is installed only when absent, is verified by content
hash when already present, and is never removed by uninstall. A different
existing shared file causes installation to fail safely rather than silently
overwriting a component that another app or NeutronOS may own.

The root broker independently re-verifies the complete `.napp` SHA-256,
OpenPGP manifest signature, signed file hashes and platform compatibility
against the root-owned shared release trust root before any privileged
dependency or system-file operation. This is required even though
`AppStoreManager` already verifies repository packages in the shell process.

Unsigned Developer Mode packages may not contain privileged system files.

## Uninstall state

`uninstallState` is optional and may only name state below:

```text
state/apps/<package-id>/
```

If omitted or empty, user application state is preserved when the package is
removed.

## Repository metadata

An authenticated catalog entry supplies `packageUrl`, `sha256`, `id`, `version`,
`platforms`, `architectures`, permissions, storage size, screenshots and other
storefront metadata. The adjacent catalog signature covers all entries. The
internal NAPP manifest signature covers its own metadata and complete file hash
map. Neither a catalog nor a package can supply a replacement trust key.

## Declarative managed runtime requirements

Trusted repository packages may request one narrowly-scoped managed runtime under
`runtimeRequirements`. Runtime provisioning is performed by the root App Store
broker only after it independently verifies the complete signed `.napp`.
Package-provided lifecycle scripts are still never executed.

Schema 1 currently supports the `jellyfin-server` requirement only for the
`jellyfin` package id. The accepted declaration is intentionally fixed:

```json
{
  "runtimeRequirements": [
    {
      "type": "jellyfin-server",
      "systemUnit": "jellyfin.service",
      "containerName": "jellyfin",
      "dockerPackages": ["docker.io", "docker-cli"],
      "dockerUnit": "docker.service",
      "image": "jellyfin/jellyfin:10.11.11",
      "imageDigest": "sha256:aefb67e6a7ff1debdd154a78a7bbb780fd0c873d8639210a7f6a2016ad2b35db",
      "networkMode": "host",
      "restartPolicy": "unless-stopped",
      "configVolume": "neutron-jellyfin-config",
      "cacheVolume": "neutron-jellyfin-cache",
      "mediaRoots": ["/media", "/mnt", "/srv"],
      "autoDeviceDri": true
    }
  ]
}
```

Install behavior is deterministic and preservation-first:

1. If an installed `jellyfin.service` exists, NeutronOS starts and uses it. If
   that installed service cannot become responsive, installation fails instead
   of creating a competing server.
2. Otherwise, if an existing Docker container named `jellyfin` exists,
   NeutronOS starts and reuses it without taking ownership of it.
3. Otherwise NeutronOS checks for Docker. Only when Docker is absent does it
   install the missing Debian `docker.io` and `docker-cli` packages, then enables the Docker daemon.
4. The official Jellyfin 10.11.11 multi-platform image is pulled by immutable
   digest only if that exact image is not already present.
5. NeutronOS creates the `jellyfin` container with host networking, persistent
   config/cache Docker volumes, read-only `/media`, `/mnt`, and `/srv` bind
   mounts when those host paths exist, and `/dev/dri` when available.
6. Installation is not reported successful until `System/Info/Public` answers
   on `http://127.0.0.1:8096`.

Docker and downloaded images are shared dependencies and are not removed when an
app is uninstalled. A Jellyfin container created by NeutronOS is package-managed
and is removed on uninstall, but the persistent config/cache volumes are kept so
server state survives a later reinstall. An existing native Jellyfin service or
pre-existing Docker container is never removed by NeutronOS App Store uninstall.

## Security-owned infrastructure boundary

Optional application packages may not replace or claim NeutronOS Security
infrastructure. Schema-1 validation rejects `systemFiles` that target Security,
firewall life-support, nftables compatibility, or the OS-owned Remote Systems
security-isolation drop-in. Package-owned systemd units are also rejected when
they claim the shared `/run/neutronos` runtime directory, write into Security
runtime/state, request `CAP_NET_ADMIN`, or directly invoke firewall-management
programs such as nftables/iptables/firewalld.

These checks are enforced twice: once by the unprivileged package inspector and
again by the root App Store broker after exact-byte signature verification.
Security/firewall updates must use the NeutronOS OS-update path rather than an
optional `.Napp` package.

### Security-reserved privileged boundary

The installed `/usr/local/sbin/neutronos-privileged-helper` is a stable OS-owned
Security guard. The version-specific implementation is installed as
`/usr/local/libexec/neutronos-privileged-helper.real` and is not rewritten by
Security hardening updates. The guard stages the exact package bytes root-owned,
checks the expected SHA-256, denies Security/firewall-reserved system authority,
and only then delegates to the real helper for OpenPGP release verification and the
normal transactional install/uninstall flow.


## Package-helper confinement

`backend.type = "package-helper"` does not grant ordinary user-session authority. NeutronShell launches package helpers through the OS-owned bubblewrap sandbox. The sandbox starts with no network namespace sharing, no Linux capabilities, a cleared/allowlisted environment, a private `/tmp`, read-only package payload, and a writable app-private state directory. Network, Documents, removable storage, and Remote Systems broker sockets are exposed only when the signed package declares the corresponding permission and Core Capabilities has not explicitly denied it. Process/file-descriptor/file-size limits are applied before exec. If the sandbox runtime is unavailable, helper startup fails closed.

## Gemini 0.5.5 application-native boundary

Gemini rejects `rebuildRequired: true` and nonempty `buildFiles`. NAPP transactions never build or replace NeutronOS, NeutronShell or an OS-owned backend. Compile application-owned native code externally and include it under the application's isolated payload. Declare every `.so` in signed `nativeLibraries`; it must be a hashed ELF64 shared object matching the declared target architecture.

Signed `osRequirements` accepts `minimumVersion` (three numeric components), `capabilities` (API-name → positive integer version), and optional exact `qtVersion`. App metadata must agree with the signed package requirements. Missing OS capabilities block installation until an authenticated OS release provides them. Requirements cannot authorize an OS source rebuild.

Example: `"osRequirements":{"minimumVersion":"0.5.5","capabilities":{"package-session":1,"controller-proxy":1,"gemini-geometry":1},"qtVersion":"6.8.2"}`. Gemini publishes authoritative capability metadata at `/etc/neutronos/app-capabilities.json`, root-owned and not group/other writable. Platform/architecture, permissions, native libraries and all payload hashes remain covered by the NeutronOS release signature. No package-supplied key is trusted.
