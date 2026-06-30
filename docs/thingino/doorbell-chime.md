Wyze Doorbell V1 Chime
======================

The Wyze Doorbell V1 includes a CC1310 sub-GHz radio that communicates
wirelessly with a plug-in chime module. Thingino provides a command-line
tool, `doorbell_ctrl`, to pair the chime and trigger sounds.

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

| Command               | Description                                           |
|-----------------------|-------------------------------------------------------|
| `pair [-p] [<MAC>]`   | Full 8-step pairing sequence (see below)              |
| `play <MAC> <SOUND> [VOLUME] [REPEAT]` | Trigger a sound on a paired chime |
| `<MAC> <SOUND> [VOLUME] [REPEAT]`     | Same, positional syntax          |
| `init`                | Initialise the sub-GHz radio (low-level)              |
| `delete`              | Remove all stored pairings from the radio (low-level) |
| `start`               | Enter pairing mode on the radio (low-level)           |
| `stop`                | Exit pairing mode on the radio (low-level)            |
| `challenge <MAC>`     | Send challenge to a chime (low-level)                 |
| `verify <MAC>`        | Send verify-result to a chime (low-level)             |

The MAC address is written in `XX:XX:XX:XX` colon-separated format. It can
appear anywhere in the arguments — the tool auto-detects strings containing `:`.

Pairing
-------

Pairing uses an 8-step handshake reverse-engineered from the Wyze protocol.
The old tool only sent the final verify step, making pairing unreliable.
The current implementation runs the full sequence.

### Step-by-step

1. **Put the chime in pairing mode:** Unplug the chime for at least 10
   seconds, plug it back in, then hold the button until the LED starts
   **slowly flashing blue** (~3–4 seconds).

2. **Run the pair command:**

   ```
   doorbell_ctrl pair
   ```

   If you know the chime's MAC address (printed on the label), provide it
   as a fallback:

   ```
   doorbell_ctrl pair 77:AB:62:77
   ```

   With `-D` to clear old pairings first:

   ```
   doorbell_ctrl -D pair 77:AB:62:77
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

4. **Success:** The chime plays a confirmation tone. The doorbell is now
   paired.

### Troubleshooting pairing

| Symptom                            | Likely cause / fix                                    |
|------------------------------------|-------------------------------------------------------|
| "no chime announcement" after 45 s | Chime not in pairing mode. Re-check: unplug 10+ s, plug in, hold button until slow blue flash. Try again. |
| No sound after "Done!"             | Chime may already be paired. Try `doorbell_ctrl play <MAC> DOORBELL_1 5` to test. |
| Pairing works but chime is silent  | Chime volume may be too low. Test with `DOORBELL_1` at volume 8. |
| LED flashes **fast** blue          | Chime is in factory-reset mode, not pairing mode. Wait for it to settle, then start over. |

Playing sounds
--------------

Once paired, trigger sounds from the command line:

```
doorbell_ctrl <MAC> <SOUND> [VOLUME] [REPEAT]
```

Examples:

```
# Ring DOORBELL_1 at volume 5, once
doorbell_ctrl 77:AB:62:77 DOORBELL_1 5

# Play BIRD_CHIRP at max volume, 3 times
doorbell_ctrl 77:AB:62:77 BIRD_CHIRP 8 3

# Use the decimal sound ID instead of name
doorbell_ctrl 77:AB:62:77 6 5 1
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
| `MAC`      | `XX:XX:XX:XX`| —       | Chime MAC address (printed on label)  |
| `SOUND`    | name or 1–19 | —       | Sound to play (see table above)       |
| `VOLUME`   | 1–32         | 5       | Playback volume                       |
| `REPEAT`   | 1–255        | 1       | Number of times to repeat the sound   |

Doorbell button integration
---------------------------

Thingino automatically configures the doorbell button to trigger the chime.
The build-time setting `BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL_MAC` (menu
option "Chime MAC") is written into `/etc/thingino-button.conf` at build time.

The generated configuration:

```
KEY_1 RELEASE 0 doorbell_ctrl <MAC> 15 1
KEY_1 TIMED 0.1 play /usr/share/sounds/th-doorbell_3.opus
```

- **RELEASE action:** Sends `SIMPLE_1` (sound 15) at volume 1 to the chime
  when the button is released.
- **TIMED action:** Plays a local doorbell sound through the camera's speaker
  for audible feedback.

To change the chime sound or volume, edit `/etc/thingino-button.conf`
directly on the camera and reboot.

Build-time configuration
------------------------

In `make menuconfig`:

```
Target packages  --->
  Wyze Accessories  --->
    [*] Wyze Accessories
    [*] Wyze Doorbell Chime
    (00:11:22:33) Chime MAC
```

Set the MAC address to match the label on your chime module. After changing
the MAC, rebuild:

```
CAMERA=wyze_doorbell_v1 make
```

Debugging
---------

The `-d` / `--debug` flag prints every TX and RX frame in hex with an ASCII
sidebar, plus step-by-step protocol messages:

```
doorbell_ctrl -d pair 77:AB:62:77
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
