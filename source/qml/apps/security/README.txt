NeutronOS Security App

Three-column controller-first Security frontend backed by SecurityCoreManager and SecurityManager.

Current UI contract:
- Narrow Security Settings rail with backend-backed advanced settings.
- Larger typography across navigation, content, and Security State rails.
- Triangle opens Security Settings search except where an active modal/editor owns the input; DEFCON keeps its response-engine action.
- Header and footer use identical horizontal bounds.
- Footer wordmark is Neutron (white) + OS (red), center branding is Secure | Intelligent | Unstoppable, and controller battery appears beside the clock.

Backend surfaces include threat protection, events, hardening, listening ports/firewall, bans, peripherals,
password vault, recovery, malware/quarantine, integrity, trusted devices, DEFCON, and audit state.

Feature/resilience pass 2026-08-16:
- Security mutations preserve last-known-good state on transient failures and receive realistic IPC timeouts.
- DEFCON readiness text follows the live level and active-threat count.
- Password Vault unlock uses controller combo only for normal access; no local account password prompt.
- Full scans are single-job, low-priority, memory-guarded, streamed, and expose the current file.
- Scan elapsed time updates locally at 250 ms while backend scan telemetry refreshes every second.
- Rich listening-port ownership/purpose details, rejected/blocked activity, persistent event flags, SSH/Tailscale controls, fixed peripheral identity, app permission browsing, audit history, and Recovery navigation remain intact.
