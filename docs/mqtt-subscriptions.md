MQTT Subscriptions
==================

The MQTT Subscriptions feature allows a Thingino camera to listen on one or
more MQTT topics and execute a shell command when a message arrives.  This
turns any MQTT-capable home-automation system (Home Assistant, Node-RED,
openHAB, ioBroker, etc.) into a remote control for the camera.

Configuration is managed through the Web UI at
**Services → MQTT Subscriptions** or directly in `/etc/thingino.json` under
the `mqtt_sub` key.


## How it works

A persistent daemon (`mqtt-sub-dispatcher`) is started at boot by
`/etc/init.d/S91mqttsub`.  It reads the broker connection settings and the
list of subscriptions from `/etc/thingino.json`, then launches
`mosquitto_sub` to subscribe to all enabled topics in a single connection.

For every incoming message the daemon matches the arriving topic against each
subscription (MQTT wildcards `+` and `#` are supported) and runs the
configured shell command with two environment variables set:

| Variable        | Value                                          |
|-----------------|------------------------------------------------|
| `$MQTT_TOPIC`   | The topic on which the message was received.   |
| `$MQTT_PAYLOAD` | The raw message payload (UTF-8 string).        |


## Topic shorthands

The following placeholders are expanded at daemon startup and can be used
anywhere in a topic string:

| Shorthand     | Resolves to                                          |
|---------------|------------------------------------------------------|
| `%hostname`   | Camera hostname (e.g. `ing-wyze-cam3-592e`)          |
| `%ip`         | Camera IP address (e.g. `192.168.1.42`)              |
| `%id`         | MAC address without separators (e.g. `0244dd22592e`) |

Example: `cameras/%id/cmd` subscribes to
`cameras/0244dd22592e/cmd` at runtime.


## QoS levels

MQTT defines three Quality of Service levels that control the delivery
guarantee between the broker and the subscriber.

| Level | Name              | Guarantee                                                |
|-------|-------------------|----------------------------------------------------------|
| `0`   | At most once      | Fire-and-forget. Message may be lost if the network drops or the camera is offline. No acknowledgement. |
| `1`   | At least once     | Broker retries until the camera acknowledges receipt. The message may arrive **more than once** — your action must tolerate duplicate execution. |
| `2`   | Exactly once      | Four-way handshake guarantees the message is delivered exactly one time. Highest overhead; rarely needed for camera control. |

Note: the QoS value in a subscription is the *maximum* QoS the camera
requests from the broker.  The broker delivers at the lesser of the
publisher's QoS and this value.

### Choosing the right level

**QoS 0** is appropriate for:
- Frequent, idempotent commands where occasional loss is acceptable
  (PTZ nudges, LED toggles, audio chimes)
- High-frequency telemetry topics that self-correct on the next message

**QoS 1** is appropriate for:
- State-changing commands where missing a message matters
  (motion guard on/off, privacy screen, day/night mode, reboot)
- Actions that are naturally idempotent — running them twice has the same
  effect as running them once (e.g. `privacy on` when already on)

**QoS 2** is rarely needed for camera control.  Prefer QoS 1 with
idempotent actions instead of paying the QoS 2 handshake cost on
resource-constrained hardware.

> **Important — QoS 1 duplicate delivery:** if the broker re-delivers a
> retained or in-flight message after the camera reconnects, the action
> will run again.  For commands like `reboot` this is usually harmless
> (the camera is already up), but for commands like `record` it could
> produce an extra clip.  Guard against this where necessary:
>
> ```sh
> # Only reboot if uptime > 60 s (avoids boot-loop from retained message)
> [ "$(awk '{print int($1)}' /proc/uptime)" -gt 60 ] && reboot
> ```


## Configuration reference

```json
"mqtt_sub": {
  "enabled": true,
  "host": "192.168.1.10",
  "port": 1883,
  "username": "myuser",
  "password": "secret",
  "use_ssl": false,
  "subscriptions": [
    {
      "topic": "cameras/%id/reboot",
      "qos": 1,
      "enabled": true,
      "action": "reboot"
    }
  ]
}
```

| Field           | Type    | Description                                        |
|-----------------|---------|----------------------------------------------------|
| `enabled`       | bool    | Start the service on boot.                         |
| `host`          | string  | MQTT broker hostname or IP.                        |
| `port`          | integer | Broker port. Default: `1883`.                      |
| `username`      | string  | Optional broker username.                          |
| `password`      | string  | Optional broker password.                          |
| `use_ssl`       | bool    | Enable TLS using system CA bundle.                 |
| `subscriptions` | array   | List of subscription objects (see below).          |

Each subscription object:

