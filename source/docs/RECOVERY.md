# NeutronOS Recovery and Safe Mode

Recovery is a one-boot local terminal mode. The boot generator atomically
consumes `/var/lib/neutronos/recovery/next-boot.json`, masks NeutronShell only
for that generated boot transaction, and starts the tty1 recovery console.
The normal service is never disabled. A later reboot returns to the standard
NeutronOS target.

Safe Mode uses the same terminal after three consecutive genuine shell
startup failures. Intentional stop, reboot, and shutdown do not invoke the
failure unit. A LoginScreen-ready shell which remains active for 90 seconds
resets the counter.

The terminal requires normal local Linux authentication. It does not enable
remote access, change networking, repair files, or mutate configuration.
