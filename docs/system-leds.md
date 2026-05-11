# System LED Routine

Thingino now uses the Linux LED subsystem (`/sys/class/leds`) as the default system LED control path.

## Boot routine

1. `S00blink` starts early boot blink by selecting the first matching indicator LED class device (blue/green/white/yellow/red) and enabling the `timer` trigger.
2. `F00ledd start` saves current LED brightness values and applies blink via LED class triggers.
3. `rcS` calls `F00ledd stop` at the end of init to stop blink and restore saved brightness.

No `/run/ledd/<pin>` GPIO file control is used in the default flow.

## Runtime control

- `/usr/sbin/led` discovers channels from LED class device names and maps color requests (`r`, `g`, `b`, `y`, `c`, `m`, `w`, `p`) to LED class entries.
- LED state is set through `trigger` and `brightness` only.

## Build defaults

- `thingino-ledd` is no longer enabled by default in `configs/fragments/core.fragment`.
- Camera LED pins must be provided through kernel DTS LED nodes so LED class devices are present at runtime.
