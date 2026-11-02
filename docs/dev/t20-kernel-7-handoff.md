# Session Handoff - Thingino kernel 7.3.1 on the T20 Wyze Cam 2

> Originally written against 7.2.11 and updated for the 7.3.1 bump. The
> runtime results below were collected on 7.2.11.

Branch: `feature/kernel-7`
Camera: `wyze_cam2_t20x_jxf23_rtl8189ftv` (T20X, JXF23, RTL8189FTV)
Device: `192.168.88.125` (flashed, online)
Serial console: **`/dev/ttyUSB0`** at 115200 (the older notes said `ttyUSB1`;
that is the second adapter, not this camera).
Reference: 3.10.14 vendor image and worktree (`/home/paul/thingino/firmware/feature-k7-ciao`)

## 1. Where the branch stands

The 7.3.1 kernel now brings the JXF23 up all the way to a working ISP
stream on the T20:

- the mainline jxf23 driver probes at `1-0040` and reads chip ID `0f23`;
- the tx-isp bridge attaches that subdev and the ISP acquires it;
- the VIC captures and the ISP runs (AE/AWB statistics move, the day
  mode is applied, the fps set returns 0);
- `/proc/jz/isp/isp-m0` reports a live sensor and ISP stream.

The remaining blocker is **timpsd**: it segfaults in `libimp.so`
(`si_addr=0xb74`) right after `ISP up`, before the RTSP listener opens.
The kernel stays alive; the S95timps supervisor respawns it every 5 s.
The crash is in the userspace IMP frame-source/encoder bring-up, after
the ISP is already streaming.

## 2. Root cause of the original sensor NACK (fixed)

The sensor NACKed every I2C transaction because it had **no MCLK**.
On the T20 the CIM MCLK is PA15, function 1. The mainline pinctrl sets
a device function only for pins in a group; the T20 table only had
`cim-data-10bit` (PA0-9), so PA15 stayed in GPIO mode (MSK=1) and the
24 MHz CIM clock never reached the pad. The 3.10 vendor kernel muxes
PA15 explicitly in its board init.

Fix: `0053-pinctrl-ingenic-add-t20-cim-pins.patch` adds `cim-pclk`
(PA14), `cim-mclk` (PA15) and `cim-sync` (PA16/17), and the sensor dtsi
pulls in all four groups.

## 3. Fixes on the branch

Kernel:

- `0053` (new, replaces the parked `.disabled`): the T20 CIM pin groups.
- `0052` (updated): the jxf23 driver now uses the **T20 DVP init
  sequence** for a parallel endpoint (PLL 0x10=0x48, 500 ms after
  0x48=0x85, then 0x48=0x05/0x1f/0x99/0x9b/0x12=0x00), writes
  0x12=0x40 on stream off, and keeps the T31 MIPI path unchanged.
- `configs/sensors/t20/jxf23.dtsi`: 100 kHz I2C (the old 18 kHz value
  was a wrong PCLK assumption), all CIM groups.

open-tx-isp (recovered vendor T20 driver):

- `0018` (regenerated): the ISP/CSI clocks are requested by their
  mainline CGU names (`isp`, `mipi_csi`), not the vendor names.
- `0019` (new): the dma-buf/vb2 7.3 adaptation that used to exist only
  as a manual build-tree edit (`.vmap`/`iosys_map`, `vm_flags_set`,
  `DEFINE_DMA_BUF_EXPORT_INFO`).
- `0020` (new): the mainline sensor bridge and the rest of the bring-up:
  - `driver/t20/tx_isp_t20_v4l2_sensor.c` finds the mainline subdev on
    the I2C bus, presents the vendor `tx_isp_sensor` ABI (DVP 10-bit,
    BGGR, vendor gain LUT) and forwards s_stream / AE ioctls to the
    mainline driver's controls;
  - the video-in register path prefers the bridge and keeps the real
    bus/address in the sinc registry;
  - the ISP IRQ is mapped through the INTC domain (`T20_ISP_IRQ` is a
    hwirq; a raw `request_irq(29)` lands on a GPIO irqchip line);
  - the ISP and CSI clocks stay enabled for the module lifetime (the
    streamer can reach STREAMON without the pipeline prepare, and
    `clk_disable_unused` has already gated the boot state);
  - the image tuning device uses `v4l2_fh`;
  - the `/proc/jz` files use `struct proc_ops` and the tree is created
    under `/proc/jz` (not `/proc/isp`);
  - the tuning controls are forwarded to the vendor
    `isp_core_ops_s_ctrl/g_ctrl` directly, because 7.3 removed the
    subdev `s_ctrl`/`g_ctrl` ops and the core subdev has no ctrl handler.

## 4. Verified on 7.3

