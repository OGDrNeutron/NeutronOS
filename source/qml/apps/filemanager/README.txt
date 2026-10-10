NeutronOS File Manager
Controller-first three-pane File Manager packaged using the modular qBittorrent app convention.

LAYOUT
- Header/footer match the Security app.
- Left rail matches the Security navigation proportions and typography.
- Center pane defaults to list view and supports icon view with Square.
- Right pane is persistent Preview / Details with Open and Tags controls.

LEFT RAIL
Favorites:
- Home
- Desktop
- Documents
- Downloads
- Pictures
- Music
- Videos

Storage:
- NeutronOS boot/root filesystem
- Real external block-device peripherals only
- tmpfs, overlay, boot helper mounts and container/temp mounts are excluded

Network:
- Shared (/mnt)
- SFTP Servers
- Saved SFTP profiles

SFTP
- Uses SSHFS so remote SFTP content is mounted into File Manager and then uses the normal
  FileManager open/edit/save/copy/move backend.
- Supports SSH key or password authentication.
- Passwords are never persisted.
- Requires the `sshfs` executable.

RIGHT PANE
- Preview occupies about one third of the right pane.
- Human-readable owner/permission details.
- Open button.
- Three-dot Tags button.
- Presets: Work (briefcase), Personal (person), Important (red triangle).
- Custom tags choose a name, color and icon.

NEW FILE / FOLDER
Triangle opens the creation modal.
- Folder: enter a name and create.
- File: enter a name, then choose a type.
- Presets include txt, py, sh, qml, json, js, cpp, h, md, html, css, yaml, xml,
  service, desktop, apk, ipa, zip, tar, log, conf and csv.

CONTROLLER
D-Pad       Navigate
X           Open / select
Square      List <-> Icon view
Triangle    New File / Folder
L1          Back
R1          Forward
R3          Refresh
Start       Actions
Circle      Back / Exit

When focus is in the right Preview pane:
Up/Down     Open <-> Tags
Right       Header three-dot menu
Left        Return to file list

No fullscreen waiting/working overlay is shown during fast directory refreshes.

Tag rail:
- Work uses a briefcase icon
- Personal uses a person icon
- Important uses a red triangle
- Selecting a tag filters the current directory by that tag