| Field     | Type    | Description                                              |
|-----------|---------|----------------------------------------------------------|
| `topic`   | string  | MQTT topic filter. Wildcards `+` and `#` are supported.  |
| `qos`     | integer | QoS level: `0`, `1`, or `2`.                            |
| `enabled` | bool    | Whether this subscription is active.                     |
| `action`  | string  | Shell command to run on message receipt.                 |

### Thingino hub pairing and control

When a camera is managed by the Thingino hub, the camera should subscribe to
the hub command topic and forward the raw JSON payload to
`telegram-cam-agent` unchanged:

```json
{
  "mqtt_sub": {
    "enabled": true,
    "host": "192.168.88.20",
    "port": 1883,
    "username": "",
    "password": "",
    "use_ssl": false,
    "subscriptions": [
      {
        "topic": "thingino/cam/%id/cmd",
        "qos": 1,
        "enabled": true,
        "action": "telegram-cam-agent \"$MQTT_PAYLOAD\""
      }
    ]
  }
}
```

This is the subscription the hub expects for MQTT-driven camera actions such as
registration refresh, Telegram command routing, and agent bootstrap pairing.

Important: keep the action exactly as shown above, including the inner quotes
around `$MQTT_PAYLOAD`. The payload is JSON, and `telegram-cam-agent` expects
to receive it as a single shell argument.


---

## Sample configurations

Each example below shows the `action` field value to use in the Web UI or
the full subscription JSON for direct config editing.

Where a subscription responds to a payload value (e.g. `1`/`0`, `on`/`off`),
use a conditional in the action.  When no payload check is needed, the action
runs unconditionally for every message.


### PTZ / motor control

Move the camera to a preset position or in a direction.  The `motors` binary
uses `x`/`y` for absolute position (steps from home) or the `g` direction
command.

```json
{
  "topic": "cameras/%id/ptz",
  "qos": 0,
  "enabled": true,
  "action": "case \"$MQTT_PAYLOAD\" in up) motors -d g -x 0 -y -100 ;; down) motors -d g -x 0 -y 100 ;; left) motors -d g -x -100 -y 0 ;; right) motors -d g -x 100 -y 0 ;; home) motors -r ;; esac"
}
```

Tip: split into separate topics for cleaner rules:

```json
{ "topic": "cameras/%id/ptz/up",    "action": "motors -d g -x 0 -y -100" },
{ "topic": "cameras/%id/ptz/down",  "action": "motors -d g -x 0 -y 100"  },
{ "topic": "cameras/%id/ptz/left",  "action": "motors -d g -x -100 -y 0" },
{ "topic": "cameras/%id/ptz/right", "action": "motors -d g -x 100 -y 0"  },
{ "topic": "cameras/%id/ptz/home",  "action": "motors -r"                 },
{ "topic": "cameras/%id/ptz/stop",  "action": "motors -d s"               }
```


### Snapshot trigger

Take a JPEG snapshot and save it to a timestamped file.

```json
{
  "topic": "cameras/%id/snapshot",
  "qos": 1,
  "enabled": true,
  "action": "prudyntctl snapshot -c 0 > /tmp/snap_$(date +%Y%m%d_%H%M%S).jpg"
}
```

Send the snapshot to an FTP server or over MQTT immediately after capture:

```json
{
  "topic": "cameras/%id/snapshot",
  "action": "FILE=$(mktemp /tmp/snap.XXXXXX.jpg) && prudyntctl snapshot -c 0 > \"$FILE\" && send2ftp -f \"$FILE\"; rm -f \"$FILE\""
}
```


### Video snippet trigger

Record a 10-second video clip by signalling the Prudynt recorder.

```json
{
  "topic": "cameras/%id/record",
  "qos": 1,
  "enabled": true,
  "action": "FILE=/tmp/clip_$(date +%Y%m%d_%H%M%S).mp4 && echo \"START $FILE 10 0\" > /run/prudynt/mp4ctl"
}
```

The payload can carry the clip duration in seconds:

```json
{
  "topic": "cameras/%id/record",
  "action": "DUR=${MQTT_PAYLOAD:-10}; FILE=/tmp/clip_$(date +%Y%m%d_%H%M%S).mp4; echo \"START $FILE $DUR 0\" > /run/prudynt/mp4ctl"
}
```


### Motion Guard on/off

Enable or disable the Prudynt motion detection engine.

```json
{
  "topic": "cameras/%id/motion",
  "qos": 1,
  "enabled": true,
  "action": "case \"$MQTT_PAYLOAD\" in 1|on|true)  motion enable  ;; 0|off|false) motion disable ;; esac"
}
```

Or with dedicated topics:

```json
{ "topic": "cameras/%id/motion/enable",  "action": "motion enable"  },
{ "topic": "cameras/%id/motion/disable", "action": "motion disable" }
```


