# Codex

## 1.0.0-alpha.3

### Current Release

- Controller-first Codex coding agent interface built for NeutronOS.
- Connects to the existing local Codex app-server runtime.
- Create new coding sessions directly from the controller.
- Resume previous Codex sessions.
- Browse and reopen session history.
- Stream Codex activity and task progress live inside the app.
- Send prompts through the integrated NeutronOS virtual keyboard.
- Review and respond to Codex approval requests.
- Interrupt active Codex turns when needed.
- Warns before closing while an active task is still running.
- Displays the active Codex model and reasoning effort.
- Supports official Codex authentication and initialization.
- Maintains repository and document filesystem access through scoped permissions.
- Supports background execution, notifications and system telemetry integration.
- Uses the Codex CLI runtime already installed on NeutronOS.
- Does not force unnecessary Debian dependency installation during updates.
- Does not force Codex CLI upgrades when the existing runtime already works.
- Distributed as an officially signed NeutronOS App Store package.
