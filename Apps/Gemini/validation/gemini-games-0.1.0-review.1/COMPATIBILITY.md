# Recognition and realistic launch candidates

Recognition identifies evidence and a likely platform; it does not certify a
game's compatibility. Native and Windows executables can also be utilities.
Ambiguous entries retain likely matches and persist the user's selection.
Hardware evidence is read-only CPU flags, architecture, RAM and available DRM
metadata. Graphics APIs and title performance are never inferred from a binary
being present. No runtime listed below has actual-game evidence from this run.

| Game/platform | Detection | Candidate/status |
|---|---|---|
| Native Linux | ELF machine + executable permission | AMD64 candidate; i386 libraries require validation; other architectures rejected |
| Windows PC | MZ, PE signature and machine | Installed Wine candidate; AMD64/i386 only; experimental compatibility |
| Steam | VDF app ID, name and installation directory | Indexed; delegated process tracking/Steam Input blocked |
| Plutonium T6 / BOII | T6 EXE plus zone/launcher structure | Explicit launcher selection and installed Wine; unofficial Linux support, untested |
| Ubisoft / Far Cry 6 | Executable and loader evidence | Local execution blocked; recommend configured remote host |
| Wii U / Breath of the Wild | PowerPC RPX plus code/content; adjacent update/DLC hints | Installed Cemu candidate; CPU/RAM checks, GPU/title/update setup unverified |
| Wii/GameCube | Disc header system magic | Installed Dolphin candidate |
| Nintendo 64 | Cartridge header and byte order | RetroArch with explicitly selected installed core |
| PSP | ISO9660 plus PSP_GAME | Installed PPSSPP candidate |
| PlayStation | Disc/container candidates and user confirmation | DuckStation/PCSX2/RPCS3 candidates only with appropriate installed runtime, BIOS/firmware and title validation |
| RetroArch systems | iNES/Game Boy header; ambiguous generic containers | Compatible installed core required; extension alone does not establish identity |
| ZIP/7z / UDF-disc containers | Extension plus magic / complete volume-recognition sequence | Indexed as requiring extraction; direct launch denied even after manual platform selection |
| Flash | SWF format signature | Installed Ruffle candidate; feature compatibility unverified |
| Android APK | APK/ZIP and AndroidManifest central-directory hints | Indexed; local Android execution unsupported |
| Cloud | Explicit HTTPS `.game.json` descriptor | Indexed; authenticated browser/game lifecycle unsupported |
| Remote streaming | Explicit Moonlight host/application descriptor | Installed Moonlight candidate; pairing and network required |

Game configuration is stored separately from game files. Material executable
signature changes invalidate direct launch. Runtime disappearance also requires
setup review. The material signature samples the first 64 KiB plus size and
mtime; it is not a full-file authenticity guarantee. Duplicate candidates use
sampled content plus size and are never automatically merged or deleted.

Launcher/core existence is checked; a changed separate launcher/core may need
manual configuration review. Large discs and APK containers are probed rather
than exhaustively parsed. Steam sub-executables may appear as separate entries.
No online metadata/artwork database is queried automatically. Local artwork and
user overrides are supported. Library roots remain separate from app ownership;
removal and disconnect retain files and historical metadata.

These candidacy rules follow current installed-runtime evidence. Cemu's stated
memory requirements are documented by [Cemu](https://wiki.cemu.info/wiki/Installation_guide),
and Dolphin hardware caveats by [Dolphin](https://dolphin-emu.org/docs/faq/).
Plutonium's own [documentation](https://www.plutonium.pw/docs/) and
[community Linux guidance](https://forum.plutonium.pw/topic/37097/plutonium-on-linux-ultimate-cross-distro-guide/1)
do not establish an official supported Gemini configuration. No frame-rate or
Far Cry 6 compatibility guarantee is offered.

## Runtime capability matrix

| Adapter | Launch candidate | Pause/resume | Graceful/force stop | Background | Display detach |
|---|---|---|---|---|---|
| Native | Installed executable, architecture/config checks | Explicit offline approval; owned process-group SIGSTOP/CONT | Owned group TERM; explicit KILL after timeout | Same offline approval, unverified with games | Unsupported |
| Wine | Installed runtime + EXE/launcher | Unsupported | Owned process group only; actual wineserver behavior unverified | Blocked | Unsupported |
| Cemu/Dolphin/RetroArch/PPSSPP | Installed executable, needed core/title configuration | Unsupported | Owned process group; runtime exit unverified | Blocked | Unsupported |
| DuckStation/PCSX2/RPCS3/Ruffle | Installed runtime + title requirements | Unsupported | Owned group; unverified with titles | Blocked | Unsupported |
| Moonlight | Installed client, paired host descriptor | Unsupported | Local client group only; remote game remains host-owned | Blocked | Unsupported |
| Steam/Proton | Blocked pending a delegated lifecycle adapter | Unsupported | Unsupported game ownership | Blocked | Unsupported |
| Android/cloud | Unsupported execution | Unsupported | Unsupported | Blocked | Unsupported |

Runtime-specific command lines are used; unsupported capabilities do not become
available merely because POSIX signals exist. Graceful stop currently means
SIGTERM to the owned sandbox/process group, not an emulator-specific save API.
Force close is controller-confirmed only after the timeout. Games are mounted
read-only; titles that require writing next to their original executable need
an explicitly designed save/data setup before support can be claimed.
