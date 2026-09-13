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
| `state_interval` | `15` | Seconds between state polls |
| `discovery_interval` | `3600` | Re-publish discovery every N seconds (survives HA restarts) |
| `ota_check_interval` | `21600` | Seconds between GitHub firmware release checks (Firmware update entity) |
| `device_name` | `""` | Override device name (defaults to hostname) |
| `device_model` | `""` | Override device model string |
| `mqtt.use_ssl` | `false` | Connect to the MQTT broker with TLS using the system CA bundle |
| `mqtt.tls_skip_verify` | `false` | Skip broker certificate verification when TLS is enabled. Insecure; use only for self-signed or otherwise untrusted broker certificates |
| `enable_motion` | `true` | Binary sensor: motion detected |
| `enable_doorbell` | `false` | Binary sensor: doorbell button pressed |
| `enable_motion_guard` | `true` | Switch: enable/disable motion detection |
| `enable_ircut` | `true` | Switch: IR cut filter |
| `enable_daynight` | `true` | Select: day / night mode |
| `enable_privacy` | `true` | Switch: privacy screen |
| `enable_color` | `true` | Switch: color vs monochrome |
| `enable_floodlight` | `false` | Light: Wyze Floodlight v1 with on/off and 1–100% brightness |
| `enable_ir850` | `true` | Switch: 850 nm IR LED |
| `enable_ir940` | `true` | Switch: 940 nm IR LED |
| `enable_white_light` | `true` | Switch: white light |
| `enable_firmware_version` | `true` | Sensor: firmware version (e.g. "ciao+9a88c72") |
| `enable_firmware_timestamp` | `true` | Sensor: firmware build timestamp (e.g. "2026-07-24 03:04:32 UTC") |
| `enable_gain` | `false` | Sensor: ISP gain (proxy for lux) |
| `enable_rssi` | `true` | Sensor: WiFi signal strength (dBm) |
| `enable_snapshot` | `true` | Button: take snapshot |
| `enable_reboot` | `false` | Button: reboot camera |
| `enable_ota` | `true` | Update: OTA firmware update |
| `enable_ptz` | `false` | Buttons: PTZ up/down/left/right/home |

The firmware update entity (`enable_ota`) uses a cached GitHub release lookup:
`firmware/state` is still published every `state_interval`, but
`firmware/latest` is refreshed on `ota_check_interval` cadence with per-camera
jitter to avoid synchronized bursts across multiple cameras.

Disable individual entities you don't want:

```sh
jct /etc/thingino.json set ha.enable_reboot false
jct /etc/thingino.json set ha.enable_ptz true   # enable PTZ buttons
```

## Wyze Floodlight v1

Floodlight control is available only on Wyze Floodlight v1 builds that include
`/usr/sbin/floodlight_ctl`. Enable the Home Assistant light entity with:

```sh
jct /etc/thingino.json set ha.enable_floodlight true
/etc/init.d/S93ha restart
```

Home Assistant discovers it as a **Light** entity with on/off and 1–100%
brightness control. The reported state and brightness are the last commands
sent to the controller; the Floodlight v1 accessory board does not report the
physical lamp state.

## MQTT topic layout

All topics are scoped to `cameras/<id>/` where `<id>` is the camera's hostname
(e.g. `ing-wyze-cam3-2937`). The default hostname includes the SoC serial suffix
for uniqueness; override the hostname to retain HA configuration across hardware
swaps.

| Entity | State topic | Command topic |
|--------|-------------|---------------|
| Motion detected | `cameras/<id>/motion/state` | — |
| Doorbell | `cameras/<id>/doorbell/state` | — |
| Motion Guard | `cameras/<id>/motion_guard/state` | `cameras/<id>/motion_guard/set` |
| IR Cut Filter | `cameras/<id>/ircut/state` | `cameras/<id>/ircut/set` |
| Day/Night Mode | `cameras/<id>/daynight/state` | `cameras/<id>/daynight/set` |
| Privacy Screen | `cameras/<id>/privacy/state` | `cameras/<id>/privacy/set` |
| Color Mode | `cameras/<id>/color/state` | `cameras/<id>/color/set` |
| IR LED 850 nm | `cameras/<id>/ir850/state` | `cameras/<id>/ir850/set` |
| IR LED 940 nm | `cameras/<id>/ir940/state` | `cameras/<id>/ir940/set` |
| White Light | `cameras/<id>/white/state` | `cameras/<id>/white/set` |
| Firmware version | `cameras/<id>/firmware_version/state` | — |
| Firmware build | `cameras/<id>/firmware_timestamp/state` | — |
| Floodlight | `cameras/<id>/floodlight/state` | (`on` / `off`) |
| Floodlight Brightness | `cameras/<id>/floodlight_brightness/set` | (0-100) |
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
- **Floodlight**: `on` / `off`; send an integer from `1` to `100` to its
  brightness command topic
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
