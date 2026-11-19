# Fixing sensor mode mismatches

Instructions for a developer, or a coding agent working for one, who has a
camera whose sensor driver is on the
[sensor mode roadmap](sensor-mode-roadmap.md). The job is to take one row,
find out on the camera which side of the disagreement is right, fix the driver,
show the fix on the camera, and send two pull requests: the driver to
[thingino/ingenic-sdk](https://github.com/thingino/ingenic-sdk), the roadmap row
to this repository.

## Background

A sensor driver states the frame of each mode in three places:

- the register init table of the mode, which programs the sensor's frame-length
  registers (the frame the sensor runs at power-up);
- the attributes the mode reports to the ISP: `total_height`, with
  `max_integration_time`, `max_integration_time_native` and
  `integration_time_limit` derived from it;
- `set_fps`, which computes a frame length from a clock constant, the line
  length and the requested rate, writes it to the sensor and reports it to the
  ISP.

The ISP takes its line time from the frame rate and `total_height`. When
`total_height` is not the frame the sensor runs, every exposure time and every
anti-flicker step the ISP computes is off by the ratio of the two.

The worked example is
[ingenic-sdk#13](https://github.com/thingino/ingenic-sdk/pull/13): the T31
GC2053 30 fps MIPI table programs 1181 lines, the mode reported 1418, and the
ISP's "60 Hz" anti-flicker steps were 10 ms of real exposure, so the picture
banded under 60 Hz light.

`tools/check_sensor_modes.py` in ingenic-sdk finds these disagreements by
reading the source. It cannot tell which side is right.

## Rules

- **Do not pick a side from the source alone.** A finding says two places
  disagree. Which one the sensor follows is decided by a measurement on a
  camera, or by the sensor's datasheet. Do not edit whichever side is easier
  just to make the script go quiet.
- **Touch a camera only on the user's order** (see `AGENTS.md`): no upload, no
  module load, no flash without it. Ask for the camera's address; do not guess
  it.
- **One sensor per pull request.** Fix the mode that was measured. Leave the
  other rows of the same driver open unless they are the same edit and the text
  says they were not measured.
- **Both kernel trees.** A driver present under `3.10.14/` and `4.4.94/` gets
  the same fix in both, in one pull request.
- **Say what was not measured.** A fix that was built but never run on a sensor
  is marked so, in the pull request and on the roadmap.
- **Do not paste datasheet text** into a commit, a pull request or these pages.
  Cite the document by name and revision.

## 1. Find the row

From the camera profile's defconfig:

| Value | Where | Gives |
|---|---|---|
| SoC family | `BR2_INGENIC_SOC_MODEL` (`t31x` is family `t31`) | the folder; `t10` builds from `t20`, `c100` from `t31` |
| Kernel | `KERNEL_VERSION_4=y` is `4.4.94`; without it, `3.10.14` on T10 to T33 and `4.4.94` on T40, T41 and A1 | the tree |
| Sensor | `BR2_SENSOR_1_NAME` | the file: `<kernel>/sensor-src/<family>/<sensor>.c` |
| Mode | `BR2_SENSOR_1_PARAMS`, and the driver's own defaults for what is not set | the row |

The mode is what the driver's probe selects from its module parameters
(`sensor_max_fps`, `data_interface`, `sensor_resolution`, `data_type`). The
defaults are the `static int <name> = ...;` lines at the top of the driver. The
T32, T40 and T41 drivers select the mode by `default_boot`, which the streamer
passes in (raptor's `[sensor] boot` setting). No profile in this tree sets it;
the roadmap takes it to be 0 then, which was not checked on a camera.

On a running camera the parameters in force are in
`/sys/module/sensor_<sensor>_<soc>/parameters/`.

If no row matches the mode the camera runs, the camera cannot show that row's
fault as it is. Stop there and say so, or load the row's mode only if the
board's wiring allows it (interface, lanes, clock) and the user agrees.

Look through the open pull requests of ingenic-sdk for the sensor first, so
that two people do not fix the same row.

## 2. Get the driver source and run the checker

```sh
./scripts/manage-package-overrides.sh ingenic-sdk
```

This clones the SDK into `overrides/ingenic-sdk/` and registers it in
`local.mk` (see [local overrides](../build/local-overrides.md)). Start the fix
branch from the tip of the SDK's `main`, not from the commit the firmware pins:
the fix goes to `main`.

```sh
cd overrides/ingenic-sdk
python3 tools/check_sensor_modes.py --driver t31/gc2053 --modes
python3 tools/check_sensor_modes.py --list-checks
```

The finding names the init table, the frame-length registers and the line. The
`--modes` table lists every mode of the driver with three numbers, in lines per
frame:

- `T`: what the init table programs;
- `A`: the `total_height` the mode reports;
- `C`: what `set_fps` computes at the mode's own rate.

Line numbers on the roadmap are those of the SDK commit it was generated from;
go by the script's output on the checkout in hand.

## 3. Read the driver

Read the three places for the row's mode before measuring anything:

- the init table: the frame-length register writes, and the table's header
  comment (often left over from the table it was copied from);
- the probe branch, or `sensor_attr_check` on T40 and T41: `total_height`, the
  three integration limits, and any cached frame-length bytes;
- `set_fps`: the clock constant and line length it uses for this mode, and
  whether it has a branch for the mode at all.

Then read the file's history for the lines involved (`git log -L`, `git blame`).
In the GC2053 case the table had been changed to a new rate in one commit and
the attributes left at the old one.

## 4. Measure on the camera, before any change

Only on the user's order. These are the readings that settled the GC2053 case.
They were taken on a T31 running the raptor streamer; on another SoC or streamer
the file names and commands may differ, so list what is there first
(`ls /proc/jz/isp/`) and say in the pull request which readings were possible.

1. **The parameters in force:**
   `cat /sys/module/sensor_<sensor>_<soc>/parameters/*`.
2. **What the ISP believes:** `/proc/jz/isp/isp-m0`. `SENSOR Max Integration
   Time` is the mode's `max_integration_time`; with anti-flicker on, the last
   value of `Antiflicker nodes ... step` is the frame length the ISP works
   with, the mode's `total_height`.
3. **What the sensor runs:** read the frame-length registers the finding names,
   over I2C, read only. The bus and address are in `/sys/bus/i2c/devices/`.
   For a sensor with 8-bit register addresses: `i2cget -f -y <bus> <addr> <reg>`.
   A sensor with a page register needs the page read first and left as found.
   Sensors with 16-bit register addresses need a two-byte address write before
   the read; that was not done for this guide.
4. **The real frame interval:** the timestamps of a few hundred consecutive
   frames (`ringdump main -f` with raptor) give the mean frame interval. Frame
   length in lines is the interval times the pixel clock over the line length,
   with the clock and line length the driver uses for the mode. For the GC2053:
   33310.29 us, which is 1181 lines of 28.205 us.
5. **A cross-check that needs no build:** ask the streamer for another sensor
   rate and then for the original one (`raptorctl rvd set-sensor-fps 25`, then
   `raptorctl rvd set-sensor-fps 0`). A real rate change runs `set_fps`, which
   hands the ISP the frame it computes. If readings 2 change after the cycle,
   the probe's attributes and `set_fps` disagree on the camera as they do in the
   source. A request for the rate already running did not reach the driver, and
   a streamer restart probes the sensor again and brings the probe's values
   back.

The sensor's registers and the frame interval say which frame the sensor runs.
The side of the driver that states another frame is the wrong one. If the
readings contradict each other, stop and report them; do not average them into
a fix.

If the measurement shows the driver is right as it stands (the finding is an
artefact of how the driver is written), set the row to `not a bug: <why>` and
send only the roadmap change.

## 5. Change the driver

Make the smallest edit that brings the three places into agreement with the
measurement. When the table is right and the attributes are stale (the GC2053
case), that is, for the mode's branch only:

- `total_height`;
- `max_integration_time`, `max_integration_time_native` and
  `integration_time_limit`, kept at the same offset from `total_height` as the
  driver's other modes use;
- any cached frame-length bytes the branch sets;
- the table's header comment, if it states the old frame.

When the table is wrong, change the table's frame-length registers and nothing
else. When `set_fps` is wrong (a clock constant, a missing branch, bytes written
to the wrong registers), fix that and say how a rate change was tested.

Apply the same edit to the driver's copy in the other kernel tree. Copies in
other SoC folders are separate rows: change one only if it is the same code and
the pull request says it was not measured.

## 6. Check with the script

```sh
python3 tools/check_sensor_modes.py --driver <family>/<sensor> --modes
```

The row's finding is gone, the mode's `T`, `A` and `C` agree, and no finding
appeared that was not there before the edit.

## 7. Build and run it

```sh
CAMERA=<profile> make rebuild-ingenic-sdk
```

The module is `sensor_<sensor>_<soc>.ko` under the build's
`target/lib/modules/`. To try it without writing flash, on the user's order:

1. Copy the module to `/tmp` on the camera and check its checksum there.
2. Note the parameters the stock module was loaded with (reading 1 of step 4).
3. Stop the streamer and wait until its process and the sensor's I2C client
   under `/sys/bus/i2c/devices/` are both gone. The module's reference count
   reads 0 even while the streamer uses the sensor, so `rmmod` does not refuse
   by itself.
4. `rmmod sensor_<sensor>_<soc>`, then `insmod /tmp/<module>.ko` with the same
   parameters.
5. Start the streamer.

A reboot brings the stock module back. This sequence was run once, on a T31
with raptor (`/etc/init.d/S31raptor stop` and `start`).

## 8. Measure again

Repeat step 4 with the patched module, from a fresh streamer start, with no
rate cycle. The fix is shown when:

- the ISP's `SENSOR Max Integration Time` and anti-flicker steps now follow the
  frame the sensor runs;
- the sensor's frame-length registers and the frame interval are unchanged (for
  an attribute fix), or are the intended ones (for a table fix);
- the picture is not worse: check the anti-flicker setting that matches the
  mains frequency, and a dark scene, where the exposure runs to its limit.

Keep the readings, before and after, as text.

## 9. Send it

1. **The driver**, to thingino/ingenic-sdk `main`: one commit, signed off,
   touching only the driver's copies. In the text: the three numbers before and
   after, the camera profile, the readings of steps 4 and 8, the SDK and
   firmware commits used, and what was not measured (other modes, other SoC
   folders, night).
2. **The roadmap row**, to this repository: set the row's Status to
   `fixed: <pull request>, measured on <profile>`. Once the driver is merged,
   move the row to the Done table.

Do not bump `INGENIC_SDK_VERSION` in the same pull request unless a maintainer
asks; the pin moves on its own schedule.

## Refreshing the roadmap

The roadmap is a snapshot of one SDK commit. After drivers change, run the
script on the new `main`: a row whose finding is gone belongs in Done with the
commit that fixed it, and a finding that has no row is a new row. A driver that
is not on the roadmap is not proven right: the script reads the frame length
from the init table for about four modes in five, and reports the rest as not
read.
