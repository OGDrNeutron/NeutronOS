# NeutronOS boot system

## Source of truth

The only production artwork source is
`/opt/neutronos/design-reference/Boot.zip`. Its required SHA-256 is:

`53185c65cd9792a91acba1bc22ffacf2cd42f43aeb5a6b2773bf9ef30350264f`

Both `NeutronBootRenderer` and `NeutronShell` validate this hash and read the
PNG frames directly from the archive. There is no generated 4K copy and no
second production artwork tree.

## Display ownership and geometry

`neutronos-boot-renderer.service` starts during sysinit. It probes `/dev/fb0`
with `FBIOGET_VSCREENINFO` and `FBIOGET_FSCREENINFO` on every redraw, so it
uses the actual framebuffer dimensions, stride, channel layout, and bit depth.
The approved 1920x1080 frame is aspect-fitted with Qt smooth transformation
onto a black native-size canvas and centered. A 3840x2160 output therefore
uses an exact 2x scale and fills the output; a non-16:9 early mode is
letterboxed rather than distorted or cropped. A geometry change causes an
immediate redraw at the new native dimensions.

The renderer does not become DRM master. It writes the DRM framebuffer and
leaves the most recent scanout in place while NeutronShell starts EGLFS on the
real KMS display device. NeutronShell uses the same `BootVisualSource`
compositor and requested window dimensions to paint an identical fullscreen
cover. Only after that cover has completed a frame swap does NeutronShell
publish `/run/neutronos/boot/display-taken`; the framebuffer writer then stops.

LoginScreen is loaded synchronously behind the cover. Readiness requires the
correct Login or Setup surface to be loaded, visible, enabled, focused, and no
input lock to remain. Covered frame swaps advance the final milestones. After
the 100% cover has itself been swapped, the cover is removed. The following
frame swap proves the uncovered Login frame exists before
`/run/neutronos/login-ready` and `shell-frame-ready` are published.

## Progress authority

`/run/neutronos/boot/progress` is an atomic, group-writable, locked integer.
Only multiples of five from 0 through 100 are valid, and a transition lower
than or equal to the current value cannot move it backward. Events and
`CLOCK_BOOTTIME` timestamps are recorded in `events.tsv`.

The production milestones are:

| Percent | Evidence |
| ---: | --- |
| 0 | Approved archive hash and structure validated |
| 5 | A frame was written using the probed framebuffer geometry |
| 10 | Root filesystem remount completed |
| 15 | systemd device discovery completed |
| 20 | NeutronOS runtime/state setup completed |
| 25 | Firewall life-support guard active |
| 30 | Security core active |
| 35 | Security watchdog active |
| 40 | Controller transport active |
| 45 | Remote Systems state initialized |
| 50 | Remote Systems service active |
| 55 | User sessions enabled |
| 60 | NeutronShell start job active |
| 65 | Qt and EGLFS initialized |
| 70 | Shell managers constructed |
| 75 | Matching EGLFS cover frame swapped |
| 80 | Login/Setup surface created |
| 85 | Destination enabled, focused, and input-ready |
| 90 | First covered destination frame swapped |
| 95 | Handoff frame sequence confirmed |
| 100 | Ready Login and 100% cover have rendered |

There is no 99% state, fixed-duration completion timer, or sleep-based final
readiness test. On a fast boot, already-satisfied system milestones advance
quickly. On a slower boot, progress waits on the corresponding system state.

## Failure and recovery behavior

The renderer is deliberately a non-required, non-restarting service. A bad
archive, missing framebuffer, or renderer crash does not stop the OS,
networking, SSH, Tailscale, security services, or NeutronShell. tty1 remains
reserved and masked during a normal boot, while the serial console token is
preserved for physical recovery. Authenticated NeutronOS console
handoff/return services remain separate and are not part of the renderer.

Before the first reboot, keep these temporary recovery copies on the boot
partition:

- `cmdline.txt.neutronos-pre-boot-rebuild`
- `initramfs8.neutronos-pre-boot-rebuild`

If the OS boots but graphics fail, reconnect over SSH or Tailscale, inspect
`journalctl -b -u neutronos-boot-renderer.service -u neutronos.service`, and
disable only the renderer with
`sudo systemctl disable neutronos-boot-renderer.service`. NeutronShell remains
independent of renderer success.

If the kernel command line prevents normal remote boot, use the preserved
serial console or mount the FAT boot partition on another system, verify the
backup contains the original `root=PARTUUID=...`, and replace `cmdline.txt`
with `cmdline.txt.neutronos-pre-boot-rebuild`. The initramfs backup is replaced
only if the new initramfs itself fails to load root; do not change the root
PARTUUID. After a proven successful reboot, the two temporary boot-partition
copies may be removed.

## Command-line contract

`scripts/neutronos-stage-cmdline` stages but never installs a replacement. It
requires and preserves the serial console, exact root PARTUUID, rootfstype,
filesystem repair, rootwait, Wi-Fi regulatory domain, and USB-storage quirk.
The only intended live token changes are:

- remove `console=tty1`, `plymouth.ignore-serial-consoles`, and
  `ignore_loglevel`;
- replace `systemd.show_status=1` with `systemd.show_status=false`;
- replace `loglevel=7` with `loglevel=3`;
- add `quiet` and `vt.global_cursor_default=0`.

`splash`, `systemd.unit=multi-user.target`, the serial console, and all
storage, hardware, and networking tokens are preserved. `config.txt` does not
need a live change for this rebuild.
