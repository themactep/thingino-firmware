Wyze Doorbell V1 Chime
======================

The Wyze Doorbell V1 includes a CC1310 sub-GHz radio that communicates
wirelessly with a plug-in chime module. Thingino provides a command-line
tool, `doorbell_ctrl`, to pair the chime and trigger sounds.

Multiple chimes are supported. Paired chimes are stored by name in
`/etc/thingino.json`, grouped for selective playback, and dispatched by
day/night-aware events.

Hardware
--------

- The chime is a small white plug-in module with a single button and a blue
  status LED.
- The doorbell communicates with the chime over a proprietary sub-GHz
  protocol (CC1310 radio, serial interface on `/dev/ttyS0` inside the camera).
- No additional wiring is required — pairing is performed over the air.

The `doorbell_ctrl` command
---------------------------

Built from `package/wyze-accessory/files/doorbell_chime.c` and installed to
`/usr/sbin/doorbell_ctrl`. It talks to the on-board CC1310 radio at 115200
baud, 8N1, over `/dev/ttyS0`.

```
doorbell_ctrl [-d] [-D] <command> [arguments...]
```

### Options

| Flag            | Description                                          |
|-----------------|------------------------------------------------------|
| `-d`, `--debug` | Show TX/RX hex dumps and protocol step-by-step       |
| `-D`, `--delete`| Delete existing chime pairings before pairing        |
| `-h`, `--help`  | Print usage                                          |

### Commands

| Command                                    | Description                                         |
|--------------------------------------------|-----------------------------------------------------|
| `pair [<NAME>] [<MAC>]`                    | Full 8-step pairing sequence (see below)            |
| `discover [<NAME>]`                        | Passive scan for an already-paired chime            |
| `list`                                     | List all stored chimes and groups                   |
| `unpair <NAME\|MAC>`                       | Remove a chime from the config                      |
| `play <NAME\|MAC> <SOUND> [VOL] [REP]`     | Trigger a sound on one chime by name or MAC         |
| `<NAME\|MAC> <SOUND> [VOL] [REP]`          | Same, positional syntax                             |
| `play-all <SOUND> [VOL] [REP]`             | Play on every stored chime                          |
| `play-group <GROUP> <SOUND> [VOL] [REP]`   | Play on all chimes in a named group                 |
| `init`                                     | Initialise the sub-GHz radio (low-level)            |
| `delete`                                   | Remove all stored pairings from the radio (low-level)|
| `start`                                    | Enter pairing mode on the radio (low-level)         |
| `stop`                                     | Exit pairing mode on the radio (low-level)          |
| `challenge <MAC>`                          | Send challenge to a chime (low-level)               |
| `verify <MAC>`                             | Send verify-result to a chime (low-level)           |

The MAC address is written in `XX:XX:XX:XX` colon-separated format. It can
appear anywhere in the arguments — the tool auto-detects strings containing `:`.

Chime names are alphanumeric labels stored in `/etc/thingino.json`. Once a
chime is paired with a name, you can use that name instead of the MAC in
all commands.

Pairing
-------

Pairing uses an 8-step handshake reverse-engineered from the Wyze protocol.
The old tool only sent the final verify step, making pairing unreliable.
The current implementation runs the full sequence and optionally stores the
chime under a friendly name in `/etc/thingino.json`.

### Step-by-step

1. **Put the chime in pairing mode:** Unplug the chime for at least 10
   seconds, plug it back in, then hold the button until the LED starts
   **slowly flashing blue** (~3–4 seconds).

2. **Run the pair command:**

   ```
   doorbell_ctrl pair living_room
   ```

   This pairs the chime and stores it as `"living_room"` in
   `/etc/thingino.json`. When no name is given, an auto-generated
   name is derived from the MAC address (e.g. `chime_39F9` for
   MAC `77:DA:39:F9`):

   ```
   doorbell_ctrl pair
   ```

   If you know the chime's MAC address (printed on the label), provide it
   as a fallback:

   ```
   doorbell_ctrl pair kitchen 77:AB:62:77
   ```

   With `-D` to clear old pairings first:

   ```
   doorbell_ctrl -D pair basement 77:AB:62:77
   ```

3. **Press Enter** when prompted. The tool then:

   1. Initialises the sub-GHz radio (`SUB1G_INIT`)
   2. Optionally clears existing pairings (`DELETE_ALL`)
   3. Starts pairing mode (`START_PAIRING`)
   4. Waits up to **45 seconds** for the chime to broadcast its MAC
      (`NOTIFY_SCAN`) — the LED must be slowly flashing blue during this
      period
   5. Sends a 16-byte challenge (`CHALLENGE`)
   6. Waits for the challenge response (`CHALLENGE_RESP`)
   7. Sends the verify command (`VERIFY_RESULT`)
   8. Stops pairing mode (`STOP_PAIRING`)

4. **Success:** The chime plays a confirmation tone and is stored in
   `thingino.json`. It is automatically added to the `"all"` group.

### Troubleshooting pairing

