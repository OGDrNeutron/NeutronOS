# Gemini Games 0.1.0-review.4

Requires NeutronOS Gemini **0.5.6 candidate R2** and its `appstore-dependency-lifecycle:1` capability. R1 rejects this package safely. Physical hardware acceptance remains pending.

- Controller-first EXE/MSI and ISO9660/Joliet/Rock Ridge installation wizard with isolated per-game prefixes, read-only unprivileged FUSE disc mounts and multi-disc mappings. UDF-only and unsupported disc formats report an error.
- Import existing Windows or DOS executables and ScummVM data folders. Select launch executables, working directories, arguments, installed runtime versions and approved compatibility overrides.
- Wine, Proton, DOSBox and ScummVM adapters; graphics settings require actual Vulkan evidence and already supplied DXVK/VKD3D components. Compatibility varies by title, architecture and graphics hardware.
- Missing runtimes use the existing signed App Store approval workflow. Installing Games or importing a game never silently installs optional gaming runtimes.
- Installer progress, logs, cancellation, EXE reinstall and conservative tracked-file uninstall. Saves, changed files, unknown files, imported data and prefixes remain intact.
- Manual local patch review, explicit confirmation, original-file backup and verified rollback. No automatic patch/crack downloads or Security bypass.
- Private unprivileged FUSE prefix views preserve Gemini human-file ownership while satisfying Wine's prefix owner check. Mandatory filesystem helpers are separate from optional gaming runtimes.
- Wine installer controller assistance and the integrated NeutronOS keyboard. Submitted installer text is retained; Circle still restores canceled text. Proton installer interaction requires per-title validation.
- Preserves the approved footer, branding, Options focus behavior, official Games artwork and shared desktop carousel.

The package contains its compiled native module, app-owned installer helper and Windows input host. It contains no optional gaming runtimes, OS rebuild instructions, proprietary OS source or private signing keys.

MSI repair is deferred as an optional future enhancement; working MSI installation remains supported.
