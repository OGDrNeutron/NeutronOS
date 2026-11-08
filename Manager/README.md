# NeutronOS Manager (Gemini private deployment)

Target: https://neutronos.neutronprojects.com. iPhone-first standalone web app.

## Status
This is source code on a feature branch. It is NOT deployed on Gemini, not exposed at the target URL, and not yet a complete administration suite.

Implemented: dashboard, system load/memory/storage, selected systemd service controls, file browser/upload/download, user-scoped terminal, Tools launchers, 30-minute idle session, CSRF, same-origin request checks.

## CRITICAL SECURITY REQUIREMENTS
1. Bind HTTPS only to Gemini's Tailscale IP, never 0.0.0.0 or a public tunnel; restrict source to tailnet 100.64.0.0/10. Use private split DNS to resolve the requested hostname to the Tailscale IP. Keep the public site and domain DNS routes separate.
2. Use a server TLS certificate valid for neutronos.neutronprojects.com. Reusing TorrentLab's SERVER certificate only works if its SAN covers that hostname.
3. Reuse the trusted client CA (and the installed iPhone client identity) from TorrentLab for mutual TLS, not the server's private key. Never put private keys, certificates containing private keys, or credentials in GitHub.
4. Gemini already runs NeutronAI Nginx on port 443 of its Tailscale IP. Add a new Nginx server block into that SAME existing Nginx process. Do not start a second listener, alter the existing host certificates, or overwrite the prior config. Example file is a TEMPLATE requiring actual host path verification.
5. Run the Python backend ONLY at 127.0.0.1:8877 as an unprivileged neutron-manager account. Do not allow untrusted upstream or direct client connections to it.
6. Systemctl actions require extremely restricted sudo permissions for exact permitted unit/action combinations, granted only after manual validation. NEVER give the server unrestricted sudo or access to the Docker socket.
7. Validate the iPhone client certificate works in the standalone Home Screen app. A certificate working in Safari does not automatically prove it will work inside every web-app storage context.
8. Protect privileged actions; terminal is a real unprivileged shell, not a demonstration. Keep backend isolated and reject unauthorized traffic before reaching it.

## Face ID
Apple provides Require Face ID for eligible iPhone app icons, but permits passcode fallback. Web apps have no direct, server-verifiable Face ID-only API without WebAuthn/passkeys. We do NOT add passkeys or a password UI. The security boundary is Tailscale + mTLS. Apple device-side Face ID lock may be enabled on the added Home Screen app if that option is available. A native companion is required for app-controlled biometric-only authentication.

## Deployment outline
- Install at /opt/neutronos-manager from this feature branch, using a venv with Manager/server/requirements.txt.
- Create dedicated non-root neutron-manager Unix account with access only to approved file areas. Change FILE_ROOTS according to desired access.
- Install backend systemd unit from deploy/neutronos-manager.service.template, using uvicorn, with loopback binding only.
- Generate PNG app icon from the owner-supplied artwork; install at Manager/web/apple-touch-icon.png (180x180) and make sure HTML/manifest references resolve.
- Add the private DNS record and Nginx mTLS vhost after identifying the correct live CA and TLS files.
- Start the manager, test from a Tailscale iPhone, ensure certificate rejection for unauthorized devices, and verify no public inbound route.
- Only then consider allowing narrowly scoped service actions and terminal access.

## Known limitations / future work
- The existing TorrentLab and NeutronAI applications are NOT absorbed yet; private launchers are in place, with link configuration by MANAGER_TOOL_* environment values.
- Docker, Jellyfin and qBittorrent native administration are not implemented yet.
- The Files tab is HTTPS-based; a true SFTP client is separately available through SSH/Tailscale.
- NeutronStream remains untouched.
