# Apollo 1.0.1 final repair candidate build

Source base: Git `b0663374e0c627aa2438ec724c83990f484255e1` plus the complete Apollo 1.0.1 working tree.

The existing configured build directory is `staging/apollo-1.0.1-build`. Compile and test with no more than two parallel jobs:

```sh
cmake --build staging/apollo-1.0.1-build --parallel 2
ctest --test-dir staging/apollo-1.0.1-build --output-on-failure -j2
python3 source/apollo-1.0.1-working/scripts/neutronos-qml-audit.py source/apollo-1.0.1-working/qml
```

Image integration starts with the preserved clean `output/NeutronOS-Apollo-1.0.1.img.xz`. Decompress it to a distinct raw candidate, mount only that candidate, stage source-backed files and the compiled `NeutronShell`, compare hashes, and atomically install them. Update the privileged-helper watchdog hashes, synchronize, unmount, detach the loop device, verify both filesystems and the partition table, then compress with XZ CRC64 using no more than two threads.

The candidate remains a two-partition image. Storage provisioning creates partition 3 only on the eventual installation drive after explicit First Boot confirmation.
