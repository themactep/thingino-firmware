# TX-ISP pipeline

The kernel side of the Ingenic media stack is the `tx-isp` driver. It is
modeled as a video-device graph of subdevices ("subdevs") plus widgets. Each
subdev is a platform device; the driver matches them, wires the graph, and
creates the user-visible nodes.

Source: `overrides/ingenic-sdk/common/isp/<soc>/`, primarily the open
3.10.14 T30 tree (T31/T40/T41 use binary modules with the same names).

## Subdev graph

Names come from `txx-isp.h`:

```c
#define TX_ISP_VIN_NAME     "isp-w00"   /* video-in node (sensor controller) */
#define TX_ISP_CSI_NAME     "isp-w01"   /* CSI-2 receiver */
#define TX_ISP_VIC_NAME     "isp-w02"   /* video input controller (DMA) */
#define TX_ISP_CORE_NAME    "isp-m0"    /* Apical ISP core */
#define TX_ISP_LDC_NAME     "isp-m1"    /* lens distortion correction */
#define TX_ISP_NCU_NAME     "isp-m2"    /* post-processing unit */
#define TX_ISP_MSCALER_NAME "isp-m3"    /* memory scaler (crop/scale) */
#define TX_ISP_FS_NAME      "isp-fs"    /* frame source (capture channel) */
```

Dataflow (`tx-isp-common.h` link enums) runs:

```
sensor -> CSI (isp-w01) -> VIC (isp-w02) -> CORE (isp-m0)
        -> LDC (isp-m1) -> NCU (isp-m2) -> MSCALER (isp-m3) -> FS (isp-fs)
```

The `platform.c` file declares one `platform_device` per subdev with its
`platform_data` descriptor (type, subtype, parent id, clock list, memory/IRQ
resources). Roles from the descriptors:

| Subdev | Descriptor subtype | Role |
| --- | --- | --- |
| `isp-w00` | INPUT_TERMINAL (widget) | controller of all sensors |
| `isp-w01` | SELECTOR_UNIT | MIPI CSI-2 receiver |
| `isp-w02` | CONTROLLER | DMA engine pulling raw frames to DDR |
| `isp-m0` | PROCESSING_UNIT | Apical ISP image processing + 3A + tuning |
| `isp-m1` | PROCESSING_UNIT | lens distortion correction |
| `isp-m2` | PROCESSING_UNIT | post-processor between LDC and MSCALER |
| `isp-m3` | PROCESSING_UNIT | crop/scale to output resolution |
| `isp-fs` | OUTPUT_TERMINAL | frame-source channel userspace reads from |

The `CORE` subdev wraps the Apical ISP firmware (see
`apical-isp/` — calibrations, tuning, `sensor_drv`, and the I2C/SPI `sbus`
used to program the sensor).

## User-visible nodes

`tx-isp-device.c` registers, in probe order:

1. `/proc/jz/isp/` (via `jz_proc_mkdir("isp")`).
2. One miscdevice `/dev/<name>` for each subdev that exposes an `ops` table.
3. One proc entry `/proc/jz/isp/<name>` for each subdev that exposes
   `debug_ops`.
4. The controller miscdevice `/dev/tx-isp` with the ioctl fops (`tx_isp_fops`).

So userspace sees both a char-device ioctl surface and a proc debug surface.
`libimp` drives the former; the latter is for humans and diagnostics.

### Proc debug nodes

| Node | Source | Read | Write |
| --- | --- | --- | --- |
| `/proc/jz/isp/isp-w00` | VIN | current sensor/input | input select |
| `/proc/jz/isp/isp-w01` | CSI | MIPI error status registers | — |
| `/proc/jz/isp/isp-w02` | VIC | frame-drop counter | `snapraw` / `saveraw` |
| `/proc/jz/isp/isp-m0` | CORE | ISP status | — |
| `/proc/jz/isp/isp-m1` | LDC | LDC state/buffers | — |
| `/proc/jz/isp/isp-m2` | NCU | NCU state/buffers | — |
| `/proc/jz/isp/isp-m3` | MSCALER | scaler state | — |
| `/proc/jz/isp/isp-fs` | FS | channel/pixformat/buffer state | — |
| `/proc/jz/isp/isp_info` | CORE (apical) | ISP info dump | — |

