# T31 mainline sensor drivers (open ISP)

This page describes the sensor-driver structure used by the T31 open-ISP path
on Linux 7.3.3. It is the reference for porting a new sensor, including the
AE gain model, which is the part that is easy to get wrong.

The short version: the kernel driver stays a normal mainline V4L2 subdev
driver, and open-tx-isp's V4L2 bridge supplies the Ingenic vendor ABI on top
of it. The bridge also owns the AE gain model for each sensor.

## Layers

| Layer | Location | Responsibility |
| --- | --- | --- |
| Mainline V4L2 driver | `linux/drivers/media/i2c/<sensor>.c`, carried as a patch in `package/all-patches/linux/7.3.3/` | Register sequences, V4L2 controls, the index-to-register gain table |
| V4L2 bridge | open-tx-isp `driver/t31/tx_isp_v4l2_sensor.c` | Finds the probed subdev, implements `tx_isp_sensor_attribute`, `alloc_again`, `alloc_dgain`, and the per-sensor log2-Q16 gain model |
| ISP core | open-tx-isp `driver/t31/tx_isp_module.c`, `tx_isp_core.c` | AE, CSI/ISP pipeline, frame production |
| Sensor DT fragment | `configs/sensors/t31/<model>.dtsi` | I2C address, supplies, clock, MIPI endpoint; injected into the kernel leaf `.dts` before the camera fragment |
| Camera selection | `configs/cameras/<camera>/<camera>_defconfig` | `BR2_SENSOR_1_NAME="<model>"`; drives `SENSOR_1_MODEL`, `CONFIG_VIDEO_<MODEL>`, and `SENSOR_DTSI_FILE` |
| Raptor config | `package/thingino-raptor/thingino-raptor-conf.mk` | Seeds `[sensor] name` and `i2c_addr` from the build when the explicit raptor options are unset |
| Startup gate | `package/thingino-raptor/files/S30raptor-sensor-wait` | Holds the streamer until the mainline sensor's I2C driver is bound |

The open-tx-isp source is fetched by `package/open-tx-isp/open-tx-isp.mk`.
Bridge changes are carried as numbered patches in `package/open-tx-isp/`
(for example `0015-`, `0016-`, `0017-`), not by editing the fetched tree.

The kernel source is not edited directly. Add or change a driver with a patch
in `package/all-patches/linux/7.3.3/`. The existing SC2336 port is
`0020-media-i2c-add-sc2336.patch`; the Kconfig/Makefile entries are in
`0099-media-i2c-enable-thingino-t31-sensors.patch`.

## What the bridge needs from a sensor

The bridge attaches to a probed V4L2 subdev whose name matches the sensor
model string, and expects these controls:

- `V4L2_CID_EXPOSURE`
- `V4L2_CID_ANALOGUE_GAIN`
- `V4L2_CID_HBLANK`
- `V4L2_CID_VBLANK`
- `V4L2_CID_LINK_FREQ`
- `V4L2_CID_PIXEL_RATE`

It also reads the MIPI lane count, link frequency and pad format from the
subdev. `V4L2_CID_ANALOGUE_GAIN` is an **index** into the driver's gain
table; it is not a physical gain.

The bridge sets `attr->max_dgain = 0`; the vendor SDK drivers also leave
digital gain at zero. Exposure is controlled by integration time plus the
analog gain index.

## The AE gain model

The Ingenic AE works in **log2(gain) in Q16**: `0` is 1x, `65536` is 2x,
`131072` is 4x, `327680` is 32x. `alloc_again()` receives the requested gain
in this unit and must return the applied gain in the same unit. `max_again`
is also log2 Q16; the ISP core converts it internally with
`exp2(value, 0x10, 0xa)`.

The bridge LUT is therefore the vendor driver's gain column **verbatim**, one
entry per V4L2 gain index:

```c
struct again_lut sensor_again_lut[] = {
    { 0x80,      0 },   /* 1.0x  */
    ...
    { 0xfc,  64059 },   /* 1.97x */
    { 0x880, 65536 },   /* 2.0x  */
    ...
    { 0x1f80, 327680 }, /* 32x   */
};
```

