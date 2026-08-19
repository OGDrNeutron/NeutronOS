# ⚛️ NeutronOS

**🛡️ Secure. 🧠 Intelligent. ⚡ Unstoppable.**

NeutronOS is a controller-first Linux operating environment designed to combine a console-style user experience with desktop functionality, media features, system management, local AI capabilities, and an active defensive security layer.

The current platform, **NeutronOS Apollo**, is being developed around Debian Linux with a custom Qt/QML shell and a strong focus on usability from a game controller without making keyboard and mouse support an afterthought.

> 🚧 **Project status:** Active development / pre-release beta  
> ⚛️ **Current platform:** NeutronOS Apollo  
> 🍓 **Primary development target:** Raspberry Pi 4B, ARM64  
> 🐧 **Base system:** Debian 13 (Trixie)  
> 🧩 **Shell technology:** Qt 6 / QML

---

## 🚀 What is NeutronOS?

Most Linux desktops were designed around a keyboard, mouse, windows, menus, and a user who is already comfortable administering Linux.

NeutronOS takes a different approach.

The goal is to provide a polished, controller-first interface that can function as:

- A living-room console interface
- A general-purpose Linux computer
- A media center and media server
- A game launcher
- A local network management system
- A defensive security workstation
- A local AI platform
- A Raspberry Pi management environment
- A foundation for dedicated NeutronOS hardware

NeutronOS is intended to remain approachable for everyday users while exposing deeper Linux, networking, development, and security controls for advanced users.

---

## 🎯 Design Goals

### 🎮 Controller First

The main NeutronOS interface is designed to be fully navigable with a game controller.

Keyboard and mouse input remain available, but they are not required for normal shell navigation.

### 🛡️ Secure by Default

NeutronOS is being designed around continuous system awareness rather than treating security as a collection of disconnected utilities.

The long-term security model ranges from passive monitoring to increasingly restrictive defensive responses, with the user retaining control over how aggressively the system reacts.

### 🧩 Modular

Applications remain independent from the core operating environment.

### 🖥️ Console-Level Presentation

The interface is designed around:

- Full-screen applications
- Controller navigation
- Dashboard widgets
- Large readable layouts
- Premium visual feedback
- Minimal dependence on traditional desktop UI conventions

### 🐧 Linux Underneath

The visual shell is not intended to hide the underlying system from advanced users.

Terminal access, services, networking, storage, Docker, logs, security state, and other Linux functionality remain part of the platform.

---

## 🧭 Core Interface

The NeutronOS shell currently includes or is being developed around the following major areas:

### 🔐 Login and Lock Screen

- Linux account authentication
- Controller-based unlock combinations
- Lockout handling
- Developer-mode controls
- Controller-driven session actions
- Animated unlock feedback

### 📊 Dashboard

The main dashboard provides quick system information and application access.

Dashboard information includes:

- CPU usage
- RAM usage
- CPU temperature
- Boot storage
- Expansion/media storage
- Network status
- Local IP address
- Tailscale IP address
- Upload/download activity
- Uptime
- User/session information
- Security state

Dashboard widgets are designed around **Small**, **Medium**, and **Large** layouts where appropriate.

### 🧰 Application Carousel

Applications are presented through a controller-friendly carousel rather than a conventional desktop launcher.

Current and planned NeutronOS applications include:

- Settings
- Security
- Jellyfin
- qBittorrent
- App Store
- File Manager
- Terminal
- Browser
- Music
- Gallery
- Games
- Storage
- Logs
- Docker
- Media Optimizer
- Codex / development tools
- Additional NeutronOS utilities

---

## 🛡️ Security

Security is one of the central parts of NeutronOS rather than a secondary utility.

The NeutronOS Security application is being developed to provide a unified view of system security and defensive controls.

Current design areas include:

- Overall security score
- DEFCON-style system state
- System integrity monitoring
- Threat protection
- Malware defense
- Ransomware protection
- Firewall state
- Network monitoring
- Listening-port inspection
- SSH access controls
- Tailscale controls
- Peripheral monitoring
- Banned sources
- Quarantine
- Security events
- Suspicious activity
- Recovery controls
- Password vault
- Security scans
- Response engine
- Learning mode

