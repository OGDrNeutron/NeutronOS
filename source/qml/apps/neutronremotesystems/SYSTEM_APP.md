# Neutron Remote Systems — OS-owned system app

This application is part of the NeutronOS base system beginning with the system-app migration.
It is not App Store-owned and must not be uninstalled through App Store transactions.

Runtime ownership:
- `/usr/local/lib/neutronos/remote-systems-bridge.py` — built-in administrative bridge, root-owned 0755.
- `/usr/local/lib/neutronos/neutron-remote-service.py` — Remote Systems broker, root-owned 0755.
- `/etc/systemd/system/neutron-remote-service.service` — OS-owned broker unit.

Third-party/App Store remote providers remain package-owned and continue to use signed registry/hash validation.