- `jxf23 1-0040: chip id 0f23`; MCLK toggles on PA15; `i2cdetect` shows
  the sensor at 0x40.
- `tx_isp: Registered sensor subdevice jxf23` via the bridge.
- `/proc/interrupts`: `INTC 29 isp` counts frame interrupts (hundreds per
  stream).
- `/proc/jz/isp/isp-m0`: SENSOR NAME jxf23, ISP Runing Mode Day, live
  integration time/gain/WB; ISP OUTPUT FPS 25/1.
- timpsd: `sensor fps: requested 25, driver holds 25/1, set rc=0` and
  `ISP up, sensor=jxf23 fps=25`.

## 5. Remaining: timpsd segfaults in libimp

`/var/run/timps.crash`:

```
*** timpsd FATAL: SIGSEGV si_addr=0x00000b74 pc=0x77d1e590
```

The fault is in `libimp.so` (userspace), after the ISP is up and the
tuning open succeeded. The kernel is fine. The supervisor respawns
timpsd every 5 s; each attempt streams for under a second and releases
the sensor.

Next step: debug the IMP frame-source/encoder bring-up that runs after
`ISP up` (the next libimp calls after the ISP is opened), or compare
against the 3.10 image's prudynt path. The frame-channel ioctl ABI of
the recovered 3.10 driver may not match the newer libimp in this rootfs.
If that is the case, either adapt the frame-channel ABI or switch the
T20 7.3 config to a streamer that matches the driver.

## 6. Build and flash

7.3 worktree: `/home/paul/thingino/firmware/feature-k7`

```bash
CAMERA=wyze_cam2_t20x_jxf23_rtl8189ftv IP=192.168.88.125 \
    make rebuild-linux          # clean kernel + DT, re-applies patches
CAMERA=wyze_cam2_t20x_jxf23_rtl8189ftv IP=192.168.88.125 \
    make rebuild-open-tx-isp    # clean ISP module
CAMERA=wyze_cam2_t20x_jxf23_rtl8189ftv IP=192.168.88.125 make fast
CAMERA=wyze_cam2_t20x_jxf23_rtl8189ftv IP=192.168.88.125 make ota
# kernel/DT only:
CAMERA=wyze_cam2_t20x_jxf23_rtl8189ftv IP=192.168.88.125 make ota-kernel
```

3.10 reference image/worktree:

```bash
cd /home/paul/thingino/firmware/feature-k7-ciao
CAMERA=wyze_cam2_t20x_jxf23_rtl8189ftv IP=192.168.88.125 make ota
```

Images:

```
/home/paul/output/feature/kernel-7/wyze_cam2_t20x_jxf23_rtl8189ftv-7.3.1-uclibc-192.168.88.125/
/home/paul/output/ciao/wyze_cam2_t20x_jxf23_rtl8189ftv-3.10.14-uclibc-192.168.88.125/
```

## 7. Traps

- A clean kernel build needs `make rebuild-linux` (dirclean + re-patch);
  `linux-rebuild` reuses the tree and does not re-apply patches.
- The open-tx-isp source must be changed through the package patches,
  not the build tree; a clean build drops build-tree edits.
- `T20_ISP_IRQ` (29) is an INTC hwirq. Request it via the INTC domain;
  raw `request_irq(29)` hits a GPIO irqchip line on 7.3 because the
  GPIO domains allocate low virqs.
- The ISP/CSI gates are closed by `clk_disable_unused` at boot. Do not
  rely on the pipeline prepare to open them; it is skipped on some
  streamer paths.
- The 7.3 V4L2 core requires `v4l2_fh` on video devices and rejects the
  old `file_operations` layout for proc files. Both bit this driver.
- The 7.3 subdev core ops no longer have `s_ctrl`/`g_ctrl`; use the
  vendor `isp_core_ops_*` functions directly.
- The serial console for this camera is `/dev/ttyUSB0`.
- If the streamer enters a panic loop (a bad proc/ABI), catch a boot
  window over SSH and `mv /etc/init.d/S95timps /tmp/` before 31 s.

## 8. Debug techniques that worked

- `/tmp/memtool` (static mipsel, /dev/mem mmap): `read`, `write`, `poll`
  and `sample ADDR COUNT BIT` (pad sampling detected the 24 MHz MCLK and
  the UART edges).
- `I2C_TXABRT` (`0x10050080`) latched `0x01000001` for the original
  failure: bit 0 = 7-bit address NACK.
- Force `CLKGR0` bits open with memtool to prove whether a block is
  clocked: the VIC writes only stick with bit 23 cleared.
- The kernel oops EPC resolves with `addr2line` against the build
  `vmlinux`; `/var/run/timps.crash` carries the userspace fault.
- The 3.10 kernel's `/dev/mem` I2C reads return 0x6; GPIO/CGU reads work.
