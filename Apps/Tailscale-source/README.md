# Tailscale for NeutronOS, 1.0.0-alpha.1

Controller-first Tailscale installer, configuration, and live connection dashboard for NeutronOS on Debian 13 Trixie aarch64. Uses the user-supplied icon and poster.

## Package status

The signed NAPP and complete source are available as downloadable artifacts in the development conversation. This Git branch is an **incomplete source staging area**: no binary or signature has been uploaded here, and the App Store catalog on main has intentionally NOT been changed. Do not merge or publish an App Store entry before the exact signed NAPP bytes, signature and SHA-256 are present in `Apps/`.

The verified local NAPP is `Tailscale-1.0.0-alpha.1.Napp`, SHA-256 `98dc785688b8f8d073d4497aea045dab45c20803d4f5fb8b6c5c8b9f4cb50a80`, verified against existing official `neutronos-release-v1` public key. This commit does not imply dev-drive runtime validation or store availability.

## Planned user flow and implemented local package

A large centered user icon and INSTALL/CONFIGURE entry; actual package installation stdout/stderr and circular progress; Tailnet preferences (DNS, subnet routes, Shields Up, hostname), official Tailscale browser sign-in, service start; an animated center host planet, a green/red larger Tailscale satellite, potential smaller app/service planets and disconnected warning triangle. The packaged UI uses runtime shims pointing at the OS-provided actual ReferenceAppHeader, ReferenceAppFooter and VirtualKeyboard so it does not try to import an absent `app-store/payload/qml/components` directory.

The existing source `AppManager` already reserves `tailscale` as a legacy built-in command tile. The new package has ID `tailscale-manager` to avoid shadowing. Both tiles may coexist until an OS-side migration, which is outside this app change.

First-time installation checks existing APT candidates, and if needed fetches the official Debian 13 Trixie Tailscale source and key over HTTPS and validates the expected source entry, then streams `apt-get update`, `apt-get install tailscale` and `systemctl enable --now tailscaled`. Local admin consent is requested when required; the password is passed to sudo on stdin and is not recorded in argv or logs. Tailnet login uses the official Tailscale login URL, never a NeutronOS-collected Tailscale password or auth key.

## Future Remote Systems contract

A live status poll reports `installed`, `configured`, `connected`, `remoteReady`, Tailnet address and DNS identity and writes a 15-second-expiry `remote-readiness.json` under the package state. Positive readiness requires an active daemon, authenticated node identity and Running state. The emitted record explicitly has `authoritativeForAccessControl:false`. Future Remote Systems must independently verify live Tailnet identity and access policy before accepting off-LAN requests; this package intentionally does NOT change Remote Systems, routing, firewall or existing local Wi-Fi/Ethernet remote accessibility. Shields Up must remain off for inbound Tailnet services.

## Validation and publishing

Offline local tests: three unit/integration tests passed, deterministic zip verified, trusted Ed25519 signature verified, and exact signed package transactionally installed and uninstalled in isolated state roots. QML rendering, real APT installation, authentication and remote traffic remain untested on Pi hardware. The complete source ZIP and signed NAPP have been provided for direct dev-drive testing; this repository branch only stages documentation and manifest while binary publishing is unavailable in the current GitHub connector.