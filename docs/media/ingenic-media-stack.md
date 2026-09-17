# Ingenic media stack

This is the index for the Ingenic camera pipeline documentation. The media
stack is the Ingenic "IMP" (Ingenic Media Platform) / "ISVP" (Ingenic Smart
Video Platform) subsystem: a kernel ISP driver plus a set of proprietary
userspace libraries that together turn sensor pixels into encoded streams.

## Layer map

```
sensor (I2C)            sensor_<model>_<soc>.ko
   |
   v
CSI-2 receiver           isp-w01 (TX_ISP_CSI_NAME)
   |
   v
Video Input Controller   isp-w02 (TX_ISP_VIC_NAME)   -- DMA into DDR
   |
   v
Apical ISP core          isp-m0  (TX_ISP_CORE_NAME)  -- 3A, tuning, image proc
   |
   v
LDC / NCU / MSCALER      isp-m1 / isp-m2 / isp-m3    -- distortion, post-proc, scale
   |
   v
Frame source             isp-fs  (TX_ISP_FS_NAME)    -- userspace capture channel
   |
   v
libimp.so (userspace)    IMP_* API
   |
   v
streamer                 prudynt / raptor
   |
   v
encoder (AVPU)           H.264 / H.265 / MJPEG
```

Kernel side and userspace side are cleanly split:

- **Kernel**: the `tx-isp` driver plus per-subdev modules. Exposes one ioctl
  miscdevice (`/dev/tx-isp`), one miscdevice per subdev that has an ops table
  (`/dev/isp-w00`, `/dev/isp-m0`, ...), and debug proc nodes under
  `/proc/jz/isp/`.
- **Userspace**: `libimp.so` (proprietary blob, or OpenIMP) drives the
  kernel nodes through ioctls and exposes the `IMP_*` API that streamers link
  against. Companion blobs are `libalog`, `libsysutils`, `libaudioProcess`.

The ISP is the Apical ISP IP core licensed into the Tomahawk SoCs; the
"apical-isp" directory in the SDK carries its calibration/tuning code.

## ISP stack providers

Thingino selects the stack through the `BR2_PACKAGE_THINGINO_ISP` virtual
package (menuconfig: `Thingino Firmware → System Packages → ISP stack`):

| Provider | Kernel driver | Userspace libimp | Status |
| --- | --- | --- | --- |
| `THINGINO_ISP_PROPRIETARY` | Ingenic `tx-isp` | Ingenic `libimp.so` | default |
| `THINGINO_ISP_OPEN` | `open-tx-isp` | OpenIMP (`libimp.so`) | experimental |

See `package/thingino-isp/Config.in` and `docs/media/open-isp-stack.md`.

## Document series

- [TX-ISP pipeline](tx-isp-pipeline.md) - kernel driver internals: subdev
  graph, miscdevices, proc debug nodes, memory model.
- [Ingenic SDK versions](ingenic-sdk-versions.md) - SoC family / kernel /
  SDK version matrix and where each artifact lives.
- [libimp userspace](libimp-userspace.md) - the `IMP_*` ABI, library set,
  neo replacements, OpenIMP, and the diagnostic tools.

## Related

- [Open ISP stack](open-isp-stack.md) — open-tx-isp + OpenIMP provider
- [Streamer](streamer.md) — prudynt RTSP/OSD/rate-control details
- [`docs/dev/glossary.md`](../dev/glossary.md) — IMP, ISVP, ISP, and platform codenames