The project goal is to allow the user to choose how defensive behavior escalates, from observation and logging through progressively stronger containment actions.

NeutronOS is a defensive platform. Security features are intended to protect the device, its users, and authorized systems.

---

## 🌐 Networking

NeutronOS includes dedicated networking work for environments where the device may operate with or without normal Internet access.

Planned and active networking features include:

- Known Wi-Fi auto-connect
- Wi-Fi management
- Ethernet management
- Local hotspot support
- Offline LAN operation
- Offline Wi-Fi operation
- DHCP/DNS services for local devices
- Tailscale integration
- Local service discovery
- Controller-friendly network setup

One use case is allowing local media clients, including televisions and streaming devices, to communicate with NeutronOS even when no external Internet connection is available.

---

## 🎬 Media

NeutronOS is being designed to serve both as a media client and as a media server.

Media-related work includes:

- Jellyfin integration
- Local media libraries
- Music playback
- Gallery browsing
- Media optimization
- qBittorrent integration
- Local network playback
- Roku-oriented local playback workflows
- Randomized live-TV style playback experiments

---

## 🌍 Browser

NeutronOS includes a controller-oriented browser built around Qt WebEngine.

Controller actions are designed to cover common browser functions such as:

- Back
- Forward
- Refresh
- URL entry
- Tab management
- Scrolling
- Pointer movement
- On-screen keyboard access

The browser is designed to run as a separate, unprivileged component rather than unnecessarily sharing privileges with the main shell.

---

## ⚡ Performance Modes

On supported Raspberry Pi hardware, NeutronOS includes configurable performance profiles.

Current Pi 4 development targets include:

| Mode | Target CPU Frequency |
|---|---:|
| Eco | 1.2 GHz |
| Normal | 1.5 GHz |
| Performance | 2.0 GHz |

Performance behavior may vary by hardware, cooling, firmware, and system configuration.

---

## 🧱 Current Development Hardware

The primary development platform is currently:

- Raspberry Pi 4B
- ARM64
- Debian 13 Trixie
- HDMI display output
- Qt 6
- QML
- systemd
- Controller-first input

NeutronOS is also being designed with future dedicated x86-64 console-style hardware in mind.

Planned dedicated hardware work includes:

- Micro-ATX / compact PC designs
- AMD Ryzen platforms
- Gaming-capable graphics
- Local AI workloads
- Compact cooling
- Console-style enclosures
- Horizontal or vertical placement
- Slot-loading optical media support

---

## 🏗️ Architecture

At a high level, the current NeutronOS platform consists of:

```text
Debian Linux
│
├── systemd services
├── NeutronOS security services
├── networking services
├── application services
│
└── NeutronShell
    │
    ├── Qt 6
    ├── QML interface
    ├── Login / Lock Screen
    ├── Dashboard
    ├── App Host
    ├── Controller Navigation
    └── NeutronOS Applications
```

The main shell and individual applications are intentionally being separated where practical so application failures or removal do not compromise the core OS.

---

## 📁 Project Structure

The development tree is organized around the NeutronOS shell and its supporting components.

Typical top-level areas include:

```text
NeutronOS/
├── qml/
│   ├── Main.qml
│   ├── LoginScreen.qml
│   ├── Console.qml
│   ├── apps/
│   └── components/
├── src/
├── themes/
│   └── Default/
├── state/
├── build/
└── CMakeLists.txt
```

The exact tree may change as NeutronOS moves from a custom shell toward a more complete operating-system distribution.

---

## 📦 Application Packaging

NeutronOS applications are intended to be distributed through the NeutronOS App Store using a transactional package model.

Packaging principles include:

- Track package-owned files
- Install only required dependencies
- Keep optional applications independent from the core OS
- Do not remove shared or system-owned dependencies during uninstall
- Ensure uninstall removes only files owned by that package
- Avoid application lifecycle scripts unless explicitly supported by the package model
- Preserve core NeutronOS functionality when optional apps are absent

