# Apollo 1.0.1 final repair candidate validation

## Automated offline results

- Release compilation completed with `--parallel 2`; all 5 CTest tests passed.
- QML audit passed all 190 files; Python syntax checks and `git diff --check` passed.
- The focused final-repair contract check passed 46 checks.
- The guarded privileged-helper self-test passed all 10 checks.
- Security profile persistence and readback were exercised in an isolated temporary state root; invalid simultaneous learning and enforcement was rejected.
- Storage progress and idempotence were exercised on a disposable 16,000,000,000-byte loop image. Real stages were emitted, the UUID remained unchanged on repeat, and one persistent mount entry remained.
- The unchanged storage algorithm also retains the earlier disposable-loop coverage for sufficient space, insufficient space, existing managed data, unexpected partition 3, unsupported layout, repeat, and interruption before formatting.
- Candidate root ext4 and boot FAT checks passed; the DOS partition table still has exactly the original 512 MiB boot partition and approximately 6.5 GiB system partition.
- All installed source-backed files and the compiled binary match the integration hashes.
- The image contains the exact five Mesa packages at `25.0.7-2+rpt4`; kernel, firmware, and libdrm are unchanged.
- First Boot state is clean: no SSH host keys, Wi-Fi profiles, setup completion, controller registration, storage transaction, user-data fstab entry, or partition 3.
- No GDB or basic-render diagnostic override is present.

The broad regression checker recorded 10 passes and 4 errors caused by stale expectations already present in the 1.0.1 baseline: an obsolete AppHost timeout marker, two absent legacy app QML paths, and an obsolete App Store copy marker. The final repair did not touch those paths.

## Physical validation pending

These seven repairs have not been tested on physical hardware. Physical testing must cover Wi-Fi success and failure feedback, responsive storage progress, one-time login acknowledgment across reboot, Setup controller pairing, the Wired label, Security profile application, and per-session unregistered-controller attention. The candidate is not declared release ready.
