# Tailscale for NeutronOS, 1.0.0-alpha.1

Controller-first Tailscale setup and live network visualization for NeutronOS on Debian 13 Trixie aarch64, using the supplied icon and poster.

## Current publication status

The **complete signed NAPP and full source ZIP are available from the development chat**, but this GitHub branch is an **incomplete source staging area**. It contains the initial manifest, build script and documentation, not the entire application source, image assets, NAPP binary or signature. No App Store catalog changes were made. The available GitHub connector can commit text but cannot upload the locally created binary file. Do not merge or publish an App Store listing until the exact binary and matching signature have been uploaded to `Apps/`.

Final locally verified NAPP: `Tailscale-1.0.0-alpha.1.Napp`.
SHA-256: `e9f8668d0f1ef28052c0509ee935bda9203b9f414975a69638c2a885aee14648`.
Signature validates against NeutronOS's existing official `neutronos-release-v1` Ed25519 trusted public key. This is not a claim of device runtime validation or GitHub binary publication.

## User flow

The locally built NAPP implements a first-open centered icon/INSTALL or CONFIGURE action; streamed apt and systemctl stdout/stderr with circular progress; Tailnet DNS/subnet routes/Shields Up/hostname settings; official Tailscale browser sign-in and daemon management; animated central host planet, large green/red Tailscale planet, potential service satellites and disconnected warning triangle. The package dynamically loads NeutronOS's actual shared header/footer/controller keyboard based on AssetManager.qmlPath so that its isolated QML payload does not try to import a nonexistent `app-store/payload/qml/components` tree.

The OS already reserves `tailscale` for a legacy built-in command tile. This app has ID `tailscale-manager` to avoid shadowing; both may coexist until future OS integration. When installation is required, the NAPP obtains the official Debian Trixie Tailscale source/key over HTTPS, validates the expected source, installs through APT with explicit local admin authorization, and streams terminal output. The administrator password is never put in argv or logs. Tailnet login uses Tailscale's own authentication link, never a NeutronOS-collected Tailscale password.

## Remote Systems integration boundary

A live poll writes `remote-readiness.json` with installed/configured/connected/remoteReady, IP, DNS and 15-second expiry. Remote-ready requires live active daemon, authenticated identity, Tailnet IP and Running state. The record has `authoritativeForAccessControl:false`: future Remote Systems must independently validate live Tailnet identity, permissions and reachable service for each off-LAN access. This package deliberately does not change Remote Systems or local Wi-Fi/Ethernet access. Shields Up must be off to accept inbound Tailnet traffic.

Offline tests passed: three tests, deterministic NAPP, verified trusted signature and signed isolated install/uninstall. Raspberry Pi Qt rendering, real APT installation, Tailnet authentication and remote access remain unverified pending dev-drive testing.