`isp_info` vs `isp-m0` is a generation difference: the old t10/t20 (gen2)
driver registers the CORE debug node explicitly as `isp_info`, while the gen3
driver (t30+) exposes the same `isp_info_proc_fops` content under the subdev's
own name `isp-m0`. `thingino-diag` reads `isp-fs`, `isp-m0`, and `isp_info` to
cover both.

## isp-w02 raw frame dump

The VIC node is the one used to grab a single pre-ISP (Bayer) frame. In the
open T30 tree (`videoin/tx-isp-vic.c`):

- **Read** returns `vic_frd_c`, incremented on the "vic frd" interrupt
  (`0x10000` in the pending status) — a frame-drop/frame-received counter.
- **Write** (`isp_vic_cmd_set`) recognizes `snapraw`: it allocates a buffer
  from the private ISP memory region, programs the VIC DMA for one frame,
  waits on the frame-done completion (`0x1<<26`), writes the frame to
  `/tmp/snap.raw`, and frees the buffer. The argument after `snapraw` is
  ignored in the T30 implementation.

Newer generations' binary modules also honor `saveraw 1`, which self-buffers
and writes `/tmp/snap*.raw`. The two commands differ in where the DMA target
buffer comes from; on T30 only `snapraw` exists and it requires the `ispmem=`
bootarg reserve.

Callers in the tree:

- `overrides/thingino-raptor/rvd/rvd_ctrl.c::bayer_snapraw_grab()` writes
  `snapraw 0` (T40/T41), `snapraw 1` (T30), or `saveraw 1` (others), then
  waits for `/tmp/snap*.raw`.
- `package/thingino-webui/files/www/x/image.raw` does `echo snapraw 0` and
  `echo saveraw 1`, then serves `/tmp/snap0.raw`.

## Memory model

`tx-isp-videobuf.c` manages a private ISP memory region (`isp_malloc_buffer` /
`isp_free_buffer`) carved out of the `ispmem=` bootarg. The T30 README
documents the LDC memory cost:

```text
mem = width * height * (isp_m1_bufs + isp_m2_bufs) * 1.5
```

`libimp` additionally writes its allocator report to
`/tmp/continuous_mem_info` (read by `thingino-diag`); that file is produced by
the blob, not the open driver.

## Module parameters

The driver is loaded as `tx_isp_<soc>` from `/etc/modules.d/20-isp`
(generated by `package/ingenic-sdk/ingenic-sdk.mk`). Parameters vary by
family; the T30 set (from the ISP README) is:

```text
ispw isph isptop ispleft                -- ISP input crop window
ispcrop ispcropwh ispcroptl             -- ISP crop enable/size/origin
ispscaler ispscalerwh                   -- MSCALER enable/size
isp_m1_bufs isp_m2_bufs                 -- LDC in/out buffer counts (default 2)
ispmem                                  -- private ISP memory region
```

## Sensor proc tree

`common/sensor/common/sensor-info.c` creates `/proc/jz/sensor/<name>/` with
read-only entries: `name`, `chip_id`, `version`, `min_fps`, `max_fps`,
`i2c_addr`, `width`, `height`, `rst_gpio`, `pwdn_gpio`, `boot`, `mclk`,
`video_interface`, `i2c_adapter`. The `sensor` command line tool aggregates
this for diagnostics.

## Related

- [Ingenic media stack](ingenic-media-stack.md) — stack overview and layer map
- [Ingenic SDK versions](ingenic-sdk-versions.md) — where each SoC's
  driver/sensor/IQ lives
- [libimp userspace](libimp-userspace.md) — the userspace side of the ioctl
  surface
