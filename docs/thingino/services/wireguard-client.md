WireGuard Client
================

Thingino can operate as a WireGuard client. The camera-side configuration can be
entered manually in the Web UI or imported from an external provisioner.
Manual configuration remains fully supported and does not require any
provisioner service.

This document describes the client-side fields, how they map to WireGuard, and
how the Thingino service behaves at runtime.

Prerequisites
-------------

- A camera build that includes the `wg` userspace tool.
- A WireGuard server with a peer entry for the camera.
- The following values from the server administrator:
  - camera tunnel address
  - server endpoint
  - server public key
  - optional pre-shared key
  - allowed networks

Where to configure it
---------------------

Open the WireGuard page in the Thingino Web UI. The page stores its settings in
the `wireguard` section of `/etc/thingino.json` and the service is managed by
`/etc/init.d/S42wireguard`.

Field reference
---------------

### Run WireGuard at boot

Enables the client during normal boot. If this is disabled, the service will
not start automatically.

### Private Key

This is the private key for the camera itself.

- Required.
- Stored as `wireguard.privkey`.
- Corresponds to `PrivateKey` in the `[Interface]` section.
- The UI can generate this key on the camera.

### Public Key (derived)

This is derived from the private key and shown for reference.

- Not entered manually.
- Useful when creating the matching peer entry on the server.

### Pre-Shared Key

Optional extra symmetric key shared between the camera and the server peer.

- Stored as `wireguard.peerpsk`.
- Corresponds to `PresharedKey` in the `[Peer]` section.
- Must match on both sides if used.

### Address

This is the camera's internal WireGuard address.

- Required.
- Stored as `wireguard.address`.
- Applied with `ip address add` to `wg0`.
- Usually a single host address such as `10.13.13.5/32`.

### Port

Optional local listen port for the camera.

- Stored as `wireguard.port`.
- Written as `ListenPort` in the `[Interface]` section.
- Most client setups can leave this empty.

### DNS

Optional DNS server list used while WireGuard is up.

- Stored as `wireguard.dns`.
- Comma-separated values are accepted.
- When set, Thingino rewrites the working resolver file while the tunnel is up
  and restores the original resolver configuration on stop.

### Endpoint host:port

The public or LAN endpoint of the WireGuard server.

- Required.
- Stored as `wireguard.endpoint`.
- Written as `Endpoint` in the `[Peer]` section.
- Example: `vpn.example.com:51820` or `192.168.88.20:51820`.

### Peer Public Key

The public key of the remote server peer.

- Required.
- Stored as `wireguard.peerpub`.
- Written as `PublicKey` in the `[Peer]` section.

### MTU

Optional interface MTU.

- Stored as `wireguard.mtu`.
- Applied with `ip link set mtu ... up dev wg0`.
- Leave empty unless you have a specific path MTU problem.

### Persistent Keepalive

Optional keepalive interval in seconds.

- Stored as `wireguard.keepalive`.
- Written as `PersistentKeepalive` in the `[Peer]` section.
- Recommended value for NATed clients is usually `25`.

### Allowed CIDRs (networks)

Comma-separated list of networks routed through the tunnel.

- Stored as `wireguard.allowed`.
- Written as `AllowedIPs` in the `[Peer]` section.
- Thingino also adds matching routes to `wg0` at startup.
- Example split tunnel: `10.13.13.0/24`
- Example full tunnel: `0.0.0.0/0`

Manual configuration workflow
-----------------------------

1. Create a camera private key in the UI or generate one elsewhere.
2. Copy the derived camera public key to the WireGuard server.
3. Create a server peer entry for the camera using the camera public key and a
   unique camera tunnel address.
4. Enter the server endpoint, server public key, allowed networks, and optional
   pre-shared key in the camera UI.
5. Enable `Run WireGuard at boot` if you want the tunnel to start
   automatically.
6. Save the settings.
7. Start the client with the UI toggle or with `/etc/init.d/S42wireguard force`
   for immediate testing.

Manual example
--------------

Example camera-side values for a split-tunnel setup:

```text
Private Key: <camera private key>
Pre-Shared Key: <optional shared key>
Address: 10.13.13.5/32
Port:
DNS: 1.1.1.1
Endpoint: 192.168.88.20:51820
Peer Public Key: <server public key>
MTU:
Persistent Keepalive: 25
Allowed CIDRs: 10.13.13.0/24
Run WireGuard at boot: enabled
```

What Thingino does at startup
-----------------------------

When `S42wireguard` starts, it:

1. Reads the `wireguard` section from `/etc/thingino.json`.
2. Refuses normal startup if `enabled` is not `true`.
3. Creates interface `wg0`.
4. Builds a temporary WireGuard configuration with the interface and peer
   settings.
5. Applies it with `wg setconf`.
6. Assigns the configured tunnel address.
7. Applies optional MTU and DNS overrides.
8. Adds routes for each configured allowed network.
9. Installs the WireGuard watchdog cron job.

Useful service commands
-----------------------

```bash
/etc/init.d/S42wireguard start
/etc/init.d/S42wireguard stop
/etc/init.d/S42wireguard restart
/etc/init.d/S42wireguard force
```

`force` is useful for testing a configuration immediately even when `Run
WireGuard at boot` is disabled.

Checking status on the camera
-----------------------------

```bash
wg show
ip addr show wg0
ip route | grep wg0
```

Common problems
---------------

### The interface starts but no handshake appears

- Verify `Endpoint host:port` is reachable from the camera.
- Verify the server peer entry uses the camera public key.
- Verify the server peer allows the camera address.
- If the camera is behind NAT, set `Persistent Keepalive` to `25`.

### The handshake works but traffic does not pass

- Check `Allowed CIDRs` on the camera.
- Check `AllowedIPs` on the server peer.
- Make sure the server forwards traffic between peers if you expect peer-to-peer
  communication through the server.

### DNS breaks while the tunnel is up

- Leave `DNS` empty if you do not want WireGuard to override resolver settings.
- If you do set DNS, confirm the configured resolver is reachable over your
  chosen routing policy.

### The camera becomes unreachable after enabling WireGuard

- Use split tunneling first, for example `10.13.13.0/24`, before trying a full
  tunnel.
- Keep local LAN management access until the VPN path is verified.
- Use the service `force` mode or the UI toggle for testing before enabling it
  permanently at boot.

Provisioner import
------------------

The provisioner is optional. If used, the camera can import a profile from an
HTTP service.

- The imported profile is stored in the same `wireguard` config section used by
  manual configuration.
- Imported profiles are saved enabled by default.
- If the provisioner does not supply a keepalive value, Thingino defaults it to
  `25` during import.

For details on building a compatible provisioner, see
`wireguard-provisioner.md` in the same directory.