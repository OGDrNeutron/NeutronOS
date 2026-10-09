# Gemini Games

## 0.1.0-review.1

- Independent Gemini AMD64 identity and package-owned C++/QML implementation.
- Eight native pages with dark blue/red Gemini design, artwork, focus and footer.
- Persistent per-account libraries with background incremental monitoring,
  disconnected media retention, favorites, history and duplicate candidates.
- Header/structure-based detection and conservative runtime recommendations.
- Configured runtime launch plans, owned-process shutdown and UI/scanner quiescence.
- Real evdev/uinput gamepad service, per-game remaps/assignment and reserved Home hold.
- Conditional Gemini system modal and actual AppManager task-switching hooks.
- Existing OpenPGP signed NAPP/catalog format; publication staged locally only.

This is a development review version. Actual-game controllers, compositor focus,
privileged install/update/removal and hardware performance remain blocked. Steam/
Proton ownership, automatic emulator mappings and runtime installation are
incomplete. Review the validation and compatibility documents before deployment.

* Reuse the installed Gemini Recovery EnergyAtom and adaptive render quality
  directly in the footer; release them when hidden and use a system-clock footer
  countdown independent of rendering cadence.
* Add account-scoped custom artwork discovery, strict title matching, ambiguity
  selection, manual assignment/reset, content-hashed thumbnail cache and watched
  updates. Original images remain read only and outside package ownership.

* Named-button per-game controller editor, duplicate-free button swaps, stick
  inversion, defaults, Save/Cancel and preserved focus.
* Unknown/unsupported runtime adapters no longer advertise launch, owned-process
  or controller-interception capabilities.

* Runtime approval review through existing AppStoreManager, authenticated
  candidate filtering, actual footprint estimates, explicit confirmation and
  changed-metadata/unknown-estimate safeguards; no automatic installation.
* ZIP/7z archives are indexed as requiring extracted data and cannot launch
  directly. Known redistributable directories are excluded from game detection.
* Read-only discovery of the supplied external library, with stable rescanning
  and safe removal of the library root.

* Account identity guards prevent stale singleton library/artwork/settings access
  after account changes; preferences/messages/UI state reset between accounts.

* Recognize verified UDF-disc containers without treating PC installer discs as
  emulator-ready games; explicit mounting/extraction and runtime setup required.
