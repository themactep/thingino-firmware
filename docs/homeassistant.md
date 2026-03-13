# Home Assistant Integration

Thingino includes a native Home Assistant integration via MQTT auto-discovery.
When enabled, the camera registers itself as a HA device automatically — no
manual YAML configuration required.

## Prerequisites

- Home Assistant with the **MQTT integration** enabled (Settings → Devices &
  Services → Add Integration → MQTT)
- An MQTT broker reachable by both the camera and HA (e.g. Mosquitto add-on)
- The MQTT broker address configured under **Services → MQTT Subscriptions**
  on the camera Web UI (`mqtt_sub.host`)

## Quick start

Enable the integration from the camera shell:

```sh
jct /etc/thingino.json set ha.enabled true
/etc/init.d/S93ha restart
```

Or set `ha.enabled = true` via the Web UI configuration editor.

Within a few seconds HA will show a new device containing all enabled entities.

## Configuration keys (`ha.*` in `/etc/thingino.json`)

| Key | Default | Description |
|-----|---------|-------------|
| `enabled` | `false` | Start the HA daemon on boot |
| `discovery_prefix` | `"homeassistant"` | MQTT discovery prefix (match HA setting) |
| `state_interval` | `60` | Seconds between state polls |
| `discovery_interval` | `3600` | Re-publish discovery every N seconds (survives HA restarts) |
| `device_name` | `""` | Override device name (defaults to hostname) |
| `device_model` | `""` | Override device model string |
| `enable_motion` | `true` | Binary sensor: motion detected |
| `enable_motion_guard` | `true` | Switch: enable/disable motion detection |
| `enable_ircut` | `true` | Switch: IR cut filter |
| `enable_daynight` | `true` | Select: day / night mode |
| `enable_privacy` | `true` | Switch: privacy screen |
| `enable_color` | `true` | Switch: color vs monochrome |
| `enable_ir850` | `true` | Switch: 850 nm IR LED |
| `enable_ir940` | `true` | Switch: 940 nm IR LED |
| `enable_white_light` | `true` | Switch: white light |
| `enable_gain` | `false` | Sensor: ISP gain (proxy for lux) |
| `enable_rssi` | `true` | Sensor: WiFi signal strength (dBm) |
| `enable_snapshot` | `true` | Button: take snapshot |
| `enable_reboot` | `false` | Button: reboot camera |
| `enable_ota` | `true` | Update: OTA firmware update |
| `enable_ptz` | `false` | Buttons: PTZ up/down/left/right/home |

Disable individual entities you don't want:

```sh
jct /etc/thingino.json set ha.enable_reboot false
jct /etc/thingino.json set ha.enable_ptz true   # enable PTZ buttons
```

## MQTT topic layout

All topics are scoped to `cameras/<mac_address>/` where `<mac_address>` is the
camera's primary interface MAC without separators (e.g. `0244dd22592e`).

| Entity | State topic | Command topic |
|--------|-------------|---------------|
| Motion detected | `cameras/<id>/motion/state` | — |
| Motion Guard | `cameras/<id>/motion_guard/state` | `cameras/<id>/motion_guard/set` |
| IR Cut Filter | `cameras/<id>/ircut/state` | `cameras/<id>/ircut/set` |
| Day/Night Mode | `cameras/<id>/daynight/state` | `cameras/<id>/daynight/set` |
| Privacy Screen | `cameras/<id>/privacy/state` | `cameras/<id>/privacy/set` |
| Color Mode | `cameras/<id>/color/state` | `cameras/<id>/color/set` |
| IR LED 850 nm | `cameras/<id>/ir850/state` | `cameras/<id>/ir850/set` |
| IR LED 940 nm | `cameras/<id>/ir940/state` | `cameras/<id>/ir940/set` |
| White Light | `cameras/<id>/white/state` | `cameras/<id>/white/set` |
| Gain | `cameras/<id>/gain/state` | — |
| WiFi RSSI | `cameras/<id>/rssi/state` | — |
| Snapshot | — | `cameras/<id>/snapshot/set` |
| Reboot | — | `cameras/<id>/reboot/set` |
| Firmware installed | `cameras/<id>/firmware/state` | — |
| Firmware latest | `cameras/<id>/firmware/latest` | — |
| Firmware install | — | `cameras/<id>/firmware/set` (payload: `install`) |
| PTZ | — | `cameras/<id>/ptz/{up,down,left,right,home}/set` |
| Availability | `cameras/<id>/status` | — (`online` / `offline`) |

## Accepted command payloads

- **Switches**: `on` / `off` (also accepts `ON`/`OFF`, `1`/`0`)
- **Day/Night select**: `day` / `night` / `toggle`
- **Snapshot / reboot / PTZ buttons**: `1`
- **Firmware install**: `install`

## Gain sensor

The gain sensor (`enable_gain`) reads the ISP total gain from
`/proc/jz/isp/isp-m0` when available. It is disabled by default because the
proc interface is SoC-specific. Enable it after confirming the value makes
sense on your hardware:

```sh
jct /etc/thingino.json set ha.enable_gain true
/etc/init.d/S93ha restart
```

## Troubleshooting

Run discovery manually and watch the output:

```sh
ha-discovery
```

Watch all HA-related MQTT traffic:

```sh
mosquitto_sub -h <broker> -v -t 'homeassistant/+/thingino_#' -t 'cameras/<id>/#'
```

Check the daemon log:

```sh
logread | grep ha-
```

Force a state refresh without restarting the daemon:

```sh
ha-state
```
