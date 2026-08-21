GPIO
====

### GPIO Map in Stock Firmware

Dump stock firmware.
Use `hijacker.sh` to repack the firmware without root password.
Flash the repacked binary back to the camera.
Connect via UART, login as `root` with empty password and run:

```
mount -t debugfs none /sys/kernel/debug; cat /sys/kernel/debug/gpio
```

Save the output for future reference.

### GPIO scanning

Sweeping a range of pins can be done using the following simple
one-liner, where 0 and 35 are the range of pins to toggle:

```
for i in $(seq 0 35); do echo $i; gpio set $i 1; sleep 1; gpio set $i 0; done
```

### Declarative GPIO power control

Wiring for SD/eMMC power switches and wireless modules is now described in
`/etc/thingino.json` under the `gpio.mmc_power` and `gpio.wlan` keys. Both
use the same flexible schema, so you can mix legacy strings, single objects,
or ordered arrays depending on the SoC/board needs.

Supported shapes:

- **Legacy string**
  e.g. `"47O 47o"` means: set GPIO 47 high, then low.
  Suffixes `O` / `o` represent logic high / low.
  The optional `t`, `T`, or `~` suffix flips the pin (`"60~"`).
  These strings remain backwards compatible, but prefer the structured
  formats below for clarity.
- **Single object**
  `{ "pin": 60, "active_low": true }` resolves to a single `gpio set 60 0`.
  Omitting `active_low` defaults to active high.
- **Array of objects/strings** –
  `[ { "pin": 60 }, "62o", { "pin": 63, "action": "toggle" } ]` executes each
  entry in order, allowing complex multi-pin sequences without shell scripting.

Additional object fields:

| Field        | Type      | Purpose                                           |
|--------------|-----------|---------------------------------------------------|
| `pin`        | number    | GPIO number to drive (required).                  |
| `active_low` | bool      | Inverts the default level when no explicit state  |
|              |           |   is supplied.                                    |
| `state` /    | bool /    | Explicitly request `0` or `1`                     |
| `value`      | number /  |   (aliases like `"on"`, `"off"`, `"high"`,        |
|              | string    |   `"low"` are accepted).                          |
| `action`     | string    | `"set"` (default) or `"toggle"`. `toggle` flips   |
|              |           |   the current pin state.                          |
| `toggle`     | bool      | When true and `action` is `set`, the pin is first |
|              |           | driven to the opposite level, then to the desired |
|              |           | level. Useful for active-low reset lines that     |
|              |           | require a rising edge without writing two objects.|

Examples:

```json
"gpio": {
  "mmc_power": {
    "pin": 48,
    "active_low": true,
    "toggle": true
  },
  "wlan": [
    { "pin": 47, "state": 1 },
    { "pin": 47, "action": "toggle" },
    "65o"
  ]
}
```

Processing rules:

- Arrays are executed strictly in order; nothing is reordered.
- When `action` is `toggle`, the pin flips exactly once; `toggle` on its own
  does not imply setting a specific high/low level.
- When `toggle: true` appears with `action: set`, the system first writes the
  inverse of the requested state (or the inverse of the `active_low` default)
  and then writes the requested state, creating a deterministic edge (e.g.
  high→low for active-low resets).
- Multiple pins can be listed, and Wi-Fi bring-up tracks every pin involved
  so drivers like `bcmdhd` can unexport all of them afterwards.

Update `/etc/thingino.json`, then restart the corresponding init script
(`S09mmc` for storage power or `S36wireless` for Wi-Fi) to apply the new
sequence.

### Speaker amplifier enable

Cameras with an external audio amplifier gate it with a GPIO. That pin is
`gpio.speaker`, written in the same short notation as the rest of the
section - a bare number for an active-high line:

```json
"gpio": {
  "speaker": 63
}
```

and the object form when the line is active low:

```json
"gpio": {
  "speaker": { "pin": 64, "active_low": true }
}
```

Leave the key out entirely on boards that have no such pin.

Unlike `gpio.mmc_power` and `gpio.wlan` above, which init scripts read at
runtime, this one is consumed at **build time** by three places, so changing
it means rebuilding the camera rather than editing `/etc/thingino.json` on a
running device:

- the codec kernel module's `spk_gpio` and `spk_level` parameters, written
  into `/etc/modules.d/40-audio`;
- `ingenic,spk-gpio` on the U-Boot codec node, which U-Boot's `sound`
  command drives around playback. Boards with no `gpio.speaker` get the
  per-SoC reference default (PB31) deleted from their device tree instead,
  so U-Boot never drives a pin the board uses for something else;
- a boot-window `gpio-hog` holding the amp at its muted level, so it is not
  left floating between power-on and the first playback.