### Enable/disable Motion Guard notification services

Each send2 service (email, ntfy, Telegram, webhook, …) stores its
configuration under `/etc/send2.json`.  Set the `enabled` field to
`true` or `false` with `jct`.

```json
{
  "topic": "cameras/%id/notify/email",
  "qos": 1,
  "enabled": true,
  "action": "case \"$MQTT_PAYLOAD\" in 1|on|true)  jct /etc/send2.json set email.enabled true  ;; 0|off|false) jct /etc/send2.json set email.enabled false ;; esac"
}
```

Replace `email` with any service key: `ntfy`, `telegram`, `ftp`, `webhook`,
`mqtt`, `storage`, `gphotos`, `discord`.

One-liner to silence all notifications at once:

```json
{
  "topic": "cameras/%id/notify/silence",
  "action": "for svc in email ntfy telegram ftp webhook mqtt storage; do jct /etc/send2.json set ${svc}.enabled false; done"
}
```


### IR cut filter control

The IR cut filter switches the camera between colour (day) and monochrome
(night / IR) modes.  The `ircut` utility accepts `on`, `off`, and `toggle`.

```json
{
  "topic": "cameras/%id/ircut",
  "qos": 0,
  "enabled": true,
  "action": "ircut \"$MQTT_PAYLOAD\""
}
```

Accepted payload values: `on`, `off`, `toggle`.


### IR LED control

Control the infrared illuminators (850 nm and/or 940 nm) independently.
The `light` utility accepts `on`, `off`, and `toggle` for each type.

```json
{ "topic": "cameras/%id/ir850",  "action": "light ir850 \"$MQTT_PAYLOAD\"" },
{ "topic": "cameras/%id/ir940",  "action": "light ir940 \"$MQTT_PAYLOAD\"" },
{ "topic": "cameras/%id/ir",     "action": "light ir \"$MQTT_PAYLOAD\""    }
```

Accepted payload values: `on`, `off`, `toggle`.


### White light (flood LED) control

```json
{
  "topic": "cameras/%id/whitelight",
  "qos": 0,
  "enabled": true,
  "action": "light white \"$MQTT_PAYLOAD\""
}
```

Accepted payload values: `on`, `off`, `toggle`.


### Day/Night mode control

Force the day/night switching logic to a specific state or toggle it.

```json
{
  "topic": "cameras/%id/daynight",
  "qos": 1,
  "enabled": true,
  "action": "daynight \"$MQTT_PAYLOAD\""
}
```

Accepted payload values: `day`, `night`, `toggle`.


### Camera exposure control

Adjust image parameters at runtime by sending a JSON fragment to
`prudyntctl`.  The exact keys match the `image` section of
`/etc/prudynt.json`.

Force a fixed shutter speed (anti-flicker):

```json
{
  "topic": "cameras/%id/exposure",
  "action": "printf '{\"image\":{\"anti_flicker\":%s}}' \"$MQTT_PAYLOAD\" | prudyntctl json -"
}
```

Common image keys accepted by prudyntctl:

| Key             | Values                          |
|-----------------|---------------------------------|
| `anti_flicker`  | `0` = auto, `1` = 50 Hz, `2` = 60 Hz |
| `brightness`    | 0 – 255                        |
| `contrast`      | 0 – 255                        |
| `saturation`    | 0 – 255                        |
| `sharpness`     | 0 – 255                        |


### Streamer restart

Restart the Prudynt video streamer (useful after configuration changes).

```json
{
  "topic": "cameras/%id/streamer/restart",
  "qos": 1,
  "enabled": true,
  "action": "/etc/init.d/S31prudynt restart"
}
```


### Remote camera speech / audio playback

Play any audio file or URL through the camera speaker using the `play`
utility.  Supported formats: PCM raw, WAV, AAC, Opus, MP3, FLAC.

Play a built-in chime:

```json
{
  "topic": "cameras/%id/play/chime",
  "qos": 0,
  "enabled": true,
  "action": "play /usr/share/sounds/chime_1.opus"
}
```

Play a file path or URL supplied in the payload:

```json
{
  "topic": "cameras/%id/play",
  "action": "play \"$MQTT_PAYLOAD\""
}
```

Play an Opus file from an HTTP server with volume control:

```json
{
  "topic": "cameras/%id/announce",
  "action": "play -v 80 -f opus \"$MQTT_PAYLOAD\""
}
```

Built-in sound files in `/usr/share/sounds/`:

```
chime_1.opus
chime_2.opus
chime_3.opus
motiondetectionactivated.opus
motiondetectiondisactivated.opus
thingino.opus
videorecordingstarted.opus
videorecordingstopped.opus
wificonnected.opus
```

Stop currently playing audio:

