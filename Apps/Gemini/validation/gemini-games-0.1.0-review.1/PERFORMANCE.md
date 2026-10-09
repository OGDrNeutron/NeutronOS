# Measured Games UI resource use

Environment: Existing isolated Weston 14 / Gemini Qt 6.8.2 / AMD RX470 OpenGL; scanner fixtures; no game launched by this runner.

These are five-second samples of the actual Qt test process with no game
running. CPU is percent of one logical CPU.

| Phase | CPU | RSS |
|---|---:|---:|
| visible idle Games QML | 0.132% | 228300 kB |
| hidden window with released scene resources | 0.115% | 221508 kB |
| restored window | 1.346% | 246392 kB |

These samples do not establish sustained memory savings, game FPS, whole-OS
background impact or gaming GPU clock/load. Physical game-session measurements
remain pending. The production backend records session samples separately.