Do **not** convert the column to linear Q10. A linear `32768` is read by the
AE as `2^(32768 / 65536) = 1.41x`, not 32x, so the AE runs out of analogue
gain early and makes up the rest with ISP digital gain, which is noisy at
night. Do not derive the gain from the register coding
`1 + coarse + (fine - 128) / 128` either: it only holds for coarse 0 and
reports 9x, 10x and 12x where the sensor gives 2x, 4x and 8x.

The index is the V4L2 analogue-gain control value. Index 0 is **1.0x, not
"no change"**: `tx_v4l2_sensor_set_expo()` must write the gain on every EXPO
event. Skipping the write at index 0 leaves the sensor at the previous gain
when the AE trades gain for integration time; that frame can be up to a stop
too bright and the AE oscillates between anti-flicker steps. This was the
actual SC2336 "breathing" fault.

Current models in `tx_v4l2_gain_models[]`:

| Sensor | Entries | Max index | Max gain | `max_again` |
| --- | ---: | ---: | ---: | ---: |
| `sc2336` | 161 | 160 | 32x | 327680 |
| `sc2336p` | 161 | 160 | 32x | 327680 |
| `sc4236` | 63 | 62 | 15x | 256041 |
| `gc2083` | 29 | 28 | 125x | 456839 |
| `gc4023` | 25 | 24 | 64x | 393216 |

The bridge caps the index at `V4L2_CID_ANALOGUE_GAIN.maximum` and sets
`attr->max_again` to the LUT value at that index. A model whose size does
not match the control range is a bug: the AE will either be limited early or
the extra entries will never be reachable.

## Adding a new sensor

### 1. Port the mainline driver

Add `drivers/media/i2c/<sensor>.c` as a patch in
`package/all-patches/linux/7.3.3/`. It must provide the controls listed
above and a `*_gains[]` table whose control maximum is
`ARRAY_SIZE(*_gains) - 1`.

Keep the **log2 Q16 gain column** next to the register table, either as
comments or as a second field. Future LUT generation depends on it. The
SC4236 port carries it in hex comments, GC2083 and GC4023 in decimal
comments, and SC2336 uses the vendor `sensor_again_lut` directly. A new port
without this column cannot be modelled without going back to the vendor
source.

Add the Kconfig symbol and Makefile entry in
`0099-media-i2c-enable-thingino-t31-sensors.patch`. The symbol must be
`VIDEO_<MODEL>` in upper case: `package/open-tx-isp/open-tx-isp.mk` builds
`CONFIG_VIDEO_$(SENSOR_1_MODEL uppercase)` from the camera config. A
mismatch silently leaves the driver out of the kernel.

### 2. Add the DT fragment

Add `configs/sensors/t31/<model>.dtsi` with:

- the `camera@<addr>` node and the driver's `compatible` string,
- `reg`, supplies, clock, reset/power GPIOs,
- the MIPI endpoint and lane count.

The fragment is injected into the kernel leaf `.dts` by the
`THINGINO_KOPT_SYNC_SENSOR_DTSI` build hook before the camera fragment, so a
camera can override the labelled sensor node for board-specific wiring.

### 3. Select the sensor in the camera config

In `configs/cameras/<camera>/<camera>_defconfig`:

```text
BR2_SENSOR_1_NAME="<model>"
```

This drives `SENSOR_1_MODEL`, the kernel `CONFIG_VIDEO_<MODEL>` selection,
the `SENSOR_DTSI_FILE` path, and the raptor config fallback. The fallback in
`thingino-raptor-conf.mk` writes `[sensor] name` from the model and
`i2c_addr` from the `reg` property in the DT fragment. Explicit
`BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_NAME` and
`BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_I2C_ADDR` still win.

### 4. Add the AE gain model

Add a log2-Q16 LUT to the bridge and an entry in `tx_v4l2_gain_models[]`:

```c
static const u32 tx_v4l2_<model>_gain_lut[] = {
    /* log2 Q16 gain at each V4L2 gain index */
    0, 2886, ...
};

static const struct tx_v4l2_gain_model tx_v4l2_gain_models[] = {
    ...
    { "<model>", tx_v4l2_<model>_gain_lut, ARRAY_SIZE(tx_v4l2_<model>_gain_lut) },
};
```

