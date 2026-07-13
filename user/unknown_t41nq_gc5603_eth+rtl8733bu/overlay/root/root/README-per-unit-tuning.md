# Per-unit tuning via module / kernel parameters (T41NQ DML16-Z533)

A couple of settings on these cameras are per-unit or per-board and are applied
through a **module or kernel parameter** rather than the main config. This file
documents both; keep it in /root as a reminder. Concrete sensor example lives in
`modules.d-30-sensor.sample`; the ADC-invert kernel patch is
`patches/0005-ingenic-adc-aux-invert-module-param.patch`.

Neither is required for a working camera - the image streams and day/night (via
`[ircut] trigger=gain`) work without them. They are optional "make it exactly
right" tweaks.

---

## 1. Image flip - sensor module parameter (`shvflip`)

The GC5603 image orientation is set with the sensor driver's `shvflip` param.
It is **per unit**, because these cameras are mounted differently (and at least
one "quality" variant has the sensor 180deg on the PCB).

Set it in `/etc/modules.d/30-sensor` and reboot (applied at module load; no
hot-reload - reloading the sensor under a running raptor oopses the ISP):

```
sensor_gc5603_t41 shvflip=3
```

| value | effect |
|---|---|
| 0 | none |
| 1 | mirror (hflip) - driver default |
| 2 | flip (vflip) |
| 3 | mirror + flip (180deg) |

Pick by eye. Typical: normal mount -> `shvflip=3`; a unit mounted physically
upside-down -> `shvflip=0`. Also clear any ISP-side flip so the guard can't fire
(`raptorctl rvd set-vflip 1` returns -4090 on this build):

```
raptorctl config set isp hflip 0; raptorctl config set isp vflip 0; raptorctl config save
```

See `modules.d-30-sensor.sample` for the ready-to-copy file.

---

## 2. Inverted light-sensor day/night - kernel parameter (`ingenic_adc_aux.invert`)

The day/night photoresistor (LDR) on SADC AUX0 is wired **inverted** on these
boards: bright = LOW (~0), dark = HIGH (~15000 of ~17995 full scale). raptor's
RIC ADC trigger assumes higher = brighter and has no invert option, so without
this it never switches. The kernel patch adds an `invert` parameter that returns
`(invert - reading)`, flipping the polarity so bright -> high, dark -> low.
This is **board-wide** (same wiring on all units).

Requires `patches/0005-ingenic-adc-aux-invert-module-param.patch` in the kernel.
Then enable it one of two ways:

Persistent (kernel cmdline - add to the board uenv bootargs):
```
ingenic_adc_aux.invert=20000
```

Runtime (for tuning - read every sample, so takes effect immediately):
```
echo 20000 > /sys/module/ingenic_adc_aux/parameters/invert
```

Pick `invert` slightly above full scale (20000 is safe). Verify the polarity:
```
dd if=/dev/ingenic_adc_aux_0 bs=2 count=1 2>/dev/null | od -d | head -1 | awk '{print $2}'
# now: covered/dark -> low, bright -> high
```

Then switch raptor day/night to the light sensor, thresholds between your
measured dark (low) and bright (high) readings:
```
[ircut]
trigger = adc
adc_channel = 0
adc_night = 8000      # below -> night (dark reads low after invert)
adc_day   = 12000     # above -> day  (bright reads high)
```
`/etc/init.d/S31raptor restart`. If you prefer, `trigger=gain` also works and
needs no kernel patch (see raptor.conf.sample).

---

## See also

- **Speaker amp** (the "quality" variant with a real speaker): GPIO 63 / PB31,
  active-high. See `../variants/speaker-audio/`. Not a module param - driven via
  an init or the uenv, and best left off unless a speaker is plugged in (thermal).
