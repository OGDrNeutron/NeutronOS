#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-/home/echo/NeutronOS}"

CONFIG_DIR="/etc/neutronos"
SYSTEMD_DIR="/etc/systemd/system"

echo "Installing NeutronOS services from: ${PROJECT_ROOT}"

if [[ ! -d "${PROJECT_ROOT}" ]]; then
    echo "ERROR: PROJECT_ROOT does not exist: ${PROJECT_ROOT}" >&2
    exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/services/remote/neutronos_remote_controller.py" ]]; then
    echo "ERROR: Missing remote controller backend:"
    echo "  ${PROJECT_ROOT}/services/remote/neutronos_remote_controller.py"
    exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/services/remote/Static/controller.html" ]]; then
    echo "ERROR: Missing remote controller UI:"
    echo "  ${PROJECT_ROOT}/services/remote/Static/controller.html"
    exit 1
fi

if [[ ! -f "${PROJECT_ROOT}/scripts/neutron-securityd.py" ||
      ! -f "${PROJECT_ROOT}/scripts/neutronos_ipc/protocol.py" ||
      ! -f "${PROJECT_ROOT}/config/security-authorization.json" ||
      ! -f "${PROJECT_ROOT}/systemd/neutron-securityd.service" ]]; then
    echo "ERROR: Missing canonical Patch 70 Security IPC sources." >&2
    exit 1
fi

if [[ ! -x "${PROJECT_ROOT}/build/NeutronBootRenderer" ||
      ! -f "${PROJECT_ROOT}/design-reference/Boot.zip" ||
      ! -f "${PROJECT_ROOT}/systemd/neutronos-boot-renderer.service" ]]; then
    echo "ERROR: Missing validated framebuffer boot renderer payload." >&2
    exit 1
fi

# Install the Security daemon and its shared IPC package as one versioned
# deployment unit. This installer is never invoked by release sanitization.
install -d -o root -g root -m 0755 /usr/local/lib/neutronos/neutronos_ipc
install -o root -g root -m 0755 \
    "${PROJECT_ROOT}/scripts/neutron-securityd.py" \
    /usr/local/lib/neutronos/neutron-securityd.py
install -o root -g root -m 0644 \
    "${PROJECT_ROOT}/scripts/neutronos_app_security.py" \
    /usr/local/lib/neutronos/neutronos_app_security.py
install -o root -g root -m 0644 \
    "${PROJECT_ROOT}/scripts/neutronos_remote_security.py" \
    /usr/local/lib/neutronos/neutronos_remote_security.py
install -o root -g root -m 0755 \
    "${PROJECT_ROOT}/scripts/neutronos-remote-pairing" \
    /usr/local/sbin/neutronos-remote-pairing
install -o root -g root -m 0755 \
    "${PROJECT_ROOT}/services/remote/neutronos_remote_controller.py" \
    /usr/local/lib/neutronos/neutronos-remote-controller.py
install -d -o echo -g echo -m 0700 /var/lib/neutronos/remote
install -d -o echo -g echo -m 0700 /run/neutronos/controller
install -o root -g root -m 0755 \
    "${PROJECT_ROOT}/scripts/neutronos-securityctl.py" \
    /usr/local/sbin/neutronos-securityctl
for ipc_source in "${PROJECT_ROOT}"/scripts/neutronos_ipc/*.py; do
    install -o root -g root -m 0644 "$ipc_source" \
        "/usr/local/lib/neutronos/neutronos_ipc/$(basename "$ipc_source")"
done
install -o root -g root -m 0644 \
    "${PROJECT_ROOT}/systemd/neutron-securityd.service" \
    "${SYSTEMD_DIR}/neutron-securityd.service"
install -o root -g root -m 0644 \
    "${PROJECT_ROOT}/config/security-authorization.json" \
    "${CONFIG_DIR}/security-authorization.json"

mkdir -p "${CONFIG_DIR}"
cat > "${CONFIG_DIR}/neutronos.conf" <<CONF
NEUTRONOS_ROOT=${PROJECT_ROOT}
NEUTRONOS_STATE_DIR=/var/lib/neutronos
NEUTRONOS_SECURITY_STATE_DIR=/var/lib/neutronos/security

NEUTRONOS_REMOTE_HOST=0.0.0.0
NEUTRONOS_REMOTE_PORT=8091
NEUTRONOS_REMOTE_STATIC_DIR=${PROJECT_ROOT}/services/remote/Static
NEUTRONOS_WEB_CONTROLLER_EVENT_FILE=/tmp/neutronos_controller.json
CONF
chmod 644 "${CONFIG_DIR}/neutronos.conf"

install -o root -g root -m 0755 \
    "${PROJECT_ROOT}/scripts/neutronos-state-setup" \
    /usr/local/sbin/neutronos-state-setup
install -o root -g root -m 0644 \
    "${PROJECT_ROOT}/systemd/neutronos-state-setup.service" \
    "${SYSTEMD_DIR}/neutronos-state-setup.service"
install -o root -g root -m 0644 \
    "${PROJECT_ROOT}/systemd/neutronos.service" \
    "${SYSTEMD_DIR}/neutronos.service"
install -o root -g root -m 0644 \
    "${PROJECT_ROOT}/systemd/neutronos-boot-renderer.service" \
    "${SYSTEMD_DIR}/neutronos-boot-renderer.service"
install -o root -g root -m 0755 \
    "${PROJECT_ROOT}/release/neutronos-privileged-helper" \
    /usr/local/sbin/neutronos-privileged-helper
install -d -o root -g root -m 0755 /etc/sudoers.d
install -o root -g root -m 0440 \
    "${PROJECT_ROOT}/release/neutronos-privileged-helper.sudoers" \
    /etc/sudoers.d/neutronos-privileged-helper
visudo -cf /etc/sudoers.d/neutronos-privileged-helper

install -o root -g root -m 0644 \
    "${PROJECT_ROOT}/systemd/neutronos-remote-controller.service" \
    "${SYSTEMD_DIR}/neutronos-remote-controller.service"

install -o root -g root -m 0644 \
    "${PROJECT_ROOT}/systemd/neutronos.target" \
    "${SYSTEMD_DIR}/neutronos.target"

chmod +x "${PROJECT_ROOT}/services/remote/neutronos_remote_controller.py" || true

/usr/local/sbin/neutronos-state-setup

# Remove old remote service names.
systemctl stop neutronos-controller.service neutronos-web-controller.service 2>/dev/null || true
systemctl disable neutronos-controller.service neutronos-web-controller.service 2>/dev/null || true
rm -f /etc/systemd/system/neutronos-controller.service
rm -f /etc/systemd/system/neutronos-web-controller.service
rm -f /lib/systemd/system/neutronos-controller.service
rm -f /lib/systemd/system/neutronos-web-controller.service

systemctl daemon-reload

systemctl enable neutronos-state-setup.service
systemctl enable neutronos-boot-renderer.service
systemctl enable neutronos-remote-controller.service
systemctl enable neutronos.service
systemctl enable neutronos.target

echo
echo "NeutronOS services installed."
echo "Start:"
echo "  sudo systemctl start neutronos.target"
echo
echo "Logs:"
echo "  journalctl -u neutronos.service -f"
echo "  journalctl -u neutronos-remote-controller.service -f"
echo
echo "Remote controller:"
echo "  http://<pi-ip>:8091/"
