# Games 0.1.0-review.3

Requires Gemini 0.5.6, Qt 6.8.2 and shared-desktop-carousel capability v1.

* Controller folder browser with authorized volumes, breadcrumbs, manual paths through the NeutronOS keyboard, explicit folder selection, validation and atomic persistence.
* Compact footer consumes the desktop carousel and its existing customization/order state, with running app selection, NetworkManager connectivity, reported controller battery and local time.
* Circle opens the shared exit confirmation; active dialogs retain input priority.
* Three-launch help now owns controller press/release input in Gemini 0.5.6.
* Settings and folder lists wrap long paths and scroll within bounded panels; focus borders remain inside their controls.
* Installed icon and poster payloads retain the official App Store artwork.

Physical controller, storage, GPU and gameplay acceptance remains pending. This review package contains its native application module. Installation, update and removal use the App Store application transaction; no OS source build is included.

- Correct compact footer order: NeutronOS, Running Apps, shared carousel, Wi-Fi signal, controller battery, clock. Render all three Wi-Fi arcs and dot in the authoritative connection status color. Preserve Options focus transfer and shared desktop carousel persistence.