| Symptom                            | Likely cause / fix                                    |
|------------------------------------|-------------------------------------------------------|
| "no chime announcement" after 45 s | Chime not in pairing mode. Re-check: unplug 10+ s, plug in, hold button until slow blue flash. Try again. |
| No sound after "Done!"             | Chime may already be paired. Try `doorbell_ctrl play <NAME> DOORBELL_1 5` to test. |
| Pairing works but chime is silent  | Chime volume may be too low. Test with `DOORBELL_1` at volume 8. |
| LED flashes **fast** blue          | Chime is in factory-reset mode, not pairing mode. Wait for it to settle, then start over. |

### Discovering an already-paired chime

If the chime was paired with the original Wyze firmware (or a previous
Thingino installation), the radio already knows about it.  Use `discover`
to passively capture its MAC without the challenge/verify handshake:

```
doorbell_ctrl discover living_room
```

Like `pair`, put the chime in pairing mode (unplug, replug, hold button
until slow blue flash) before running the command.  The tool listens for
the chime's broadcast, captures the MAC, and stores it in `thingino.json`.

This is faster than a full `pair` and won't disturb existing radio
pairings.

Playing sounds
--------------

Once paired, trigger sounds from the command line using either the chime
name or MAC:

```
doorbell_ctrl living_room DOORBELL_1 5 2
doorbell_ctrl 77:AB:62:77 DOORBELL_1 5 2
```

Play on all stored chimes:

```
doorbell_ctrl play-all DOORBELL_1 5
```

Play on a specific group of chimes:

```
doorbell_ctrl play-group daytime DOORBELL_1 5 2
```

### Sound reference

| ID  | Name          | ID  | Name          |
|-----|---------------|-----|---------------|
| 1   | `SPACE_WAVE`  | 11  | `DOG_BARK_1`  |
| 2   | `WIND_CHIME`  | 12  | `DOG_BARK_2`  |
| 3   | `CURIOSITY`   | 13  | `DOOR_CLOSE`  |
| 4   | `SURPRISE`    | 14  | `DOOR_OPEN`   |
| 5   | `CHEERFUL`    | 15  | `SIMPLE_1`    |
| 6   | `DOORBELL_1`  | 16  | `SIMPLE_2`    |
| 7   | `DOORBELL_2`  | 17  | `SIMPLE_3`    |
| 8   | `DOORBELL_3`  | 18  | `SIMPLE_4`    |
| 9   | `DOORBELL_4`  | 19  | `INTRUDER`    |
| 10  | `BIRD_CHIRP`  |     |               |

### Parameters

| Parameter  | Range        | Default | Description                           |
|------------|--------------|---------|---------------------------------------|
| `SOUND`    | name or 1–19 | —       | Sound to play (see table above)       |
| `VOLUME`   | 1–32         | 5       | Playback volume                       |
| `REPEAT`   | 1–255        | 1       | Number of times to repeat the sound   |

Managing multiple chimes
------------------------

### Listing chimes and groups

```
doorbell_ctrl list
```

Example output:

```
Chimes (3):
  living_room      77:AB:62:77
  kitchen          11:22:33:44
  basement         55:66:77:88

Groups:
  all              living_room kitchen basement
  daytime          living_room kitchen
  nighttime        living_room
```

### Removing a chime

```
doorbell_ctrl unpair kitchen
doorbell_ctrl unpair 11:22:33:44
```

This removes the chime from `/etc/thingino.json` and from all groups.
The radio's pairing table cannot remove individual entries — to fully
clear the radio, use `doorbell_ctrl -D pair` to delete all pairings and
re-pair the remaining chimes.

### thingino.json schema

All chime configuration lives under a single `"chime"` key in
`/etc/thingino.json`. Chimes are stored in the `units` array and
organised into named groups:

```json
{
  "chime": {
    "units": [
      { "name": "living_room", "mac": "77:AB:62:77" },
      { "name": "kitchen",     "mac": "11:22:33:44" },
      { "name": "basement",    "mac": "55:66:77:88" }
    ],
    "groups": {
      "all":       ["living_room", "kitchen", "basement"],
      "daytime":   ["living_room", "kitchen"],
      "nighttime": ["living_room"]
    }
  }
}
```

You can edit entries directly with `jct`:

```
# Add a chime
jct /etc/thingino.json set chime.units.0.name "office"
jct /etc/thingino.json set chime.units.0.mac "AA:BB:CC:DD"

# Add or replace a group
jct /etc/thingino.json set chime.groups.daytime '["living_room","kitchen"]'
```

Groups are JSON arrays of chime names. When a chime is paired with a
name, it is automatically added to the `"all"` group. You must manually
add it to any other groups you want.

Event-driven dispatch
---------------------

The `doorbell_event` script (`/usr/sbin/doorbell_event`) reads an event
configuration from `thingino.json` and routes it to the correct chime
group based on the time of day.

### doorbell_event

```
doorbell_event <event_name>
```

Looks up `chime.events.<event_name>` in `/etc/thingino.json`, determines
whether it is currently day or night (from `/tmp/nightmode.txt`, set by
the dusk2dawn service), applies mode-specific overrides, and calls
`doorbell_ctrl play-group` or `play-all`.

