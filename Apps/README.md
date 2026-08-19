# NeutronOS Apps

This directory is the official NeutronOS App Store repository.

Signed `.Napp` packages published here are discovered through `index.json` and verified by NeutronOS before installation.

## Repository layout

```text
Apps/
├── index.json
├── <PackageName>.Napp
└── <PackageName>.Napp.sig
```

Packages use NeutronOS transactional ownership. Package-provided install/uninstall lifecycle scripts are not executed. Dependencies and privileged package-owned files are handled by the NeutronOS App Store transaction layer.
