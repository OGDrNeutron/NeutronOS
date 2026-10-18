# Gemini 0.6.0 image publication

**Public asset upload, anonymous byte verification and trusted signature verification passed.** This directory reserves metadata for the existing official 0.6.0 solid image; it does not contain an IMG.

Expected image filename: `NeutronOS-Gemini-0.6.0.img.xz`

Previously reported SHA-256 (must be independently checked against the actual bytes before publication):
`cf7021d91f654cddb21b3b546267282d5bf2473d041a072e1398335984acf77b`

Publish the unchanged IMG as a public GitHub Release asset, along with its actual trusted signature and checksum/manifest, then add its verified public asset URL, size, hash, signature metadata and release tag to `../images.json`. Do not invent a signature or mark it installable before these steps succeed.

Public release: https://github.com/OGDrNeutron/NeutronOS/releases/tag/gemini-0.6.0

Image: https://github.com/OGDrNeutron/NeutronOS/releases/download/gemini-0.6.0/NeutronOS-Gemini-0.6.0.img.xz

Signed manifest and signed checksums are release assets and are mirrored here as small metadata files. Gemini 0.6.1 adds public-catalog support for Native Recovery and Full IMG Restore. Keep My Data is disabled until complete preservation can be verified; clean erase requires external offline Recovery and explicit target confirmation.
