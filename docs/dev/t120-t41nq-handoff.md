# Noorio T120 (T41NQ / GC8613) — session handoff

Date: 2026-11-06
Branch: `feature/kernel-7` (HEAD `a5665a215`)
Board: `noorio_t120_t41nq_gc8613_aic8800d`, 32 MB SFC NOR, 128 MB RAM
Console: serial only — screen session `3040439` on `/dev/ttyUSB2` (attached); WiFi is disabled.

## What changed

Committed this session:

- `d871d9a9c` t41: bring up clocks/timers, SFC + SPI bus 0, mainline pinctrl/GPIO,
  MSC clocks, and the stock board wiring (GPB29 SD power, GPB26 CD).
- `595e7181f` uboot: 2026.10 stable, regenerated patch against the official
  v2026.10 tarball; noorio T120/T110, Wyze Cam v4 T41NQ, Cinnado D1 T32LQ switched.
- `111422584` t41: removed the kernel `mmc0_pwrseq` (GPB29 conflict), enabled the
  T41 efuse (+CGU clock), converted OTG/PHY to `snps,dwc2` + `ingenic,t41-phy`
  (AIC8800 enumerates), removed `keep_bootcon`, gated the U-Boot SD autoupdate,
  and quieted the static-GPIO-base warning.
- `a5665a215` t41: I2C buses on the mainline binding (`ingenic,t31-i2c` + CGU
  clocks). `/dev/i2c-0` appears; `sensor-info` reads the GC8613 at `0x31`,
  ID `0x03F0=0x86 0x03F1=0x13`.

Uncommitted (this sensor session):

- `configs/sensors/t41/gc8613.dtsi`: `assigned-clock-parents = <&clock T41_CLK_VPLL>`
  (stock CIM = VPLL 1,188,000,000 / 44 = 27.000 MHz; the old path selected
  APLL 1,104,000,000 / 41 = 26,926,829), and the `reset-gpios`/`powerdown-gpios`
  on GPC27 removed.
- `package/all-patches/linux/7.3.1/0136-media-gc8613-accept-the-t41-cim-xclk.patch`:
  ±1% xclk window (in case the clock still resolves to 26.93 MHz).
- `package/all-patches/linux/7.3.1/0137-media-gc8613-give-the-sensor-time-to-boot.patch`:
  `msleep(20)` → `msleep(100)` in `gc8613_power_on`.
- `package/thingino-kopt/thingino-kopt.mk`: `THINGINO_KOPT_LINUX_CONFIG_FIXUPS_SENSOR`
  now sets `CONFIG_VIDEO_<SENSOR>=m` (was `=y`) so the driver can be
  `rmmod`/`insmod` without another kernel flash. **Debug setting — revert to `=y`
  (or install the module into the rootfs) for the final image.**

## Why

The stock boot log (`themactep/ipc-firmware` commit `5cf046aa3b`) shows:

```
apll_freq = 1104000000
mpll_freq = 1400000000
vpll_freq = 1188000000
```

so the stock sensor MCLK is 27.000 MHz from the VPLL/44, not the APLL/41
(26.926829) the mainline CIM mux picked.

The stock `sensor_gc8613_t41.ko` `gc8613_reset` is a no-op stub
(`jr ra; move v0,zero`) and there is no active `gc8613_pwdn`; the T110 profile
also sets `reset_gpio: -1`, `pwdn_gpio: -1`. The stock never drives GPC27.
The stock `gc8613_read` uses a direct two-message `private_i2c_transfer`
(16-bit big-endian register, 1-byte value), not a regmap.

The mainline GC8613 driver currently probes at 16.52 s and fails:

```
gc8613 0-0031: probe at i2c 0x31
gc8613 0-0031: Error reading reg 0x03f0: -5
gc8613 0-0031: probe with driver gc8613 failed with error -5
```

while the raw `/dev/i2c-0` path (`sensor-info`) reads the same register fine.
So power/reset/GPIO/clock wiring is not the blocker; the v4l2 CCI/regmap
register access is.

## Files touched

Committed:

- `configs/cameras/noorio_t120_t41nq_gc8613_aic8800d/{defconfig,thingino.json,noorio_t120_t41nq_gc8613_aic8800d.dtsi}`
- `configs/cameras/noorio_t110_t41nq_gc4023_aic8800d/*_defconfig`
- `configs/cameras/{wyze_cam4_t41nq_os04d10_atbm6062s,cinnado_d1_t32lq_sc4336p_atbm6162u}/*_defconfig`
- `package/all-patches/linux/7.3.1/0128`–`0135`
- `package/all-patches/uboot/2026.10/0001-from-2026.10-to-thingino.patch`
- `configs/fragments/uboot/v2026-10.fragment`
- `package/thingino-uboot/{Config.in,thingino-uboot.mk}`, `Makefile`
- `board/ingenic/xburst2/kernel/7.3.1/t41.generic.config`
- `configs/common.uenv.txt`, `overlay/etc/init.d/S04hostname`

Uncommitted:

- `configs/sensors/t41/gc8613.dtsi`
- `package/all-patches/linux/7.3.1/0136-media-gc8613-accept-the-t41-cim-xclk.patch`
- `package/all-patches/linux/7.3.1/0137-media-gc8613-give-the-sensor-time-to-boot.patch`
- `package/thingino-kopt/thingino-kopt.mk`

## Commands run

- `CAMERA=noorio_t120_t41nq_gc8613_aic8800d make rebuild-linux` / `make fast`
- Kernel flashed over the serial console (WiFi OTA/scp reset the AIC8800):
  - base64 split into 1.4 MB chunks, pasted via `screen -S 3040439`,
    `base64 -d > /tmp/uImage`, `flashcp -v /tmp/uImage /dev/mtd3`, `reboot`.
  - Current `mtd3` kernel: `9f9d99f7…` (2,137,122 B; `CONFIG_VIDEO_GC8613=m`).
- U-Boot 2026.10 was boot-tested with the full image via the SD autoupdate.
- WiFi deliberately disabled to stop the AIC8800 oops:
  `rmmod aic8800_fdrv aic_load_fw`,
  `find /lib/modules -name 'aic8800_fdrv.ko' -delete` / `aic_load_fw.ko`,
  `printf '#!/bin/sh\nexit 0\n' > /etc/init.d/S40network`,
  `echo 1 > /sys/bus/usb/devices/1-1/remove`.
  This is in the data overlay; a full-image flash restores it.
- Module debug: `gc8613.ko` (16,592 B) uploaded to `/tmp`; `insmod` fails on
  `devm_cci_regmap_init_i2c`, `cci_multi_reg_write`, `cci_write`, `cci_read`.

## Open follow-ups

1. **Load the sensor module** (`/tmp/gc8613.ko` is already on the board):
   the v4l2 CCI dependency is not loaded. Check `CONFIG_V4L2_CCI_I2C` /
   `CONFIG_V4L2_CCI` (module vs built-in) and either
   `insmod`/`modprobe` the `v4l2-cci` module first or use `modprobe gc8613`
   from a proper `modules.dep`. Then `insmod` again and read `dmesg`.
2. **CCI vs stock I2C**: if the probe still fails, replace the driver's
   `regmap_read`/`regmap_write` in `gc8613_read`/`gc8613_write` with the
   stock-style direct two-message `i2c_transfer` (16-bit BE register,
   1-byte value), or switch to a plain `devm_regmap_init_i2c` with
   `reg_bits=16, val_bits=8, reg_format_endian=BIG`.
   Then the media graph / CIM / ISP path (`/dev/media*`, `/dev/video*`).
3. **AIC8800 WiFi**: `aicwf_busrx_thr` oops (`BadVA fffffff6`, epc
   `c014e8bc`) under sustained RX; it panics the board and drops every
   OTA/scp. Needs the vendor driver/USB RX bug fixed; until then the WiFi
   and the overlay disable stay.
4. **MMC**: the host probes (`ingenic-sdhci … Got CD GPIO`, `mmc0`) but no
   `/dev/mmcblk*`; verify the card is seated / CD GPB26 polarity.
