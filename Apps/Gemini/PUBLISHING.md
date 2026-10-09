# Gemini NAPP publication

This retained directory maps to `Apps/Gemini/` in the existing
`OGDrNeutron/NeutronOS` repository. The Gemini 0.5.4 handoff publishes this public scaffold through the existing
repository history. Keep existing `Apps/index.json` and every Apollo package/URL
unchanged. Publish Gemini packages and their catalog only under `Apps/Gemini/`.
The bundled empty catalog is already signed and may be used to create the new
repository area before any Gemini application is released.

## Build and sign outside the image

Use an external GnuPG home owned by the trusted publisher. It must contain the
release signing identity `F1A1E10BD2DB35060D6E61187CEB773D5ABD64B0` and must never
be placed inside the package input tree or any distributable archive.

1. Prepare the permitted payload/system/build files from PACKAGE_FORMAT.md.
2. Write `manifest.json` with schema 1, application ID, version, permissions,
   `platforms: ["gemini"]`, `architectures: ["amd64"]`, and `fileHashes` mapping
   every archive file except the manifest/signature to its SHA-256. A genuine
   cross-platform package may explicitly name both platforms and architectures;
   package content must support every advertised combination.
3. Ensure `payload/qml/apps/<id>/app.json` has the same ID and version. Keep any
   existing declarative dependency/system-file declarations and safety rules.
4. Sign the exact manifest bytes using GnuPG's detached signature operation:
   `gpg --homedir EXTERNAL_TRUSTED_HOME --local-user F1A1E10BD2DB35060D6E61187CEB773D5ABD64B0 --detach-sign --output manifest.json.sig manifest.json`.
5. Create the NAPP ZIP containing those exact manifest/signature bytes and all
   hashed files. Never include the GnuPG home, private key or build credentials.
6. Test it with the installed `/usr/local/libexec/neutronos-napp-verify verify PACKAGE.napp` on Gemini. A legacy Ed25519 signature is not accepted.
7. Add a catalog entry to `Apps/Gemini/index.json` containing matching ID,
   version, explicit platform/architecture, relative `packageUrl`, and SHA-256
   of the finished NAPP. Optional UI fields retain the existing storefront UX.
8. Sign the exact finished catalog as adjacent `index.json.sig` using the same
   external release identity. Changing even whitespace requires a new signature.
9. Publish the NAPP, index and detached signature together. The image queries
   `https://raw.githubusercontent.com/OGDrNeutron/NeutronOS/main/Apps/Gemini/index.json`.

Install/Update is offered only from an authenticated compatible catalog. A newer
version with the same Gemini ID is compared with the installed Gemini record;
Apollo records are never used as a Gemini version source. Packages signed with
the obsolete dedicated App Store key must be rebuilt and re-signed externally;
verification is not weakened for compatibility.

No automatic public-key import or key rotation exists. A separately authenticated
OS trust-root migration is required for rotation. Debian Secure Boot signing
must remain independent.
