# Apollo 1.0.1 validation

Automated offline validation passed:

- Release build completed with two jobs; all 5 CTest tests passed.
- Python syntax, QML lint, and Git whitespace checks passed.
- Exact five Mesa 25.0.7 packages and all 97 recorded installed files matched.
- Boot and root filesystem checks and partition table verification passed.
- SSH enabled/disabled command paths and timezone validation were exercised with isolated mocks.
- Storage was exercised destructively only on disposable loop images: sufficient and insufficient capacity, managed and unmanaged partition 3, unsupported system layout, repeated provisioning, and an interruption before formatting.
- The image remains two partitions: 512 MiB boot and approximately 6.5 GiB system. First Boot storage state, partition 3, fstab entry, host keys, Wi-Fi profiles, and Setup completion state are absent.
- Installed source-backed files match the source/build hashes.

Physical hardware validation is pending. It must cover graphical boot, SSH,
timezone, Wi-Fi, controller registration, Settings, both onboarding stages,
Desktop startup persistence, and storage provisioning on each supported boot
medium. This offline result does not declare the release ready.

Compressed image validation also passed: XZ CRC64 verified and the full decompressed stream matched the validated 7,499,999,744-byte raw image at SHA-256 `31954b38eb777e9e4c66f2ff3f1857597efeda441c09c462874f266808b7c634`.
