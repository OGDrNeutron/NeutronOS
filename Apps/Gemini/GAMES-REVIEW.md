# Games — Gemini 0.1.0-review.1

This is a testing/review candidate published for physical acceptance. It is not
a stable Gemini OS release or a claim of verified game compatibility.

## Package and trust

Application ID: `gemini-games`. Version: `0.1.0-review.1`. The signed manifest
authenticates `platforms: ["gemini"]` and `architectures: ["amd64"]`.
Minimum catalog OS version: `0.5.4`.

* [Signed NAPP](Gemini-Games-0.1.0-review.1.napp)
* [Reviewed source archive](Gemini-Games-0.1.0-review.1-source.zip)
* [Release notes](changelogs/gemini-games-0.1.0-review.1.md)
* [Validation snapshot](validation/gemini-games-0.1.0-review.1/VALIDATION.md)
* [Runtime/capability matrix](validation/gemini-games-0.1.0-review.1/COMPATIBILITY.md)

The NAPP is unchanged from the reviewed artifact. SHA-256:
`8f2e3157886f42615f94da74cfc1713933e9331fe4bb9ff6188676c771d00a04`.
Size: 79,393 bytes. All 22 signed file hashes verify with the existing NeutronOS
release identity `F1A1E10BD2DB35060D6E61187CEB773D5ABD64B0`. The catalog and its
adjacent signature use that same identity. No private key or replacement trust
key is distributed. Developer Mode does not bypass verification.

The storefront [icon](icons/gemini-games.png) and
[poster](posters/gemini-games.png) are the supplied approved originals, unchanged.
The signed NAPP retains its reviewed bundled fallback graphic; its contents
were not regenerated to change artwork.

## Exact OS integration blocker

**Stock Gemini 0.5.4 does not contain the required Games OS hooks.** The inspected
release source and isolated installed guest match the before-hashes in
[patch preconditions](integration/gemini-games-0.1.0-review.1-preconditions.json).
The package's signed C++ backend checks for the session integration and refuses
game launch when it is absent. Library/artwork browsing can still be tested.

The [separate integration patch](integration/gemini-games-0.1.0-review.1.patch)
changes only Gemini `qml/Main.qml` and `src/ControllerManager.cpp`. It adds
authenticated session/modal/switching/account hooks and excludes the owned
virtual pads from duplicate system registration. It is published for OS
maintainer review; it is **not applied or installed by this NAPP**.

Current NAPP `buildFiles` permit only package-owned backend source. They cannot
patch those shared OS files. The catalog dependency text is informational; it
does not automatically install or enforce this OS integration. Do not interpret
an enabled Install button as proof that gameplay is supported on stock 0.5.4.
Gameplay/PS-Home/fullscreen restoration testing is blocked until reviewed OS
integration is deployed through an appropriate OS maintenance path. This
publication does not modify or rebuild the preserved Gemini release image.

## Dependencies and installation status

Signed Debian dependencies: `python3` and `bubblewrap`. These and the normal
`cmake`, `g++`, Qt base/declarative development packages were found installed in
the isolated 0.5.4 guest. A physical machine's dependency state can differ.
The existing privileged broker checks missing packages and requires the normal
App Store/Security approval. Optional Wine/emulator/streaming runtimes require
separate explicit setup; no emulator or game is bundled or silently installed.

This NAPP declares `rebuildRequired: true`: normal installation invokes Gemini's
existing managed shell-backend build/restart flow. That is separate from
rebuilding or replacing an OS image. Keep power connected and wait for the
store's final result. Signature and privileged-verifier checks pass; an actual
Games installation/update/removal transaction has not yet been demonstrated.
No authorization guard was bypassed to manufacture installation evidence.

## Controller-first App Store steps

1. Boot Gemini 0.5.4, sign in, and open **App Store** from the normal launcher
   using the D-pad/stick and **X/Cross**. Opening App Store refreshes its trusted
   repositories. The official repository must be enabled and network available.
2. Select **Discover** with Left/Right. Press Down to enter the package list;
   use Up/Down to select **Games — Gemini**, version `0.1.0-review.1`.
3. Press Right or X to focus its details. Read the review warning, dependencies,
   permissions and disk estimate; L1/R1 scroll the details. **Circle** cancels.
4. Press X on **Install** to open confirmation. Press X again only after
   reviewing it. Complete any normal Security/authentication prompt. Do not use
   manual/unsigned installation or disable signature checks.
5. Wait for download, verification, dependency checks and managed backend
   rebuild. A failed operation is a test failure to report, not a reason to
   bypass Security. After success, open Games from the normal launcher.
6. On stock 0.5.4 test library/artwork/controller UI first. Gameplay is blocked
   by the separate OS integration above. Add `/NeutronMedia/Games/` only if that
   existing library is mounted and accessible on the physical machine. Removing
   a library root does not delete its game files.

If Games does not appear, close and reopen App Store to refresh. **Start** opens
Repositories, where the existing official repository can be checked. Keep its
configured `Apps/Gemini/index.json` URL; do not add a competing catalog.

Custom artwork resolves through the validated account API to
`/NeutronOS/<username>/apps/gemini-games/artwork/`. Original games/artwork are
outside package ownership. The manifest declares empty `uninstallState`;
actual update/removal data-preservation testing is still pending.

## Pending physical acceptance

* Sony controller passthrough, analog controls, reconnection and multiplayer.
* Actual game launch/exit, PS/Home continuous three-second modal, fullscreen
  focus, Resume, game-session preservation and restoration.
* Actual App Store install/update/removal and user-data preservation.
* Steam/Proton lifecycle, emulator configuration, GPU performance and whole-OS
  resource consumption. Some adapters/provisioning are incomplete; see the
  compatibility matrix rather than assuming runtime support.

Existing evidence covers 67 QML checks, 13 backend Qt cases including test
setup/cleanup, a real-API account-isolation regression, 25 synthetic evdev/SDL2
checks and 19 package rejection cases. Synthetic controller evidence is not a
physical Sony or game-title test. The supplied game archives were not extracted
or launched. Historical validation documents record the earlier local-review
state; this page describes the authorized publication and its limitations.
