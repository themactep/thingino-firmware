Wyze Floodlight V1 Control
==========================

The Wyze Floodlight V1 contains a separate floodlight controller connected to
the camera over an internal USB serial interface. Thingino provides
`floodlight_ctl` to turn the lamp on and off, set brightness, and run an
optional night-time motion timer.

The controller is available only on Wyze Floodlight V1 builds. Its Web UI page
is **Settings → Floodlight** when the floodlight controller and page are
installed.

Hardware
--------

- The Floodlight V1 accessory board is attached through an internal CH341 USB
  serial adapter, normally exposed as `/dev/ttyUSB0` or `/dev/ttyUSB1`.
- `floodlight_ctl` automatically selects the available serial device.
- The board accepts a proprietary framed serial command. No external GPIO or
  additional wiring is required.

### Hardware limitations

**Reported state.** The accessory board does not report the physical lamp
state. Thingino records the last requested on/off state and brightness under
`/var/run/floodlight.status` and `/var/run/floodlight.brightness`. Home
Assistant and the Web UI display those requested values.

**Physical PIR sensor** 
The Floodlight control script does not control or disable the fixture’s built-in 
PIR sensor. It only controls the lamp through the camera’s floodlight controller.
The physical PIR sensor will trigger the floodlight independent of the software
unless disconnected.

The floodlight will still be triggered by the built-in PIR sensor and sensitivity
can not be controlled.  Advanced users interested in relying just on Thingino's 
motion detection can physically disconnect the PIR sensor.

The `floodlight_ctl` command
----------------------------

Installed at `/usr/sbin/floodlight_ctl`.

```
floodlight_ctl {on <1-100>|off|motion}
```

### Commands

| Command      | Description                                              |
|--------------|----------------------------------------------------------|
| `on <1-100>` | Turn the lamp on at the specified brightness percentage  |
| `off`        | Turn the lamp off                                        |
| `motion`     | Process one motion event using the saved motion settings |

### Manual control

Turn the light on at 75% brightness:

```
floodlight_ctl on 75
```

Turn it off:

```
floodlight_ctl off
```

Brightness must be an integer from **1** through **100**. The last successful
brightness selection is reused when motion activation turns the lamp on.

Web UI control
--------------

Open **Settings → Floodlight** on a Floodlight V1 camera.

The page provides:

- Current requested on/off state
- Brightness slider (1–100%)
- Turn on, turn off, and set-brightness controls
- Motion activation switch
- Motion on-time setting (1–3600 seconds)

The page saves the motion settings in:

```
/etc/floodlight-motion.conf
```

Its default contents disable motion activation and use a 30-second timer:

```
MOTION_ENABLED=0
MOTION_DURATION=30
```

Motion activation
-----------------

The Floodlight V1 can turn on after a camera motion event. The main motion
handler starts this non-blocking command:

```
/usr/sbin/floodlight_ctl motion &
```

The `motion` command:

1. Exits immediately when `MOTION_ENABLED=0`.
2. Checks `/run/thingino/daynight_mode` and only runs when it contains
   `night`.
3. Uses the last selected brightness, or 100% when no valid value is stored.
4. Turns on the lamp for `MOTION_DURATION` seconds, then turns it off.
5. Uses `/var/run/floodlight-motion.lock` to prevent overlapping motion
   timers.

Enable motion activation from the shell:

```
printf 'MOTION_ENABLED=1\nMOTION_DURATION=30\n' > /etc/floodlight-motion.conf
```

Disable only the lamp response to motion (camera motion detection and OSD
continue normally):

```
printf 'MOTION_ENABLED=0\nMOTION_DURATION=30\n' > /etc/floodlight-motion.conf
```

Home Assistant
--------------

Enable the Floodlight entity in the Home Assistant configuration:

```
jct /etc/thingino.json set ha.enable_floodlight true
/etc/init.d/S93ha restart
```

Home Assistant discovers a **Light** entity with on/off and brightness
controls. MQTT topics use the camera hostname as `<id>`:

| Function              | State topic                                | Command topic                            |
|-----------------------|--------------------------------------------|------------------------------------------|
| Floodlight on/off     | `cameras/<id>/floodlight/state`            | `cameras/<id>/floodlight/set`            |
| Floodlight brightness | `cameras/<id>/floodlight_brightness/state` | `cameras/<id>/floodlight_brightness/set` |

Send `ON` or `OFF` to the on/off topic. Send an integer from `1` through
`100` to the brightness command topic.

Troubleshooting
---------------

| Symptom                                              | Likely cause / fix                                                                                                                                           |
|------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Could not find a floodlight serial device`          | The camera is not a Floodlight V1 build, or the internal USB controller is unavailable. Check for `/dev/ttyUSB0` or `/dev/ttyUSB1`.                          |
| Motion does not turn on the lamp                     | Enable motion activation in Settings → Floodlight, confirm it is night, and verify that the motion handler calls `floodlight_ctl motion &`.                  |
| Lamp turns on but too bright or dim                  | Set the desired brightness in Settings → Floodlight or run `floodlight_ctl on <1-100>`. Motion uses this last brightness.                                    |
| Home Assistant shows a different state than the lamp | The board cannot report physical state; the shown value is the last command accepted by `floodlight_ctl`.                                                    |
| Motion timer starts more than once                   | The controller prevents concurrent timers with `/var/run/floodlight-motion.lock`. Remove that directory only after confirming no timer is currently running. |
