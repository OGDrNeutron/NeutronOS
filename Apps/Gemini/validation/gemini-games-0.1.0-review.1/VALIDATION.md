# Gemini Games validation status

Status: **development review candidate; physical and installation acceptance pending**.
Tests use the final isolated Gemini code and retained Debian 13/Qt 6.8.2 libraries.
The complete `NeutronShell` target builds with `-j8`. This host has 16 logical
CPUs and about 9.5 GiB available RAM; concurrency was bounded to available
resources. The original 0.5.4 release candidate and preserved release image were not rebuilt or installed.

## Fresh evidence

* `validation/shell-build.log`: full isolated shell build succeeds.
* `validation/backend-tests-native.txt` and `.xml`: Qt backend tests pass,
  including representative platform fixtures, invalid executable rejection,
  removable-root disconnect/reconnect, favorite persistence, removing a root
  without deleting games, sampled duplicate candidates, targeted changed-file
  indexing, quiescence/rescan restoration, unsupported recommendations, and
  real child process TERM/timeout/KILL and SIGSTOP/CONT ownership. Unsupported
  runtime capabilities are rejected; this regression failed before correction.
  ZIP/7z and verified UDF-disc containers cannot launch directly, including after manual Wii selection;
  redistributable installers are excluded from discovery.
* `validation/controller-core.log`: ten software tests pass for continuous
  three-second timing, repeat/short/disconnected holds, independent controllers,
  transport identity, original analog ranges and neutralization/dead-zone gates.
  These tests exercise no physical controller or game.
* `validation/ui-results.json`, `ui.log`, `ui-page-*.png`: native QML rendering
  and controller-action dispatch checks. All eight pages, every Settings tab,
  footer behavior, exact Recovery atom animation/resource cleanup, custom
  artwork preview/selection/reset, transient installed carousel, dialogs/keyboard/focus and
  message acknowledgement are exercised. Seven additional checks validate the
  named-button controller editor, remapping, stick inversion, Save/Cancel,
  defaults and returned focus. Seven runtime-review checks exercise explicit
  approval, signed candidate filtering, unavailable footprints and catalog changes.
  These store-boundary tests record calls and install no software. Additional modal checks exercise the
  production QML view against a test session, not a running game.
* `validation/os-qml-parse.log`: conditional OS root QML parses with qmlformat.
* `validation/package-verification.json`: existing production NAPP verifier
  accepts the signed Gemini AMD64 review package and every declared file hash;
  nineteen negative cases are rejected. Existing archive inspector accepts
  declarative build/system ownership. Staged catalog signature verifies with the
  pinned release identity. Offline tests use a user-owned copy of the public
  trust key; installed root-ownership enforcement is unchanged.
* `validation/apollo-after.json`: all 257 recorded Apollo/App Store/package
  hashes match the before values. `apollo-reference-payload.json` lists Games
  QML members inside the unchanged reference NAPP.
* `validation/gemini-054-preservation.json`: 856 retained original source files
  match their baseline. `catalog-baseline/` and the original repository catalog
  remain unchanged. `changed-source-files.json` records isolated changes.

Earlier PRoot-based execution tests failed because PRoot stat/process translation
did not reflect native behavior. They remain recorded in the older test logs;
fresh native execution supersedes those results. An earlier UI run exposed
message focus conflicts in Settings; Square now opens Messages there and the
fresh UI run verifies acknowledgement. No prior failure is presented as a pass.

## Performance

Actual measurements in `ui-results.json` are five-second samples of the QML
test process with the isolated Radeon-backed Weston/OpenGL display: visible, hidden with scene
resources released, then restored. They are not a GPU gaming benchmark or a
measurement of the whole running Gemini OS. CPU is process CPU time divided by
wall time, expressed as a percentage of one CPU. RSS values for all three phases are recorded in `PERFORMANCE.md`. These short samples do not establish sustained RAM savings. GPU clocks/load, background OS
process impact, game frame rate and real gaming overhead remain unmeasured.
Library quiescence is independently checked with the real scanner.

## Installation/update/removal

Offline verification and archive inspection pass. The COW VM runs the retained
installed signature tests: all 34 CLI/root-verification/trust-owner checks pass
(`validation/games-vm/installed-boundary.json`). These are signature boundary
checks. The current signed Games package also passes eight checks through the
installed CLI and privileged verifier, including every signed file hash,
Gemini/AMD64 metadata, build ownership and empty uninstallState
(`validation/games-vm/installed-games-package.json`). Its package hash matches
the current offline report. These checks do not install the Games package. Actual privileged
install/update/removal have **not** run. Version comparison is tested, but live
App Store update detection and re-verification through the root-owned snapshot
and broker are unverified. No privileged helper was replaced or bypassed.
The manifest's empty uninstallState and package-owned destinations cannot name
game roots; a real removal test with sentinel game files is still mandatory.
The NAPP cannot install the separate Main.qml/ControllerManager OS patch under
the current schema. Installing it on unmodified 0.5.4 does not enable gameplay.

## Pending physical acceptance