5. **Rootfs is tight**: 6,602,752 / 6,619,136 bytes (16 KiB free). Adding the
   `gc8613.ko` to the rootfs needs a fresh full image and careful size.
6. **Before final**: revert the KOPT `=m` to `=y` (or keep the module and
   install it in the rootfs), commit `0136`, `0137`, the sensor dtsi and the
   KOPT change, rebuild the full image, and flash with the SD autoupdate
   (the WiFi OTA is not usable until the AIC8800 bug is fixed).
7. The uncommitted sensor changes have not been boot-verified with a working
   module load yet. The CIM parent/27 MHz change and the GPIO removal are
   in the current `9f9d99f7` kernel but the driver is not loaded.

## Progress 2026-11-06 (session 2)

Root cause of the GC8613 probe `-EIO` found and proven on hardware: the CIM
MCLK was not reaching the sensor because **PA15 was never muxed to function 1**.
`pinctrl-0` on the sensor node is the whole fix:

```
pinctrl-names = "default";
pinctrl-0 = <&cim0_vic_mclk_pa>;
```

Evidence:

- debugfs showed `pin 15 (PA15): (MUX UNCLAIMED)` before the fix.
- `sensor-info` works only because it muxes PA15 to function 1
  (`t41_mclk` = `{cdr_off 0x90, port A, pin 15, func 1}`).
- With PA15 muxed (by `sensor-info` or by hand), the *unmodified* mainline
  module probes cleanly with the boot clock value `CIMCDR = 0x8800002C`:
  `gc8613: chip id 8613`. No driver-side clock workaround is needed; an
  earlier `clk_set_rate()` experiment was reverted.
- `GPIO92` (PC28) held high by `sensor-info` is not required for the probe
  after PA15 is correct; the reset GPIO stays removed.

Worktree changes made this session:

- `configs/sensors/t41/gc8613.dtsi`: added the `pinctrl-0` above. Built into
  `marmot.dtb` (verified with `dtc`), flashed to `mtd3`, and booted:
  `uImage` sha256 `7b184915…`, 2,137,069 B (built 2026-11-06 02:33).
- Committed: `6c1228955` (sensor dtsi), `65400eac2` (0136/0137),
  `61a67ec6c` (KOPT `=m`), `92142f3c6` (this handoff).

Next blocker for `/dev/video*` / `/dev/media*`:

- The sensor now probes as a V4L2 subdev, but there is no host driver binding
  the T41 CIM/VIC/ISP (`isp@0x13300000`, compatible `ingenic,t41-isp`).
  `package/open-tx-isp` is only enabled for T41 on `KERNEL_VERSION_4`
  (`Config.in`), and there is no CIM/ISP driver in the 7.3.1 patch series.
  Bringing up video capture on T41 7.x needs that host driver ported/written.

Board state: the new kernel booted, but the console now stops at a `login:`
prompt and `root`/`root` (the configured password) is rejected — the running
`/etc/shadow` from the data overlay likely differs from the rootfs image. The
sensor module has not been reloaded since the boot, so the DT-applied `pinctrl`
still needs one confirmed probe. The old `/tmp` modules are gone (tmpfs).
Re-upload with XMODEM (`rx` on the board, `sx` on the host); see the AGENTS.md
"Serial console / file transfer" section.

## Risks / assumptions to revisit

- The CIM parent/VPLL assumption is now verified: `clk_summary` reports
  `cim 27000000` and the sensor probes. The `pinctrl-0` PA15 claim is proven
  by hand on the old DTB; the rebuilt DTB still needs one boot to confirm the
  DT-applied version.
- Removing the sensor reset/PWDN GPIO assumes the stock/T110 wiring (sensor
  reset/PWDN tied). It matched the stock module's no-op reset, but the sensor
  datasheet pins were not measured.
- The KOPT `=m` is a debug convenience; a normal release build must put the
  module in the rootfs or go back to `=y`.
- The WiFi disable lives in the data overlay and in deleted module files;
  a full-image flash or manual restore is required to bring it back.
- The board is serial-only at the moment. Use a screen session on
  `/dev/ttyUSB2` at 115200; XMODEM (`rx` on the board, `sx` on the host) is the
  fastest transfer path.
