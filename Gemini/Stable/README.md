# Gemini Stable Images

Public distribution catalog for **solid-version** NeutronOS Gemini AMD64 installation and recovery images (for example 0.6.0, 0.7.0).

- Incremental versions (0.6.1, 0.6.2, etc.) are **updates only** and remain on private Mainline channels.
- Compressed full images are distributed as **public GitHub Release assets**, not committed into Git history.
- `images.json` is the machine-readable catalog for the website, Native Recovery and Full Image Restore.
- A catalog entry must not be marked available until the public release asset is uploaded, anonymously downloadable, hash-verified and its trusted release signature is verified.
- The installer must independently verify its trusted release signature and SHA-256 before any write. HTTPS and a catalog hash alone do not authenticate a release.
- Never use a public catalog entry to authorize an unattended or destructive install.

The Gemini 0.6.0 image is currently published in private Mainline. Its public copy and signed metadata must be published and verified before adding an available entry to `images.json`.
