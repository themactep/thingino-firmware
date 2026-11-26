Reset Button
============

`thingino-button` maps gpio-keys events to commands
(`/etc/thingino-button.conf`). The default reset key mapping is:

| Hold time | Action |
|-----------|--------|
| 0.1 s     | `tell %ip` |
| 5 s       | `/sbin/wlan reset; reboot` |
| 20 s      | `firstboot -f` (factory reset) |

The TIMED action runs on release and picks the longest time the hold
reached, so a key that is wrongly reported as held is dangerous.

Safeguards against a stuck key
------------------------------

- Kernel 3.10 (XBurst1, all SoCs): the GPIO controller has no dual edge
  trigger. The emulation flips the level trigger in
  `gpio_mask_and_ack_irq()`; it now re-samples the pin after clearing the
  flag and re-arms until the level is stable, so a fast press or contact
  bounce no longer loses the release edge
  (`package/all-patches/linux/3.10.14/0111-*`).
- gpio-keys (3.10): while a key reads as pressed, its level is re-read
  every 50 ms, so a lost release edge is reported within 50 ms.
- thingino-button: a hold is only valid between a press and a release
  event while the kernel still reports the key down (`EVIOCGKEY`, checked
  every 100 ms while a key is held). A key that reads released for 200 ms
  without a release event drops the hold; its next release runs no TIMED
  command. Hold times use the monotonic clock, so an NTP time step during
  a press cannot select the factory reset.

Service
-------

`/etc/init.d/S15thingino-button` runs the daemon in the foreground mode
(`-s`, syslog) under `start-stop-daemon -b -m`, so the pidfile holds the
real pid. `stop` kills by pidfile and then by executable, and waits until
no instance is left; `restart` therefore never leaves two daemons (two
daemons run every action twice).