```json
{
  "topic": "cameras/%id/play/stop",
  "action": "play stop"
}
```


### Privacy screen enable/disable

The privacy screen blacks out the video feed (useful for scheduled privacy
periods or occupancy-triggered muting).

```json
{
  "topic": "cameras/%id/privacy",
  "qos": 1,
  "enabled": true,
  "action": "privacy \"$MQTT_PAYLOAD\""
}
```

Accepted payload values: `on`, `off`.

Or with dedicated topics:

```json
{ "topic": "cameras/%id/privacy/on",  "action": "privacy on"  },
{ "topic": "cameras/%id/privacy/off", "action": "privacy off" }
```


---

## Combined example: full remote-control profile

The snippet below shows a complete `mqtt_sub` block with a practical set of
subscriptions for a single camera, all scoped under `cameras/%id/`:

```json
"mqtt_sub": {
  "enabled": true,
  "host": "192.168.1.10",
  "port": 1883,
  "username": "camera",
  "password": "secret",
  "use_ssl": false,
  "subscriptions": [
    { "topic": "cameras/%id/reboot",           "qos": 1, "enabled": true,  "action": "reboot" },
    { "topic": "cameras/%id/snapshot",         "qos": 1, "enabled": true,  "action": "prudyntctl snapshot -c 0 > /tmp/snap_$(date +%Y%m%d_%H%M%S).jpg" },
    { "topic": "cameras/%id/record",           "qos": 1, "enabled": true,  "action": "echo \"START /tmp/clip_$(date +%Y%m%d_%H%M%S).mp4 10 0\" > /run/prudynt/mp4ctl" },
    { "topic": "cameras/%id/motion",           "qos": 1, "enabled": true,  "action": "case \"$MQTT_PAYLOAD\" in 1|on) motion enable ;; 0|off) motion disable ;; esac" },
    { "topic": "cameras/%id/ircut",            "qos": 0, "enabled": true,  "action": "ircut \"$MQTT_PAYLOAD\"" },
    { "topic": "cameras/%id/ir850",            "qos": 0, "enabled": true,  "action": "light ir850 \"$MQTT_PAYLOAD\"" },
    { "topic": "cameras/%id/whitelight",       "qos": 0, "enabled": true,  "action": "light white \"$MQTT_PAYLOAD\"" },
    { "topic": "cameras/%id/daynight",         "qos": 1, "enabled": true,  "action": "daynight \"$MQTT_PAYLOAD\"" },
    { "topic": "cameras/%id/privacy",          "qos": 1, "enabled": true,  "action": "privacy \"$MQTT_PAYLOAD\"" },
    { "topic": "cameras/%id/play",             "qos": 0, "enabled": true,  "action": "play \"$MQTT_PAYLOAD\"" },
    { "topic": "cameras/%id/streamer/restart", "qos": 1, "enabled": false, "action": "/etc/init.d/S31prudynt restart" },
    { "topic": "cameras/%id/ptz/up",           "qos": 0, "enabled": false, "action": "motors -d g -x 0 -y -100" },
    { "topic": "cameras/%id/ptz/down",         "qos": 0, "enabled": false, "action": "motors -d g -x 0 -y 100"  },
    { "topic": "cameras/%id/ptz/left",         "qos": 0, "enabled": false, "action": "motors -d g -x -100 -y 0" },
    { "topic": "cameras/%id/ptz/right",        "qos": 0, "enabled": false, "action": "motors -d g -x 100 -y 0"  },
    { "topic": "cameras/%id/ptz/home",         "qos": 1, "enabled": false, "action": "motors -r" }
  ]
}
```

PTZ subscriptions are set to `"enabled": false` by default because not all
cameras have motors — enable only those relevant to your hardware.


## Home Assistant MQTT integration example

```yaml
mqtt:
  button:
    - unique_id: cam_snapshot
      name: "Camera Snapshot"
      command_topic: "cameras/0244dd22592e/snapshot"
      payload_press: "1"

  switch:
    - unique_id: cam_motion
      name: "Camera Motion Guard"
      command_topic: "cameras/0244dd22592e/motion"
      payload_on: "on"
      payload_off: "off"
      state_topic: "cameras/0244dd22592e/motion/state"

    - unique_id: cam_privacy
      name: "Camera Privacy Screen"
      command_topic: "cameras/0244dd22592e/privacy"
      payload_on: "on"
      payload_off: "off"

  select:
    - unique_id: cam_daynight
      name: "Camera Day/Night Mode"
      command_topic: "cameras/0244dd22592e/daynight"
      options: ["day", "night", "toggle"]
```

Replace `0244dd22592e` with your camera's `%id` value (visible in the Web UI
under **Services → MQTT Subscriptions** broker settings or via `hostname -I`
on the camera).
