# Personal artwork and the Recovery footer atom

The production account resolver is Gemini's existing `HumanHome::path()` in
`HumanAccountPolicy.h`. It validates a local human passwd account and its
`/NeutronOS/<lowercase-account>` home. Existing personal app data uses lowercase
`apps`. The independently owned package ID is `gemini-games`, so its resolved
artwork location is:

`/NeutronOS/<current-account>/apps/gemini-games/artwork/`

This preserves Gemini's lowercase personal-data convention and package
isolation. It does not alter system-wide QML/package installation under
`/opt/neutronos`. No example account name is hardcoded. The directory shown in
Settings and the artwork picker is the current validated account's actual path.
Thumbnail cache and library assignments live alongside it in `artwork-cache/`
and `library.json`. Account switching recreates these managers for the validated
account, and is refused while a game is active. Redirected personal directories
and artwork symlinks are rejected.

`GameArtwork` scans in a QtConcurrent worker. Exact complete filename stems
have priority; Unicode normalization, capitalization, whitespace and common
separators provide a second complete-title comparison. Prefix, substring and
fuzzy matches are never used. Two equally valid matches require a selection;
no arbitrary winner is assigned. Extension matching ignores case. Available
Qt image plugins determine whether PNG/JPEG/WebP are enabled.

Library discovery schedules artwork discovery. Directory/file watchers coalesce
updates without a game-library rebuild. Refresh Artwork is available in Library
Settings and the picker. Full content hashes invalidate cached 512×768 PNG
thumbnails after changes. Unchanged files reuse their cache and normal cards
load thumbnails asynchronously. Original images are read only. Scanning and
periodic presence checks pause during gaming sessions. A missing manual image
preserves its assignment and falls back to metadata artwork or the placeholder.

The controller picker previews the current artwork and assigned path, lists
available images, and supports X to assign, refresh or restore automatic
matching. Up/Down chooses actions; Circle returns focus. Assignments are saved
atomically through the existing Games library index. They are user data, absent
from package destinations and `uninstallState`. Updates/removal are not allowed
to own original images or game files.

## Exact Recovery animation

The footer loads the existing installed `gemini/EnergyAtom.qml` and
`gemini/GeminiRenderQuality.qml` from the shell's configured QML root. It uses
Gemini's existing registered `GeminiRingGeometry`, shaders and textures. No
Recovery animation, asset or geometry source is copied into the NAPP or edited.
The original blue/red orbit phases, 3800/4900/6000 ms animation declarations,
particles, materials and adaptive bloom are reused directly.

A square 60-pixel area at the reference 1672-pixel width scales uniformly with
the interface and precedes NeutronOS branding. Hidden footers unload both
components, releasing their rendering/animation resources. Gameplay/window
visibility also gates their loaders. The initial footer countdown uses a
precise single-shot Qt system timer, independent of animation/frame timing;
Start cancels it and toggles persistent manual visibility.

## Fresh evidence and remaining checks

`validation/ui-results.json` contains 67 passing checks on an isolated Weston 14
OpenGL display using Gemini's actual Qt 6.8.2 libraries and an AMD RX470.
`footer-atom-frame-1.png` and `footer-atom-frame-2.png`, captured 600 ms apart,
show different atom pixels. The exact component is loaded; its loader and item
are absent after the footer hides. Cards and the management preview show the
custom fixture image, and controller actions assign/reset it successfully.
This is host GPU evidence; the separate TCG VM has not produced a Qt UI frame.

Backend tests verify exact/normalized/ambiguous matches, PNG/JPEG decoding,
new-file detection, replaced-file hash/cache updates, missing-file fallback,
manual-assignment persistence across manager restarts, account separation and
symlink exclusion. WebP's plugin is absent in this retained Qt image-plugin set;
it is accurately omitted from supported formats. Physical-controller artwork
navigation, a real reboot, and actual Games package update/reinstall/removal
preservation remain outstanding; simulated restart evidence is not reboot proof.


The Games singleton now checks the authoritative account identity on every
personal-data read and write. Root and app identity-change hooks refresh it;
preferences, messages and UI state are cleared before loading another account.
An owned game still belonging to a different account is quarantined from the
new account's controls/data until its original owner returns or it exits.
The actual HumanHome/backend account-switch regression passes in a private
filesystem namespace inside the existing VM; real physical session switching
remains unverified.