### chime.events schema

The `events` object lives inside the `chime` key:

```json
{
  "chime": {
    "units": [],
    "groups": {},
    "events": {
      "button_press": {
        "sound": "DOORBELL_1",
        "volume": "5",
        "repeat": "2",
        "day": {
          "group": "daytime"
        },
        "night": {
          "group": "nighttime",
          "volume": "2",
          "repeat": "1"
        }
      },
      "motion_alert": {
        "sound": "DOORBELL_2",
        "volume": "3",
        "night": {
          "group": "nighttime",
          "volume": "1"
        }
      }
    }
  }
}
```

### How it works

1. **Baseline:** The top-level `sound`, `volume`, `repeat`, and `group`
   keys define defaults for the event.
2. **Day/night overrides:** The `day` and `night` objects override any
   of the top-level defaults. Only the keys present in the override are
   applied — others fall through to the baseline.
3. **Group selection:** If a `group` is set (either at top level or in
   the mode override), `doorbell_ctrl play-group <group>` is called.
   If no group is set, `play-all` is used (every chime rings).
4. **Day/night state:** Read from `/tmp/nightmode.txt` (set by the
   dusk2dawn cron service based on sunrise/sunset). If the file doesn't
   exist or is empty, "day" is assumed.

### Example: daytime vs nighttime button press

With the config above, when the doorbell button is pressed:

- **Daytime** → `doorbell_ctrl play-group daytime DOORBELL_1 5 2`
  (rings living_room and kitchen)
- **Nighttime** → `doorbell_ctrl play-group nighttime DOORBELL_1 2 1`
  (rings only living_room, quieter and once)

### Adding your own events

Any key under `chime.events` can be used as an event name. For example,
to trigger chimes from a motion detection script:

```sh
doorbell_event motion_alert
```

Or to add a chime to an existing MQTT or webhook action, call
`doorbell_event` from your automation script.

Doorbell button integration
---------------------------

Thingino automatically configures the doorbell button to trigger the chime
via `doorbell_event`. The generated configuration in
`/etc/thingino-button.conf`:

```
KEY_1 RELEASE 0 doorbell_event button_press
KEY_1 TIMED 0.1 play /usr/share/sounds/th-doorbell_3.opus
```

- **RELEASE action:** Calls `doorbell_event button_press`, which applies
  day/night routing from `thingino.json` and plays the appropriate sound
  on the configured group of chimes.
- **TIMED action:** Plays a local doorbell sound through the camera's
  speaker for immediate audible feedback.

To change the button behaviour, edit the `chime.events.button_press`
section in `/etc/thingino.json`. Changes take effect on the next button
press — no reboot needed.

No-chime alarm
--------------

When the doorbell boots with no chimes paired, the indicator LEDs flash
in an alternating blue/yellow pattern to signal that the doorbell is
not yet usable.  This alarm runs from `S14doorbell-alarm` and stops
automatically within two seconds of a successful pairing.

You can stop the alarm manually at any time:

```
/etc/init.d/S14doorbell-alarm stop
```

The alarm can be disabled permanently by removing the init script:

```
rm /etc/init.d/S14doorbell-alarm
```

Build-time configuration
------------------------

In `make menuconfig`:

```
Target packages  --->
  Wyze Accessories  --->
    [*] Wyze Accessories
    [*] Wyze Doorbell Chime
```

Chime MAC addresses are no longer configured at build time. Instead,
pair chimes at runtime with `doorbell_ctrl pair <name>` — they are stored
in `/etc/thingino.json` and persist across reboots.

The `doorbell_ctrl` binary and `doorbell_event` script are installed
automatically when the option is enabled.

Debugging
---------

The `-d` / `--debug` flag prints every TX and RX frame in hex with an ASCII
sidebar, plus step-by-step protocol messages:

```
doorbell_ctrl -d pair living_room
```

Example output during pairing:

```
[+] /dev/ttyS0: 115200 8N1 raw
→ SUB1G_INIT (0x14) [7]: AA 55 53 04 14 FF 01 12  | .US.....
[.] Waiting 0x14 [INIT ACK] (2s)
  ← RX [7]: 55 AA 53 14 01 12 01
[+] Got 0x14 [INIT ACK]
── [3] START_PAIRING ──
→ START_PAIRING (0x1C 01) [7]: AA 55 53 04 1C 01 01 24  | .US.....$
...
```

For low-level protocol exploration, use the individual step commands:

```
doorbell_ctrl init       # initialise radio
doorbell_ctrl start      # enter pairing mode
doorbell_ctrl challenge 77:AB:62:77   # send challenge
doorbell_ctrl verify 77:AB:62:77      # send verify-result
doorbell_ctrl stop       # exit pairing mode
doorbell_ctrl delete     # clear all pairings
```

### Debugging events

To see what `doorbell_event` resolves to at the current time of day:

```
# Check current day/night state
cat /tmp/nightmode.txt

# Run the event manually (verbose by default)
doorbell_event button_press
```

This prints the resolved `doorbell_ctrl` command before executing it,
showing which group, sound, volume, and repeat were selected.
