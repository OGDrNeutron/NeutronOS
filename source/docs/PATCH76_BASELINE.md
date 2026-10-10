# Patch 76 pre-change baseline

Captured 2026-08-08 before Patch 76 source or runtime modifications.

## Accepted roadmap baseline

Patches 70, 74, and 80–84 are the accepted regression baseline. Patch 69 is
excluded. Patches 75 and 79 remain deferred. The only outstanding Patch 80–84
items are physical-display checks caused by disconnected HDMI, not known code
failures.

## Canonical and deployed hashes

| Artifact | SHA-256 |
|---|---|
| `scripts/neutron-securityd.py` | `18e5915a0d72d4511b99d8d3fa9ec57290ec6894d11cc2d33f290d21a362120f` |
| `scripts/neutron-security-watchdog.py` | `accb622bae867ffcc3dd0443117092c543328533942c2f8cd67c182a7fee6fdf` |
| `config/security-authorization.json` | `8ca0e5588f3ffbf37195051703084c9248b8f0c709f07ee6dd3a8900f33efe89` |
| `config/ipc-schema.json` | `d3cd61afdb388685b305e0b86a5fac1c8110b36e0e500944a15a9fef144882c4` |
| `systemd/neutron-securityd.service` | `42eada8755c435794e56b3a8673078100d3bf3629e662f215eb79d45f8d3595e` |
| `systemd/neutron-security-watchdog.service` | `9dfbab14d42c73745423ee70dde5a097e36f0b68a8c8bfb8abe99a23519a3199` |
| `src/SecurityManager.cpp` | `6ee09de6923abc110821f5cbd14b2b9387a2e5319c29d31ad710c1e187091184` |
| `src/SecurityManager.h` | `e2bc97b48614b160ed7b7e686ee9336c561227b1a92a5a0d9091fdd5586800d0` |
| `src/SecurityCoreManager.cpp` | `faf8ef783d04d545f5371ef88a6b478a8de40a9ea2500696a9de374399c62ed1` |
| `src/SecurityCoreManager.h` | `0fcf95c294b7ed05f0a14110df1bd1c32fd1a37a8e52e58bba00944615560e5b` |
| `src/SecureIpcClient.cpp` | `26fd76c5305e2c4d4b780da7d2feefc544ae3bdde0a70642cc1b6d8a42a0af09` |
| `src/SecureIpcClient.h` | `989da92e1b1c7b69fd4871901dfccde36df0e614a8a56f64ebd611e9fa064e97` |
| `qml/apps/security/Main.qml` | `43aa0c948e52b9944610ce771cbc5575ac394eea09260396e8a9c7f4e882bca2` |
| `qml/dashboard/v2/ModernDashboard.qml` | `98385e81cf4000e72c6c1417563da905b033b6645634e405da2efbb91edbaa4d` |
| `qml/modals/NotificationCenterOverlay.qml` | `5a149d2acb911e12c3463c5448b40cf38531c083b57e1716269c71c5065fd8b2` |
| `src/SystemMonitor.cpp` | `69f76560ad57816dd2113da65efe4cce00e63c9241288a34c8fe893423a15cbc` |
| `build/NeutronShell` | `38dd86c02273a50a9f4b2d26afac6abab1814cc792237cd0983ab23ff70a593b` |
| `build/NeutronBrowser` | `b90c93987bd4c7277bb6b187d3fe62b160cd1b1d7c48691c46c86aa182e66fc8` |

The live daemon, watchdog, policy, and unit hashes matched these canonical
hashes exactly.

## Live service state

| Unit | Active/substate | Unit-file state | Restarts |
|---|---|---|---:|
| `neutron-securityd.service` | active/running | enabled | 0 |
| `neutron-security-watchdog.service` | active/running | enabled | 0 |
| `neutronos.service` | active/running | disabled | 2055 historical |
| `NetworkManager.service` | active/running | enabled | 0 |
| `tailscaled.service` | active/running | enabled | 0 |
| `ssh.service` | active/running | enabled | 0 |
| `docker.service` | active/running | **disabled** | 0 |
| `neutronos-remote-controller.service` | active/running | enabled | 0 |
| `neutronos-offline-network.service` | active/running | enabled | 0 |
| `remote-media-optimizer.service` | active/running | enabled | not changed |
| `neutron-jellyfin-control.service` | active/running | enabled | not changed |
| `neutron-jellyfin-bridge.service` | active/running | enabled | not changed |

Docker contained `jellyfin`, reported healthy. Docker's disabled unit-file state
is an explicit preservation invariant.

## Security runtime layout

- Protocol: `neutronos.ipc`, version 1, schema version 1.
- Socket: `/run/neutronos/security/control.sock`, `root:neutronos-shell`, mode
  `0660`.
- Authorization policy: `/etc/neutronos/security-authorization.json`,
  `root:root`, mode `0644`.
- Authoritative daemon state: `/var/lib/neutronos/security-core`, `root:root`,
  mode `0750`.
- Duplicate in-process state: `/var/lib/neutronos/security/core`, `echo:echo`,
  mode `0700`.
- Duplicate audit stream: `/var/lib/neutronos/security/core/audit.jsonl`,
  `echo:echo`, mode `0600`.
- Login/session state: `/var/lib/neutronos/security`, `echo:echo`, mode `0700`.
- Legacy daemon JSON request/response directories were absent because
  `--legacy-json-requests` was not enabled.

The authoritative daemon and watchdog were stable. NetworkManager, Tailscale,
SSH, Docker/Jellyfin, Remote Controller, Offline Network, Media Optimizer,
Browser/AppHost, Dashboard v2, Running Apps, Notification Center, and telemetry
were treated as preserved regression surfaces. HDMI-A-1 and HDMI-A-2 were
disconnected; this is a physical-validation limitation, not a known defect.
