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
