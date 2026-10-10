# ⚛️ NeutronOS Apollo

<p align="center">
  <img src="themes/Default/atom.png" alt="NeutronOS Atom" width="140">
</p>

<p align="center">
  <strong>Controller-first Linux shell for Raspberry Pi.</strong><br>
  A custom QML-powered operating shell built for HDMI, gamepad navigation, local security, full-screen apps, and a polished console experience.
</p>

<p align="center">
  <img alt="Status" src="https://img.shields.io/badge/status-alpha-blue">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Raspberry%20Pi-purple">
  <img alt="Shell" src="https://img.shields.io/badge/shell-Qt%20QML-cyan">
  <img alt="Input" src="https://img.shields.io/badge/input-controller%20first-green">
  <img alt="Codename" src="https://img.shields.io/badge/codename-Apollo-red">
</p>

---

## 🌌 What is NeutronOS?

**NeutronOS Apollo** is a custom full-screen Linux shell designed around one core idea:

> **The controller is the primary input device — not a keyboard, not a mouse.**

It is built for Raspberry Pi HDMI setups where the system boots directly into a polished QML interface with login, dashboards, app launching, system controls, service management, terminal access, and a full-screen app host.

NeutronOS is not just a web dashboard.  
It is the beginning of a complete controller-first OS experience.

---

## ✨ Core Features

### 🎮 Controller First

NeutronOS is designed around PlayStation-style controller navigation.

| Control | Action |
|---|---|
| D-Pad / Stick | Navigate |
| X / Cross | Select / Primary Action |
| O / Circle | Back / Cancel |
| Triangle | Context / Details |
| Options / Start | Menu / Options |
| PS / Home Hold 3s | Global Power Menu |
| PS / Home x5 on Console | Developer Mode |
| PS / Home x5 on armed Login Card | Mercury Edition Easter Egg |

---

## 🔐 Secure Local Login

NeutronOS uses a local-first security flow.

- First login uses the local Linux user password.
- After verification, the user creates a controller button combo.
- Future unlocks use the controller combo.
- Combos are hashed, not stored as plaintext.
- Failed attempts can trigger lockout.
- Login is controller friendly.
- Keyboard fallback exists for setup and recovery.

---

## 🧭 Shell Runtime Flow

NeutronOS uses a clean runtime flow:

qml/Main.qml
  ├── qml/LoginScreen.qml
  ├── qml/Console.qml
  └── qml/apps/AppHost.qml