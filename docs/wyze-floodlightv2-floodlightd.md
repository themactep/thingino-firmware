# Wyze Floodlight v2 control guide

`floodlightd` owns `/dev/ttyS2` and communicates with the CH554 MCU. Do not
write MCU frames directly while the daemon is running. Use `floodlightctl`,
which talks to the daemon through `/run/floodlightd.sock`.

The service starts automatically and defaults to PIR/auto mode.

## Status and monitoring

Show the current mode, light level, raw PIR samples, detected motion zones,
valid PIR frame counters, and remaining override time:

```sh
floodlightctl status
```

Follow line-delimited JSON events until Ctrl-C:

```sh
floodlightctl monitor
```

The monitor reports `pir`, `motion`, `light`, `mode`, and diagnostic events.
PIR activity continues to be monitored during manual light overrides. If
valid 0xBD replies arrive but the first 20 all contain six zero data bytes,
the daemon emits an `all_zero` diagnostic. That means the UART protocol is
working but the PIR daughterboard/sensor path is not producing samples.

The `pir_raw` status array is the MCU's left/middle/right sample data;
`pir_motion` is the host-side filtered result. `pir_frames` proves replies are
arriving, while `pir_nonzero_frames` distinguishes an idle sensor from a dead
all-zero sensor path.

## PIR-triggered light

Use a 30-second hold and 100% brightness:

```sh
floodlightctl auto 30 100
```

The hold begins after the last active PIR sample. More motion extends it.
The arguments are optional, so `floodlightctl auto` returns to the configured
PIR mode without changing its hold time or brightness.

Use the stock maximum sensitivity (default), or change it at runtime:

```sh
floodlightctl sensitivity 255
```

The three sensitivity bands match stock: 0–102 is low, 103–153 is medium,
and 154–255 is high. Enable zones with a bitmask (`left=1`, `middle=2`,
`right=4`); all zones is 7:

```sh
floodlightctl zones 7
```

## Manual control

Turn on indefinitely at the configured brightness:

```sh
floodlightctl on
```

Turn on indefinitely at 50%:

```sh
floodlightctl on 50
```

Turn on at 75% for five minutes, then return to PIR/auto mode:

```sh
floodlightctl on 75 300
```

Force the light off indefinitely:

```sh
floodlightctl off
```

Force it off for one minute, then return to PIR/auto mode:

```sh
floodlightctl off 60
```

An override without a duration remains active until another command, daemon
restart, or reboot. A timed override always returns to PIR/auto mode when it
expires.

## Boot defaults

Edit `/etc/floodlightd.conf` and restart the service:

```sh
BRIGHTNESS=100
HOLD=30
POLL=500
SENSITIVITY=255
ZONES=7
RAMP=5
HOOK=/etc/floodlightd/motion.sh
```

```sh
/etc/init.d/S96floodlightd restart
```

`BRIGHTNESS` is the PIR-triggered level, `HOLD` is seconds after the last
motion detection, and `POLL` is the PIR polling interval in milliseconds.
`SENSITIVITY` is 0–255 and `ZONES` is the enable bitmask. Keep polling enabled:
the MCU exposes raw PIR readings through the 0xBC/0xBD request/reply path; no
separate PIR initialization command exists.

The executable hook receives one argument containing three 0/1 motion-zone
flags:

```text
/etc/floodlightd/motion.sh "left middle right"
```

Runtime overrides are intentionally not written to flash.