The table can be generated from the driver's log2-Q16 comments:

```python
import re

src = open('drivers/media/i2c/sc4236.c').read()
table = re.search(r'sc4236_gains\[\] = \{(.*?)\n\};', src, re.S).group(1)
rows = re.findall(r'/\*\s*(0x[0-9a-fA-F]+|\d+)\s*\*/', table)
vals = [int(x, 0) for x in rows]
print(', '.join(str(v) for v in vals))
```

Check the result against the table size and the V4L2 control maximum before
adding it.

The `name` must match the sensor model string exactly: it is the same value
that `rvd` passes to `IMP_ISP_AddSensor` and that the bridge compares against
the V4L2 client name.

Carry the change as the next numbered patch in `package/open-tx-isp/`. Do
not leave the table out and rely on the fallback: the bridge logs

```text
tx-isp-v4l2: no gain model for <model>, using the SC2336 model capped at index N
```

and the AE will run with the wrong curve. Add the table before shipping the
camera.

### 5. Build and validate

```bash
CAMERA=<camera> make fast
```

On the camera:

```bash
dmesg | grep tx-isp-v4l2
cat /proc/jz/isp/isp-m0
```

The bridge should log the match and the model:

```text
tx-isp-v4l2: matched <model> at 0x..
tx-isp-v4l2: gain model <model> (N entries, max index M, max gain G)
```

In `/proc/jz/isp/isp-m0`, check:

- `SENSOR NAME` is the expected model,
- `SENSOR Integration Time` and `SENSOR analog gain` are plausible,
- `open-tx-isp attr analog gain` is the index in use,
- `open-tx-isp attr max analog gain` equals the last LUT value in log2 Q16
  (`327680` for the 32x models),
- `ISP digital gain` is not carrying the loop.

AE breathing test (20 s, stable scene):

```bash
ffmpeg -rtsp_transport tcp -i 'rtsp://<user>:<pass>@<camera>:554/ch0' \
  -t 20 -vf 'signalstats,metadata=print:file=/tmp/yavg.txt' -an -f null -
awk -F= '/YAVG=/{print $2}' /tmp/yavg.txt > /tmp/yavg.vals
```

A stable scene should stay within a few luma levels over 20 s. The SC2336
example went from a `74..151` range (breathing) to `116.15..116.50` after
the model was corrected. If the gain index alternates across a large LUT
step, the table is wrong.

Also check low light and the day/night transition: the AE must be able to
walk the whole index range without a jump, and the maximum index must match
the sensor's real maximum.

## Known gaps

- `imx327`, `jxf23`, `jxf37` and `jxq03` have mainline ports but no modelled
  gain LUT yet. They use the warning/fallback path. Add their tables when
  the hardware is available.
- The vendor SDK drivers (3.10/4.4) are a separate path. Their
  `sensor_again_lut` lives in the sensor driver and is used by the vendor
  `sensor_alloc_again`; the V4L2 bridge is not involved.
- The bridge currently supports one active V4L2 sensor
  (`tx_isp_v4l2_sensor_sd` is a single slot); multi-sensor on the mainline
  path is not implemented.
- The bridge LUT duplicates the driver's register table. Keep them in sync
  when the driver table changes; the LUT is the physical gain model, the
  driver table is the register programming.
- The raptor `[image] max_again` / `max_dgain` settings are not the
  authoritative limit on this path. The bridge sets `attr->max_again` from
  the selected LUT and caps the index at the sensor's V4L2 control maximum.

## File map

```text
package/all-patches/linux/7.3.3/0020-media-i2c-add-sc2336.patch
package/all-patches/linux/7.3.3/0099-media-i2c-enable-thingino-t31-sensors.patch
configs/sensors/t31/<model>.dtsi
configs/cameras/<camera>/<camera>.dtsi
configs/cameras/<camera>/<camera>_defconfig
package/open-tx-isp/0017-t31-select-per-sensor-gain-model.patch
package/thingino-raptor/thingino-raptor-conf.mk
package/thingino-raptor/files/S30raptor-sensor-wait
linux/linux-ext-thingino-kopt.mk
package/thingino-kopt/inject-camera-dtsi.sh
```
