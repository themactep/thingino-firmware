# Wyze Floodlight v2 control guide

`floodlightd` owns `/dev/ttyS2` and communicates with the CH554 MCU. Do not
write MCU frames directly while the daemon is running. Use `floodlightctl`,
which talks to the daemon through `/run/floodlightd.sock`.

The service starts automatically and defaults to PIR/auto mode.

## Status and monitoring

Show the current mode, light level, PIR zones, and remaining override time:

```sh
floodlightctl status
```

Follow line-delimited JSON events until Ctrl-C:

```sh
floodlightctl monitor
```

The monitor reports `pir`, `motion`, `light`, and `mode` events. PIR activity
continues to be monitored during manual light overrides.

## PIR-triggered light

Use a 30-second hold and 100% brightness:

```sh
floodlightctl auto 30 100
```

The hold begins after the last active PIR sample. More motion extends it.
The arguments are optional, so `floodlightctl auto` returns to the configured
PIR mode without changing its hold time or brightness.

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
RAMP=5
HOOK=/etc/floodlightd/motion.sh
```

```sh
/etc/init.d/S96floodlightd restart
```

`BRIGHTNESS` is the PIR-triggered level, `HOLD` is seconds after the last
motion sample, and `POLL` is the PIR polling interval in milliseconds. Set
`POLL=0` only when using passive MCU events.

The executable hook receives one argument containing the three zone values:

```text
/etc/floodlightd/motion.sh "left middle right"
```

Runtime overrides are intentionally not written to flash.
