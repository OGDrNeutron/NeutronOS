# In-game controller implementation and required validation

The package-owned root service accepts only the existing `neutronos` display
account over its Unix peer-credential checked socket. It does not execute
commands, install packages, or expose arbitrary file access. Its systemd unit
restricts normal-system writable storage to its own `/run` directory; `/dev`
allows aliases to its own verified virtual nodes. It allows input-device
reading and uinput creation. Only CAP_CHOWN is retained; DeviceAllow keeps
physical input read-only. Its own kernel-created virtual nodes are hard-linked
under `/dev/neutronos-gemini-input`, avoiding `/run` nodev mounts without mknod
permission or mount-policy changes. Package installation uses the current signed
App Store privileged boundary; no unsigned mode or alternate trust root exists.

At launch the service identifies actual gamepad evdev capabilities, creates a
uinput gamepad using the physical USB/vendor/product identity and original
analog ranges, then grabs the physical evdev stream. The game sees the virtual
event/joystick nodes in its private `/dev/input`; original nodes are excluded to
avoid duplicated controls. Face buttons, D-pad, shoulders, stick clicks, sticks
and analog triggers are forwarded as gamepad events, never keyboard keys.
Mappings must use distinct supported controls. Stick inversion preserves ranges.

Home retains its physical button-capability position so runtime mapping indices
do not shift; its value stays released and its events are intercepted. A monotonic timer tracks each physical
controller independently and fires once after a continuous three-second hold.
Releases, disconnection, repeat events, and transport changes cannot combine
short holds. Both short and long Home input are reserved for Gemini in this
candidate; the game receives no Home button event. All other capabilities pass
through while the game owns input.

Menu/background transitions emit neutral values and releases. Held controls
remain blocked until released or returned to the device's dead zone. Kernel
queue overflow discards stale events until SYN_REPORT, then resamples buttons
and axes. Newly grabbed controllers are also sampled before forwarding begins.
The existing ControllerManager release API clears Gemini's own input edges.
System registration ignores only the package's own named virtual pads, leaving
physical-controller registration intact.

Profiles persist with each game: button code map, stick-axis inversion, optional
SDL mapping and identity-to-player assignments. Multiple pads have separate
virtual devices and slots (up to 16). Device unique IDs plus vendor/product
retain identity across transports when the physical driver exposes the same ID.
Devices without a unique ID use a name/vendor/product fallback; identical pads
or different USB/Bluetooth identifiers may need reassignment. Runtime ordering
and multiplayer discovery still require actual-game tests.

The shared shell owns the system modal independently of Games QML lifetime.
Authenticated shell, Security combo, keyboard and search ownership take
precedence. Loss of session access neutralizes game input and routes controls
back to the shell. Resume restores virtual-gamepad forwarding without a device
reconnect. The game process owns a private sandbox and cannot reach the input
service's control socket through its filesystem.

## Limits

SDL2 mapping and transition behavior pass in a real runtime session with
synthetic source devices. Wine/emulator and actual-game mapping remain unverified.
No automatic emulator-specific mapping files are generated yet. Steam Input
and Proton delegated sessions are blocked rather than advertised as supported.
Rumble/force-feedback forwarding, gyro, touchpad and adaptive triggers are not
implemented. Intermediate analog trigger values pass through to SDL2 in the synthetic
source test; physical controller trigger behavior remains unverified. The disposable VM now also runs actual Linux evdev/uinput and SDL2 tests with
synthetic source devices; physical USB/Bluetooth and actual-game multiplayer
remain unverified.

## Mandatory hardware run

On a disposable reviewed Gemini system, test at least one real native game, one
Windows/Wine game and each advertised emulator. Record controller model,
transport, kernel/SDL/runtime version and game version. Exercise both sticks,
D-pad, every button and stick click, and intermediate analog trigger values.
Repeat with USB, Bluetooth, transport changes and two controllers. Verify no
duplicate devices, stuck controls or accidental menu selections. Test Home
holds below three seconds and at/above three seconds, Resume without reconnect,
graceful Close, timeout/force Close, app switching and session lock/unlock.
Verify Weston really puts the modal above fullscreen games and restores focus.
Until these pass, mandatory in-game controller acceptance remains blocked.

The optional EVIOCGUNIQ ioctl may be absent on valid USB devices. Only absence
errors fall back to name/vendor/product; unrelated I/O errors remain fatal.
SDL Linux mapping behavior is inspected against its [official implementation](https://github.com/libsdl-org/SDL/blob/release-2.32.4/src/joystick/linux/SDL_sysjoystick.c);
actual evdev/uinput-to-SDL integration evidence is recorded separately from
physical-controller/game-title acceptance.

The game namespace disables SDL HIDAPI ownership and uses filesystem hotplug
for its proxy input directory. udev can change a newly created virtual inode
group; the service reconciles only verified owned aliases during its normal
scan. Retaining Home capability while intercepting every Home event preserves
SDL database button indices, including both stick clicks.

The actual SDL integration harness passes 25 checks: two controllers, both
sticks, intermediate triggers, D-pad, all mapped buttons, Home hold, transition
neutralization, Resume, disconnection and reconnection with stable transport
identity. Its source controllers are synthetic; this is not physical Bluetooth
validation, a game-title compatibility claim, or a fullscreen modal/focus test.

Queue overflow cancels an uncertain Home hold immediately, neutralizes the
virtual controller, and clears Gemini stick/button edges via inputReset. The
next SYN_REPORT resamples state; a lost release cannot fabricate a long hold.

## Controller-accessible per-game editor

The profile panel now shows named Cross/A, Circle/B, Square/X, Triangle/Y,
shoulder, Select/Share, Start/Options and stick-click buttons. Left/Right or X
changes an action by swapping the other assignment, preventing duplicate
buttons. Left/right vertical stick inversion is a toggle. Save persists the
profile; Circle cancels; Restore Defaults resets buttons and sticks without
changing retained advanced SDL/identity assignments. All rows scroll into view.
PS/Home cannot be selected, and analog trigger axes remain untouched.

Fresh GPU UI checks exercise the actual panel, button swap, inversion, Save,
Cancel, defaults and focus return. Settings status reads the existing
ControllerManager's registered controller/name/input source; it no longer
confuses zero active game-session pads with missing interface hardware.
These remain action-dispatch checks, not physical-controller acceptance.