This is intended to make application installation and removal predictable rather than turning `/usr` into an archaeological dig.

---

## 🧠 Development Philosophy

NeutronOS development follows several rules intended to reduce regressions:

1. Verify the complete end-to-end change before treating a patch as ready.
2. Avoid guessing missing files, dependencies, or system state.
3. Keep non-system applications independent.
4. Preserve known-working system behavior unless a change specifically requires modification.
5. Validate builds before replacing live binaries.
6. Treat security-sensitive services and systemd behavior carefully.
7. Prefer reversible and narrowly scoped changes.
8. Keep controller navigation consistent across applications.
9. Keep application layouts visually consistent.
10. Test on the actual target hardware whenever system behavior depends on the Pi, GPU, input stack, services, or boot process.

---

## 🔨 Building

NeutronOS is under active development and the build/install process is still evolving.

Because the project touches boot behavior, systemd, networking, security services, Qt/QML, hardware acceleration, and privileged system components, this README intentionally does not publish a generic one-line installer that has not been validated against the current repository state.

Development builds should use the repository-specific build instructions associated with the current release or branch.

On the current Raspberry Pi development target, verified rebuild workflows generally use up to three parallel build jobs when appropriate:

```bash
-j3
```

Exact commands, dependencies, paths, and deployment steps should be taken from the current release documentation.

---

## 💾 Installation

A public installation workflow is not yet considered stable.

The intended future installation paths include:

- Prebuilt NeutronOS images
- Upgrade packages
- NeutronOS App Store packages
- Dedicated NeutronOS hardware

Until a release is marked installable, cloning the repository should be treated as a development workflow rather than a production installation method.

---

## 🗺️ Roadmap

Major development areas include:

- Complete dashboard redesign
- Unified application hosting
- Running-app tray
- Notification center
- Expanded security engine
- Security event workflows
- Recovery improvements
- App Store packaging
- Improved browser integration
- Controller-first file management
- Media workflows
- Local AI integration
- Dedicated x86-64 hardware
- Installer and recovery image
- Full Debian-flavor transition
- Developer documentation
- Public release tooling

---

## 🚧 Current Status

NeutronOS is not yet a finished consumer operating system.

Features may be incomplete, experimental, hardware-specific, or subject to major architectural changes.

Expect:

- Breaking changes
- UI revisions
- Service changes
- Packaging changes
- Security-model changes
- Hardware compatibility changes

Do not deploy development builds in environments where failure could cause loss of critical data or service availability.

---

## 🖼️ Screenshots

Screenshots, UI references, hardware concepts, and application previews will be added to the repository as the public presentation of NeutronOS is finalized.

Suggested future repository layout:

```text
docs/
├── screenshots/
├── architecture/
├── security/
├── hardware/
└── development/
```

---

## 🤝 Contributing

NeutronOS is currently under active development.

Public contribution guidelines, coding standards, issue templates, testing requirements, and pull-request rules will be added as the repository is prepared for broader collaboration.

Until then, contributions should be coordinated against the current development roadmap to avoid conflicting architectural changes.

---

## 🛡️ Security Reporting

Do not publish unpatched NeutronOS security vulnerabilities in public issues.

A dedicated security disclosure process should be used once the project opens for public testing.

Security reports should include:

- Affected version or commit
- Affected component
- Reproduction conditions
- Expected behavior
- Observed behavior
- Security impact
- Logs or evidence when safe to provide

---

## ⚠️ Disclaimer

NeutronOS is pre-release software.

It is provided for development and testing and may contain defects, incomplete security controls, unstable interfaces, or hardware-specific behavior.

Users are responsible for maintaining backups and for validating NeutronOS before using it with important systems or data.

---

## 📜 License

A public software license has not yet been specified for this repository.

Until a license is explicitly added, no permission should be assumed beyond rights granted by applicable law.

---

## ⚛️ Project

**NeutronOS Apollo**

**🛡️ SECURE. 🧠 INTELLIGENT. ⚡ UNSTOPPABLE.**
