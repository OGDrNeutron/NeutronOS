# NeutronOS Manager · iPhone Web App

**Status:** Finished UI prototype + reference backend, **not live on Gemini**.
Do not confuse the screenshot-inspired demo data with readings from your computer.

## Test the interface now

1. Open `neutronos-manager-preview.html` from the package in a browser. This is a standalone HTML preview with all five tabs and sample metrics. All destructive operations are **disabled**.
2. Alternatively, run `python3 -m http.server 8769 --directory web` from this folder and open `http://localhost:8769/?demo=1` on your computer.
3. To test on your iPhone over Tailscale **before** full deployment, temporarily serve **only the `web` folder in demo mode** via an existing properly secured HTTPS/Tailscale route. Do not expose the preview using an unrestricted public web server.
4. The actual installed iOS app requires the live HTTPS hostname, a TLS certificate with the correct SAN, Tailscale-only access and a valid client certificate. Use Safari → Share → Add to Home Screen → Open as Web App.

## The five tabs

- **Home:** Four utilization cards (CPU/RAM/User Data/NeutronMedia), quick access to AI/Lab/Files/Terminal, real service-state list.
- **System:** OS, kernel, CPU, GPU, network, storage, uptime, service actions. Three power buttons show confirmation and remain disabled unless explicitly enabled on Gemini.
- **Apps:** Three-wide installed application tiles; deep links use private, configured routes only.
- **Tools:** Shared workspace for files, terminal, Docker, media and AI tools.
- **Settings:** Appearance, automatic refresh interval, client security information, per-app entry points.

File management is implemented over HTTPS. Native SFTP remains available via Gemini's SSH/Tailscale, but a full browser SFTP protocol implementation is **not** included. NeutronAI and TorrentLab are linked launchers, not yet embedded into a single shared backend.

## Live server setup overview (perform on Gemini)

1. Install the folder at `/opt/neutronos-manager` and create a dedicated unprivileged Linux account `neutron-manager` with access only to selected paths.
2. Create a venv and `pip install -r server/requirements.txt` as appropriate for Debian 13.
3. Adapt `deploy/neutronos-manager.service.example`, including the verified venv path and the live hostname. Bind Uvicorn to `127.0.0.1:8877` only.
4. **Integrate** the block from `deploy/neutronos-manager.nginx.example` into Gemini's EXISTING Nginx process. There is already a Nginx listener for NeutronAI on Tailscale IP port 443. Do not override it or start a second Nginx service.
5. Reuse TorrentLab's trusted client CA **public certificate** and the enrolled iPhone client identity. Do not copy its client private keys, root CA private key or TLS server private key into this repository.
6. The new server's HTTPS certificate must cover `neutronos.neutronprojects.com` in its SAN. The old TorrentLab server cert is reusable **only if** it covers the new domain.
7. Configure tailnet-only DNS for `neutronos.neutronprojects.com` pointing at the current Gemini Tailscale IP. Do **not** publish this app to Cloudflare Workers/Pages or the public Internet; a public site can leak information even if its backend is private.
8. Configure only existing, private HTTPS tool URLs in `/etc/neutronos-manager/environment` and review any `sudoers` entries. No unrestricted sudo, no web-exposed Docker socket.
9. Check Nginx's `ssl_verify_client on` on the new host, the `X-Neutron-Client-Verified` header on every route, allowed Tailscale IPs, and the absence of a public route. Test invalid/missing client certificates are blocked.
10. Test Home Screen mode and 30-minute idle expiry on the iPhone before enabling power actions.

## Limits / safety

- **Face ID:** An installed Home Screen web app may be lockable using iOS's *Require Face ID* feature. iOS can allow device-passcode fallback. A normal web page cannot guarantee Face ID-only server authentication without passkeys/native iOS support. No passkeys or app password UI are required in this prototype; actual server protection is Tailscale + mutual TLS.
- Power controls are OFF by default. `MANAGER_ENABLE_POWER=1` does not grant sudo automatically: review explicit access rules and the shell service name. Physical presence is still needed for power-on from shutdown unless Wake-on-LAN/firmware support is configured.
- Terminal runs as `neutron-manager`, **not** root. Fine-grained sudo allowlists are critical.
- Docker container and systemd unit names vary between deployments; verify exact local identities first.
- Sample data never appears on production pages unless you intentionally use preview mode (`?demo=1`). Production unavailable data is not silently replaced with fake values.

Project is a **deployable starter**, not a fully validated live remote administration installation. No changes have been made to the running Gemini server.
