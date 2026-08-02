# Thingino Camera Card for Home Assistant

Custom Lovelace card that pairs a live camera feed with Thingino's
switch/select/button controls and sensor readouts — all in one compact tile.

![screenshot](screenshot.png)

## What it shows

| Area | What |
|------|------|
| **Top** | Camera feed (poster image, click to open full viewer) |
| **Middle** | Row of toggle/press buttons for camera controls |
| **Bottom** | Sensor readout strip (Live View state, Motion, WiFi dBm) |

## Supported Thingino entities

- **Switches**: Color Mode, IR Cut Filter, IR LED 850nm, IR LED 940nm,
  Motion Guard, Privacy Screen, White Light
- **Select**: Day/Night Mode
- **Button**: Snapshot
- **Sensors**: Motion (binary), WiFi Signal (dBm), Gain (dB), Live View, Firmware Version, Firmware Build
- All other entities work too — just list them in the YAML.

## Installation

```bash
# 1. Copy the card into Home Assistant's www directory
cp thingino-camera-card.js /config/www/

# 2. Restart Home Assistant, or reload Lovelace resources, then add:
#    Settings → Dashboards → ⋮ → Resources → Add Resource
#    URL:  /local/thingino-camera-card.js
#    Type: JavaScript Module
```

## Card config (YAML)

```yaml
type: custom:thingino-camera-card
camera_entity: camera.my_camera_stream
title: Front Porch
show_title: true
show_sensors: true
compact: false

controls:
  - entity: switch.thingino_0244dd22592e_color
    name: Color
  - entity: select.thingino_0244dd22592e_daynight
    name: Day/Night
  - entity: switch.thingino_0244dd22592e_ircut
    name: IR Cut
  - entity: switch.thingino_0244dd22592e_ir850
    name: IR LED
  - entity: switch.thingino_0244dd22592e_motion_guard
    name: Guard
  - entity: switch.thingino_0244dd22592e_privacy
    name: Privacy
  - entity: button.thingino_0244dd22592e_snapshot
    name: Snap
  - entity: switch.thingino_0244dd22592e_white
    name: Light

sensors:
  - entity: camera.thingino_0244dd22592e_live_view
    name: Live View
  - entity: binary_sensor.thingino_0244dd22592e_motion
    name: Motion
  - entity: sensor.thingino_0244dd22592e_rssi
    name: WiFi
  - entity: sensor.thingino_0244dd22592e_firmware_version
    name: Firmware
  - entity: sensor.thingino_0244dd22592e_firmware_timestamp
    name: Built
```

> **Tip**: Replace `0244dd22592e` with your camera's MAC address (no colons,
> lowercase). Run `ha-discovery` on the camera shell to find your ID.

## Choosing a camera_entity

The `camera_entity` can be **any Home Assistant camera entity**. Here are the
best options for Thingino cameras:

### Option 1 — WebRTC Camera (recommended, low latency)

Install the [WebRTC Camera](https://github.com/AlexxIT/WebRTC) custom
integration (HACS), then create a generic camera pointing at go2rtc:

```yaml
# configuration.yaml
camera:
  - platform: generic
    name: Thingino Stream
    still_image_url: http://192.168.1.42/cgi-bin/snapshot.cgi
    stream_source: http://192.168.1.42:1984/api/stream?src=thingino
```

Then use `camera.thingino_stream` as your `camera_entity`.

### Option 2 — MJPEG sub-stream (built-in, no HACS)

```yaml
camera:
  - platform: mjpeg
    name: Thingino MJPEG
    mjpeg_url: http://192.168.1.42:8080/video/mjpeg
    still_image_url: http://192.168.1.42/cgi-bin/snapshot.cgi
```

### Option 3 — MQTT camera (slow, periodic snapshots only)

Use `camera.thingino_<id>_live_view` directly. This publishes base64 JPEG frames
over MQTT every `camera_interval` seconds (default 60). Not suitable for live
motion but works without opening extra ports.

## Configuration reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `camera_entity` | string | **required** | HA camera entity for the live feed |
| `title` | string | `""` | Title shown above controls |
| `controls` | list | `[]` | Control buttons (see below) |
| `sensors` | list | `[]` | Sensor readouts (see below) |
| `show_title` | boolean | `true` | Show/hide the title bar |
| `show_sensors` | boolean | `true` | Show/hide the sensor strip |
| `compact` | boolean | `false` | Reduce card height hint |

Each **control** entry:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `entity` | string | yes | Entity ID (switch, select, button) |
| `name` | string | no | Button label (defaults to entity id) |
| `icon` | string | no | MDI icon override |

Each **sensor** entry:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `entity` | string | yes | Entity ID (sensor, binary_sensor, camera) |
| `name` | string | no | Display name (defaults to entity id) |
| `icon` | string | no | MDI icon override |

## How controls work

- **Switches** — toggle on/off (calls `turn_on`/`turn_off`)
- **Select (Day/Night)** — toggles between `day` and `night` each press
- **Buttons** (snapshot, reboot) — fires a `press` action

All commands go through MQTT to the camera and respond within a second.

## License

MIT
