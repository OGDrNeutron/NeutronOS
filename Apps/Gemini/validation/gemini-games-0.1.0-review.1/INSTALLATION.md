# Installation, update and removal validation

The review NAPP uses Gemini's current schema-1 internal signed manifest,
NeutronOS release key, authenticated platform/architecture metadata and
per-file hashes. The existing production archive inspector accepts its
package-owned build/system destinations. Developer Mode enforcement was not
changed. The original Gemini catalog and trusted keys were not changed.

The disposable COW VM runs the existing installed verifier and real privileged
helper verification functions. All 34 retained positive/negative trust-boundary
checks pass. The current Games NAPP passes eight package-specific checks through
the installed CLI and privileged verifier on a root-owned 0700 staging
directory and a 0600 single-link temporary snapshot. Its SHA-256 must match the
fresh offline report before review finalization. No private key enters the VM.

These are verification tests, not installation tests. Actual installation,
update, App Store update detection and removal remain untested. The privileged
rebuild path requires its established authorized NeutronShell caller and broker
context; this work has not bypassed those checks to manufacture install evidence.

The separate Gemini OS session patch must be reviewed and integrated with the
OS before gameplay can be enabled. Current NAPP buildFiles cannot distribute
Main.qml or ControllerManager changes. A package installed on unchanged 0.5.4
can browse/index games but intentionally refuses launch without these hooks.

Application-owned runtime state and library metadata are distinct from original
game and artwork files. The manifest declares no uninstallState deletion.
Runtime launch binds original library roots read only, and the application
never owns their files. Original artwork files are also read only; caches and
assignments remain personal data under the validated human account. Real
install/update/remove tests with sentinel user files, as well as a reboot test,
remain required before publication.
