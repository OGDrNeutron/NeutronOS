# Dependencies and installation impact

| Component | Why/source | Impact |
|---|---|---|
| Qt 6/QML, NeutronShell/AppManager/HumanAccountPolicy | Existing Gemini OS | Existing system; package-owned C++ buildFiles require guarded shell rebuild |
| Existing Gemini Recovery atom / Quick3D modules | Exact installed footer animation, geometry, shaders and textures | Existing OS components, unchanged; no static substitute |
| Python 3 | Real evdev/uinput controller service; Debian configured repositories | Shared system dependency, preserved on uninstall |
| bubblewrap | Private game input/device/filesystem and process namespace; Debian configured repositories | Shared system dependency; no arbitrary privileged game execution |
| Games input service | Signed package-owned Python and systemd unit | System-wide root service, restricted input API; transactional uninstall owns only these files |
| Reviewed Gemini Games OS hooks | Global modal, input edge release, app switching | Separate OS review patch; not deliverable through current NAPP buildFiles |
| Wine/emulators/Moonlight/libretro cores | Per-game runtime candidates | Optional, never silently installed; license, firmware, hardware and title caveats apply |

Missing supported runtimes now open a controller-accessible review panel over
Gemini's existing AppStoreManager. It considers only compatible, authenticated,
install/update-eligible catalog entries whose name/description contains the
runtime name. This is a candidate hint, not a promise that the package provides
a working runtime; users review the full package details before approval. No
package ID or alternate trust system is invented. Unsupported execution adapters
do not offer installation.

The review displays the reason, repository/package source, declared Debian
dependencies, shared system impact, permissions, title/hardware caveats, and
the current installFootprint disk/download estimate. Unknown disk estimates
block installation. A second X explicitly approves the existing App Store
install/update API; Circle cancels. Changed package metadata or footprint
requires another review. Active games and busy App Store operations block this
flow. The existing signature, Security, immutable snapshot, privileged
reverification, dependency provisioning and transactional install remain intact.

Seven fresh UI checks exercise review, unverified-provider rejection, no
automatic installation, unknown estimates, cancellation/focus, explicit dispatch
and a stale catalog. The store in these UI checks is a test boundary that records
requests; it does not install software. No compatible runtime provider package
is currently present in the preserved empty Gemini catalog. Real runtime
provisioning remains unverified until a reviewed compatible NAPP is available.
The retained apt cache has no package metadata, so no disk-size values or Debian
package availability are invented from it.

Game state resides at `<validated-human-home>/apps/gemini-games/`; discovery's
default root is `<validated-human-home>/Games/`. The default directory is
reported through HumanHome and is not created or filled with games implicitly.
Additional folders must already exist and cannot overlap existing roots.
Game roots are read-only to launched processes. Runtime writable configuration,
cache and save locations are separate per-game state directories. App Store
`uninstallState` is empty: removing the app does not request removal of game
files or personal configuration. Shared Debian packages are preserved.

Personal artwork uses `<validated-human-home>/apps/gemini-games/artwork/`;
thumbnail cache and saved assignments remain personal data across package
replacement. See `ARTWORK-AND-FOOTER.md` for matching and validation details.
