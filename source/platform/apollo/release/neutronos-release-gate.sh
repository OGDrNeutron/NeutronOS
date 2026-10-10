#!/bin/bash
set -euo pipefail
ROOT=${1:?rootfs path required}
fail(){ echo "RELEASE GATE FAILED: $*" >&2; exit 1; }
require(){ [ -e "$ROOT$1" ] || fail "missing $1"; }
for f in /opt/neutronos/build/NeutronShell /opt/neutronos/build/NeutronBootRenderer /opt/neutronos/design-reference/Boot.zip /opt/neutronos/qml/Main.qml /opt/neutronos/qml/SetupWizard.qml /usr/local/sbin/neutronos-privileged-helper /usr/local/sbin/neutronos-recovery-console /etc/systemd/system/neutronos.service /etc/systemd/system/neutronos-boot-renderer.service /etc/systemd/system/neutronos-recovery.service; do require "$f"; done
boot_hash=$(sha256sum "$ROOT/opt/neutronos/design-reference/Boot.zip" | awk '{print $1}')
[ "$boot_hash" = 53185c65cd9792a91acba1bc22ffacf2cd42f43aeb5a6b2773bf9ef30350264f ] || fail "approved Boot.zip hash mismatch"
chroot "$ROOT" /opt/neutronos/build/NeutronBootRenderer --validate
chroot "$ROOT" python3 -m py_compile /usr/local/sbin/neutronos-privileged-helper /opt/neutronos/scripts/neutron-securityd.py /opt/neutronos/services/remote/neutronos_remote_controller.py
chroot "$ROOT" visudo -cf /etc/sudoers.d/neutronos-privileged-helper
chroot "$ROOT" sshd -t
chroot "$ROOT" nft -c -f /etc/nftables.conf
ldd_out=$(chroot "$ROOT" ldd /opt/neutronos/build/NeutronShell); echo "$ldd_out"; ! grep -q 'not found' <<<"$ldd_out" || fail "NeutronShell has unresolved libraries"
chroot "$ROOT" /usr/bin/python3 /opt/neutronos/scripts/neutronos-qml-audit.py /opt/neutronos/qml
systemd-analyze --root="$ROOT" verify neutronos.service neutronos-boot-renderer.service neutronos-recovery.service neutron-securityd.service neutron-security-watchdog.service neutronos.target
[ "$(systemctl --root="$ROOT" is-enabled neutronos.target)" = enabled ] || fail "neutronos.target not enabled"
[ "$(systemctl --root="$ROOT" is-enabled neutronos.service)" = enabled ] || fail "neutronos.service not enabled"
[ "$(systemctl --root="$ROOT" is-enabled ssh.service 2>/dev/null || true)" != enabled ] || fail "SSH must be disabled on first boot"
[ "$(systemctl --root="$ROOT" is-enabled neutronos-remote-controller.service 2>/dev/null || true)" != enabled ] || fail "Remote Controller must be disabled on first boot"
grep -q '^User=neutronos$' "$ROOT/etc/systemd/system/neutronos.service" || fail "NeutronShell is not unprivileged"
grep -q '^TTYReset=no$' "$ROOT/etc/systemd/system/neutronos.service" || fail "scanout-preserving handoff missing"
grep -q 'Wants=neutronos-boot-renderer.service' "$ROOT/etc/systemd/system/neutronos.service" || fail "boot renderer ordering missing"
[ ! -e "$ROOT/var/lib/neutronos/setup/setup.json" ] || fail "setup completion state was not reset"
[ ! -s "$ROOT/etc/machine-id" ] || fail "machine-id is not empty"
initrd=$(find "$ROOT/boot" -maxdepth 2 -type f -name 'initrd.img-*' | head -n1)
[ -n "$initrd" ] || fail "initramfs missing"
! lsinitramfs "$initrd" | grep -Eq 'plymouthd|neutronos-plymouth|neutronos_progress_' || fail "obsolete Plymouth payload embedded"
for package in plymouth libplymouth5 plymouth-label plymouth-themes; do
    [ "$(chroot "$ROOT" dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" != "install ok installed" ] || fail "obsolete package remains: $package"
done
echo "RELEASE GATE PASSED"
