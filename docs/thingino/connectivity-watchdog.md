Connectivity watchdog
=====================

The connectivity watchdog reboots the camera when it cannot reach the network
for a configured number of consecutive probes. It exists for unattended
installations where a wedged network stack would otherwise leave the device
unreachable until somebody power-cycles it.

It is **off by default**. A camera on a marginal Wi-Fi link drops pings
routinely, and a reboot loop is worse than a brief outage, so the watchdog has
to be enabled deliberately.

Enabling
--------

In Web UI, open `Settings` -> `Network` and use the `Connectivity Watchdog`
card:

- `Enable watchdog` - arms the service.
- `Ping target` - IPv4 address to probe. Left empty it probes the default-route
  gateway.
- `Ping interval (seconds)` - delay between probes, 5 to 3600. Default `30`.
- `Failures before reboot` - consecutive failed probes before rebooting, 1 to
  60. Default `3`.

Saving the form writes the settings to `/etc/thingino.json` and restarts the
service immediately; no reboot is required.

Each probe is a single `ping -c 1 -W 5`, so with the defaults the camera
reboots after roughly 60 to 120 seconds without a reply.

Configuration
-------------

The settings live in the `netwatch` object of `/etc/thingino.json`:

| Key          | Type    | Default | Description                                    |
|--------------|---------|---------|------------------------------------------------|
| `enabled`    | boolean | `false` | Arm the watchdog.                              |
| `target`     | string  | `""`    | Probe target; empty means the default gateway. |
| `interval`   | integer | `30`    | Seconds between probes (minimum 5).            |
| `fail_count` | integer | `3`     | Consecutive failures before rebooting.         |

Changing them from a shell:

```
jct /etc/thingino.json set netwatch.enabled false
/etc/init.d/S52netwatch restart
```

Diagnosis
---------

The watchdog logs through `logger` with the `netwatch` tag, so its decisions
are visible in the system log:

```
logread | grep netwatch
```

A trip is recorded as `ping <target> failed (<n>/<fail_count>)` followed by
`no connectivity to <target>, rebooting`. The same messages also go to the
console.

The reboot uses the hardware-watchdog fallback: the service kills the watchdog
daemon so nothing feeds `/dev/watchdog`, then forces the reset with `reboot -f`
(falling back to a sysrq trigger). Because it does not perform a normal
shutdown, `fw_setenv watchdog_enabled false` will not prevent it. To stop a
camera that is already reboot-looping, set `netwatch.enabled` to `false` (Web
UI or `jct`) and reboot once.
