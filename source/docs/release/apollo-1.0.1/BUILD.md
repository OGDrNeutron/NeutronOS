# Apollo 1.0.1 build and image integration

Source base: Git `b0663374e0c627aa2438ec724c83990f484255e1`.

Configure and compile with no more than two jobs:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DNEUTRONOS_RUNTIME_ROOT=/opt/neutronos
cmake --build build --parallel 2
ctest --test-dir build --output-on-failure
```

The flashable image was produced from the immutable compressed RC1 image by
decompressing to a separate raw working copy. The five recorded Raspberry Pi
Mesa packages were installed with `dpkg --root` into that copy. Source-backed
QML, helpers, version metadata, and the compiled `NeutronShell` were staged,
hash checked, and atomically installed. No partition was resized or added to
the release image. First Boot can create partition 3 only after inspecting the
actual installed drive and receiving explicit confirmation.