The user has reserved the Sony controller for the physical development PC.
Controller passthrough, fullscreen gameplay, PS/Home long-press and game-session
restoration will be tested physically after boot. No controller/USB/host-display
attachment, detachment or reconfiguration was performed.
The host exposes a Radeon render node and a Sony joystick node.
An isolated Weston display validates native GPU rendering. A disposable COW
Gemini VM preserves its backing image and exposes uinput and the installed SDL2
runtime. Its TCG software-rendered Qt UI has not produced a frame. Native/Wine/emulator/streaming launches in actual games, real
analog triggers, sticks/buttons, USB/Bluetooth reconnection, multiplayer, Home
interception, modal-over-fullscreen behavior, Resume focus, runtime shutdown,
supported background switching and whole-system performance still require actual game/physical-controller sessions. Unsupported Steam/Proton lifecycle, automatic emulator
profile application, actual runtime provisioning, cloud/Android execution
and PC power/FPS/scaling controls are incomplete. Power choices are diagnostics
instead of unsupported hardware controls. No release-ready claim is made.

## Reproduction

Build using `tools/in-build-root cmake -S /games/tests -B /games/build-tests`,
then `tools/in-build-root cmake --build /games/build-tests -j8`.
Run `build-tests/games-tests` with LD_LIBRARY_PATH pointing to
`/NeutronMedia/NeutronOS-Gemini/revisions/0.5.4/staging/debian-base/usr/lib/x86_64-linux-gnu`.
Run `build-tests/games-ui /home/drneutron/GeminiGames-workspace` using the retained
Qt plugin/import paths and an isolated Weston OpenGL display. The private
compositor environment/provenance is recorded under `validation/private-weston/`.
QT_QUICK_BACKEND=software cannot validate the required Quick3D atom. Run `python3 tests/test_controller_proxy.py` and
`python3 tests/verify_review_package.py`. Signing is explicit and external via
`tools/sign-review-package.py`; it validates identity before signing and never
publishes. Reprepare/re-sign/reverify if package inputs change.

## Added artwork and footer evidence

See `ARTWORK-AND-FOOTER.md` for the resolved per-account directory, matching/cache
implementation, 67 GPU UI checks, and distinct animated atom frame captures.
The earlier offscreen renderer could not render Quick3D. The first GPU run
exposed animation-clock footer delay; a precise native system timer now passes
the countdown and persistent manual-footer checks. The artwork assertion was
corrected to inspect the selected game rather than scanner insertion order.
Original failed logs/results are superseded by the fresh GPU run, not counted
as passes. Reboot and installed-package artwork survival remain unverified.

`validation/games-vm/controller-sdl-runtime.json` records 25 passing actual
Linux evdev/uinput-to-SDL2 checks in a private bwrap game-side namespace.
Explicit synthetic fixtures bypass only production discovery, which continues
to reject virtual source nodes. The production Pad implementation, kernel
interfaces and installed SDL runtime are used. Physical hardware and game-title
acceptance remain outstanding. This run caught and fixed absent unique IDs,
nodev device aliases, shifted stick-click indices and udev ownership on reconnect.
Automatic review rejected broader mknod device policy; the accepted design
keeps DeviceAllow read-only, uses own virtual-inode hard links and removes
CAP_MKNOD. No trust, global mount policy or physical device ownership changed.

## Authorized real-library validation

`user-library-probe.json` records read-only production scanner discovery under
/NeutronMedia/Games/: three archives, each requiring extraction and with direct
launch denied. Repeat scanning is stable, and removing the additional root
preserves original files. `user-games-preservation.json` checks 699 original
files' size, modification/change timestamps and first/last 64 KiB samples, all
unchanged. This is sampled preservation evidence, not full-file authenticity.
`USER-LIBRARY.md` describes suitable candidates and the missing launch data.

The fresh synthetic SDL rerun exposed a harness readiness race: the old run's
final snapshot already said two controllers, so the test sampled it before the
new consumer initialized. `controller-sdl-stale-snapshot-failure.json` preserves
that failure. A per-run token now rejects prior/unmarked snapshots. Four focused
harness tests cover this race; the fresh VM run passes all 25 checks with a new
consumer token and an unchanged boot ID.
Physical acceptance remains separate.


## Account-switch isolation

`validation/account-tests.txt` and `.xml` record a passing account-switch
regression through the actual Gemini HumanHome API and backend in the existing
COW VM. Two valid passwd/home fixtures exist only inside a private bwrap mount
namespace. No real account was created or changed. Switching identity hides old
library roots, artwork, messages, preferences, UI state and logs before QML
refresh, rejects mutations, resets memory for a newly initialized account, and
restores the original account's saved artwork/preferences when returning.
These tests do not establish multi-account physical game-session behavior.
A PRoot fixture failed Qt home-directory resolution; native guest filesystem
execution supplies the accepted evidence without changing account policy.

## Synthetic test isolation incident

An earlier synthetic input run reached the unmodified guest Recovery interface
and selected its Recovery reboot action. The disposable COW guest rebooted;
its read-only backing release image and workspace were preserved. No host
controller, USB device or display was changed. The fresh harness suspends only
the disposable guest's original NeutronShell process for fixture-pad lifetime,
destroys its own synthetic pads, then resumes that same process. It does not
restart a service or the VM. Per-run consumer tokens also reject stale snapshots.
All 25 fresh checks pass; the boot ID remains unchanged and the original shell
resumes. Physical acceptance is still pending. The staged production controller
hook excludes Games virtual pads from duplicate system registration, but that
uninstalled hook has not been exercised in a complete game session.


The targeted added-folder probe initially could not identify the UDF disc
container (exit 6, no entry). The scanner now recognizes its complete volume
recognition descriptor sequence without guessing a game platform, and the
focused fixture rejects incomplete descriptors or attempts to choose Wii for
launch. The fresh backend suite passes 13 cases including Qt setup/cleanup;
the targeted production probe passes and records a blocked archive entry.
The preservation report separately lists seven additional files while confirming
all 699 files in the original snapshot remain unchanged.
