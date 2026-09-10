Wyze Floodlight V1
=================

The Wyze Floodlight V1 camera has a separate floodlight controller
attached over an internal USB serial link. Thingino provides
`floodlight_ctl` to turn the lamp on and off, set its brightness, and
optionally light it up after a night-time motion event.

The controller is available only on Wyze Floodlight V1 builds. Its Web UI
page is **Settings → Floodlight**.

Hardware
--------

- The floodlight controller is attached through an internal CH341 USB
  serial adapter, normally exposed as `/dev/ttyUSB0` or `/dev/ttyUSB1`.
- `floodlight_ctl` automatically selects the available serial device.
- The board accepts a proprietary framed serial command; no GPIO or extra
  wiring is required.

### Hardware limitations

**Reported state.** The controller does not expose a state-query command,
so Thingino records the last requested on/off state and brightness under
`/var/run/floodlight.status` and `/var/run/floodlight.brightness`. The
Web UI and Home Assistant display those requested values, not a reading
from the lamp.

**Physical PIR sensor.** The fixture's built-in PIR sensor keeps operating
independently of Thingino. `floodlight_ctl` controls only the lamp through
the camera's floodlight controller; it cannot disable or adjust the PIR.
To rely solely on Thingino's motion detection, the PIR sensor must be
physically disconnected.

The `floodlight_ctl` command
----------------------------

Installed at `/usr/sbin/floodlight_ctl`.

```
floodlight_ctl {on [1-100]|off|motion}
```

| Command      | Description                                                |
|--------------|------------------------------------------------------------|
| `on`         | Turn the lamp on at the configured brightness              |
| `on <1-100>` | Turn the lamp on at the given brightness and remember it   |
| `off`        | Turn the lamp off                                          |
| `motion`     | Process a night-time motion event using the saved settings |

`on` with no argument uses the configured brightness, defaulting to 100%
when none has been set. `on <1-100>` updates the configured brightness, so
the next bare `on` (from the Web UI, Home Assistant, or motion) reuses it.

Configuration
-------------

All floodlight settings live under a single `"floodlight"` key in
`/etc/thingino.json`:

```json
{
  "floodlight": {
    "brightness": 100,
    "motion": {
      "enabled": false,
      "duration": 30
    }
  }
}
```

| Key                    | Range  | Default | Description                             |
|------------------------|--------|---------|-----------------------------------------|
| `brightness`           | 1–100  | `100`   | Brightness percentage used on turn-on   |
| `motion.enabled`       | bool   | `false` | Enable night-time motion activation     |
| `motion.duration`      | 1–3600 | `30`    | Seconds the lamp stays on after motion  |

Missing keys fall back to their defaults; the Web UI writes them on first
save.

Web UI
------

Open **Settings → Floodlight** on a Floodlight V1 camera. The page
provides:

- Lamp on/off switch
- Brightness slider (1–100%)
- Motion activation switch
- Motion on-time slider (1–3600 seconds)

The page reads and writes the `floodlight` config in `thingino.json`
through the authenticated `/x/json-config-floodlight.cgi` endpoint.

### CGI API

| Action           | Method | Description                                    |
|------------------|--------|------------------------------------------------|
| (none / GET)     | GET    | Return current state and configuration          |
| `on`             | POST   | Turn the lamp on at the configured brightness   |
| `off`            | POST   | Turn the lamp off                               |
| `set-brightness` | POST   | Save `brightness` and apply it if the lamp is on |
| `set-motion`     | POST   | Save `enabled` and `duration` motion settings   |

Motion activation
-----------------

Motion activation turns the lamp on for `motion.duration` seconds after a
camera motion event, but only at night.

The streamer motion script (`/usr/sbin/motion`; Prudynt-t installs it
directly, Raptor symlinks `raptor-motion` to it) invokes the hook on every
motion start:

```sh
[ -x /usr/sbin/floodlight_ctl ] && floodlight_ctl motion &
```

`floodlight_ctl motion` then:

1. Exits immediately when `motion.enabled` is not `true`.
2. Reads `/run/thingino/daynight_mode` and exits unless it contains
   `night`.
3. Turns the lamp on at the configured brightness.
4. Sleeps for `motion.duration` seconds, then turns the lamp off.
5. Uses `/var/run/floodlight-motion.lock` so overlapping motion events do
   not start overlapping timers.

The hook is a no-op on cameras without `floodlight_ctl` installed.

Enable motion activation from the shell:

```sh
jct /etc/thingino.json set floodlight.motion.enabled true
jct /etc/thingino.json set floodlight.motion.duration 30
```

Disable only the lamp response to motion (camera motion detection and OSD
continue normally):

```sh
jct /etc/thingino.json set floodlight.motion.enabled false
```

Home Assistant
--------------

Floodlight control is available as a Home Assistant **Light** entity with
on/off and 1–100% brightness. Enable it with:

```sh
jct /etc/thingino.json set ha.enable_floodlight true
/etc/init.d/S93ha restart
```

The entity is auto-enabled on Floodlight V1 builds. See
[Home Assistant Integration](services/homeassistant.md) for the MQTT topic
layout and command payloads.

Build-time configuration
------------------------

In `make menuconfig`:

```
Target packages  --->
  Wyze Accessories  --->
    [*] Wyze Accessories
    [*] Wyze Floodlight
```

The floodlight controller, its Web UI plugin, and the motion hook are
installed automatically when the option is enabled.

Troubleshooting
---------------

| Symptom                                              | Likely cause / fix                                                                                                                                       |
|------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Could not find a floodlight serial device`          | The camera is not a Floodlight V1 build, or the internal USB controller is unavailable. Check for `/dev/ttyUSB0` or `/dev/ttyUSB1`.                       |
| Motion does not turn on the lamp                     | Confirm it is night and that `floodlight.motion.enabled` is `true` in Settings → Floodlight or `/etc/thingino.json`.                                     |
| Lamp turns on but too bright or dim                  | Set the desired brightness in Settings → Floodlight or run `floodlight_ctl on <1-100>`. Motion and bare `on` reuse this value.                            |
| Home Assistant shows a different state than the lamp | The board cannot report physical state; the shown value is the last command accepted by `floodlight_ctl`.                                                 |
