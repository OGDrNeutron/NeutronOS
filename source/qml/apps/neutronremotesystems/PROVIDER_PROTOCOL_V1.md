# NeutronOS Remote Service Provider Protocol v1

`Neutron Remote Systems` contains no app-specific provider data. Remote-capable
apps advertise themselves through their own signed `.Napp` manifest:

```json
"remoteCapabilities": [
  {
    "id": "web",
    "provider": "scripts/apps/example/example-remote-provider.py",
    "broker": "neutronos-remote-service",
    "defaultAllowed": false
  }
]
```

For protocol v1 the provider executable must be a direct child of
`scripts/apps/<package-id>/` so the existing `PackageAppBridgeManager` can start
it by helper filename. If the package already declares a `backend` package-helper,
the remote capability provider must be that same backend entrypoint. The current
OS bridge owns one helper process per app id, so a second independent helper for
the same app would collide with the app's normal backend. Remote-capable package
helpers therefore implement both their normal app protocol and the `remote.*`
provider messages below.

## Provider bridge messages

Remote Systems sends JSON-line messages through the OS-owned package bridge.
A provider should accept:

- `{"action":"remote.describe","protocol":"neutronos-remote-service","protocolVersion":1,"capabilityId":"..."}`
- `{"action":"remote.refresh",...}`
- `{"action":"remote.set","capabilityId":"...","key":"...","value":...}`
- `{"action":"remote.invoke","capabilityId":"...","key":"..."}` for provider-declared action rows

`remote.describe` and `remote.refresh` should emit:

```json
{
  "type": "remote-description",
  "protocol": "neutronos-remote-service",
  "protocolVersion": 1,
  "capabilityId": "web",
  "serviceAvailable": true,
  "serviceRunning": false,
  "appRemoteEnabled": true,
  "supportedSettings": {
    "network.customPort": {"supported": true, "writable": true, "type": "number", "minimum": 1024, "maximum": 65535},
    "security.tlsRequired": {"supported": true, "writable": true, "type": "boolean"},
    "permissions.microphone": false
  },
  "values": {
    "network.customPort": 8443,
    "security.tlsRequired": true
  }
}
```

A successful `remote.set` should emit a refreshed `remote-description` or:

```json
{"type":"remote-setting-updated","key":"network.customPort","value":8443}
```

The provider owns its settings and app-side Remote Enabled preference. Remote
Systems never edits provider config files directly.

## Broker lease gate

A provider must not bind or expose its remote listener until the central broker
returns an active lease. Providers connect to:

`/run/neutronos/remote-service-provider.sock`

and send one JSON line:

```json
{
  "op": "lease",
  "appId": "example",
  "capabilityId": "web",
  "appRemoteEnabled": true
}
```

The broker validates the kernel peer credentials, requires the provider to be a
child of `neutronos.service`, binds identity to the actual registered provider
script position (not arbitrary argv tokens), verifies the capability declaration,
then verifies the Remote Systems grant and its expiry before returning:

```json
{
  "ok": true,
  "active": true,
  "leaseId": "...",
  "expiresAt": "2026-08-26T03:00:00+00:00",
  "durationCode": "6h"
}
```

A provider must re-check its lease periodically while listening and shut down
promptly when `active` becomes false. The standard maximum re-check interval is
30 seconds; providers may use a shorter interval.

The effective security rule is always:

`appRemoteEnabled && activeRemoteSystemsGrant && unexpiredLease`

Remote Systems grants are app-level. Every declared capability from that app is
subject to the same app-level Remote Systems gate, while each provider still
controls its own app-side enable state and capability-specific settings.
