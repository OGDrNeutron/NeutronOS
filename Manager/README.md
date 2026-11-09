# NeutronOS Manager · Gemini production deployment

**Current deployment: system Python only. No venv, pip, apt, Docker permissions or package installation.**

Following the interrupted Debian installation (missing ensurepip), the existing certificate and partial install are **reused** by `deploy/deploy-gemini-reviewed.sh`. This script is a resumable installer for **the already-existing partial installation only**. It does not create a virtual environment, request the CA signing passphrase, issue a replacement certificate, or install Python packages.

The live native server is `server/native_manager.py`, based solely on the Python standard library. It runs on loopback port 8877, behind the existing TorrentLab HTTPS Nginx, with required mTLS and an Nginx-to-backend secret. The initial installation remains **read-only**; service start/stop, shutdown/reboot, uploads and terminal are intentionally unavailable until reviewed separately.

## Resume

Check out branch `feature/private-neutronos-manager` from `OGDrNeutron/NeutronOS` and run:

```bash
bash -n Manager/deploy/deploy-gemini-reviewed.sh &&
sudo bash Manager/deploy/deploy-gemini-reviewed.sh Manager
```

The installer checks the existing TorrentLab CA certificate and NeutronOS server certificate signed during the previous attempt, the previous Manager account and configuration, and the live HTTPS Nginx configuration. It preserves the existing services and aborts safely if prerequisites fail.

**Do not use `deploy/activate-gemini.sh` or the old `deploy/neutronos-manager.service.example` for the current installation.** Those were superseded by the native system-Python deployment path.

## NeutronOS Manager

The five-tab iPhone web interface is in `web/`. Installed web-app assets, system status and filesystem are served through the native Python backend. Actual Docker container states require a separately approved read-only access mechanism; no Docker permissions are granted by this deployment.

Current security is private Tailscale network plus HTTPS client certificates trusted by TorrentLab, not a separate app login. On iOS, Home Screen `Require Face ID` can allow a passcode fallback controlled by iOS.

Do not enable public DNS/Cloudflare forwarding for the manager. Install no packages or privileged rules without explicit authorization.
