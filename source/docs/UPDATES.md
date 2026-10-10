# Gemini release verification

Production Update and Recovery share /etc/neutronos/keys/neutronos-release.gpg and /usr/local/libexec/neutronos-release-verify. Expected OpenPGP fingerprint: F1A1E10BD2DB35060D6E61187CEB773D5ABD64B0; UID NeutronOS Release Signing <OGDrNeutron@proton.me>. Only public material is installed. The private signing key remains external to images and release archives.

Existing signed-metadata envelopes remain the transport, with base64-encoded detached OpenPGP signatures over exact decoded JSON metadata. Mainline metadata declares algorithm OpenPGP. Verify the signature and pinned signer before trusting payload name, byte size, SHA256, compatibility and scope. Recovery reauthenticates before application. Unsigned, changed, unknown-signer and hash-mismatched official artifacts fail closed. Root-owned locally generated configuration backups retain their existing guarded allowlist/hash workflow; they are not official signed OS images.

Mirror-supplied keys never replace installed trust. There is no automatic key rotation. Changing the pinned identity requires a separately authorized trusted image/admin procedure; an unsigned release cannot rotate trust. No supported full-disk clean-image reinstallation exists in the current backend.

OpenPGP release trust is separate from the preserved Debian shim/GRUB/kernel Secure Boot chain. Legacy raw Ed25519 OS keys are retired; App Store signatures are a separate existing trust domain.
