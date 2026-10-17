# Session Handoff - Thingino kernel 7.1.13 (cinnado_d1_t31l)

Branch: `feature/kernel-7.1`
Camera: `cinnado_d1_t31l_sc2336_atbm6031` (T31L, SC2336, ATBM6031)
Devices: `192.168.88.116` (this branch, flashed, online on wlan0)
         `192.168.88.109` (reference unit, 3.10.14 vendor kernel, sensor works)
         `192.168.88.128` (the IP used for `make ... IP=...` / DFU)

## 1. Where the branch stands

Kernel 7.1.13 built from the official kernel.org tarball plus one cumulative
patch (`package/all-patches/linux/7.1.13/0001-linux-7.1.13-to-thingino.patch`)
and the numbered follow-ups in the same directory.

**The SC2336 is now detected and streaming at the sensor level.** The sensor
driver probes, the chip id reads back correctly (`0xcb3a`), registration
publishes the subdev, and `s_stream(1)` writes the init array successfully.
The streamer (`timpsd`) still cannot initialise because libimp's
`IMP_System_Init` needs the AVPU encoder device, which 7.1.13 does not
provide yet. That is a separate driver port (see 5).

Committed before this session:

- `b84650112` toolchain: 7.1: standardize the kernel version and select the
  local SDK (7.1-rc1 -> 7.1.0-rc1 then the 7.1.13 rework).
- `dd9e0ccb3` linux: 7.1 t31: take the rootfs/data layout from the U-Boot
  mtdparts (mtdparts id must be `spi0.0`, not `jz_sfc`/`spi1.0`).
- `429d3879e` uboot: add a `nuke` macro (also carries a `loadaddr` bump to
  `0x81000000`).
- `73a98f15c` linux: 7.1 t31: enumerate the ATBM6031 SDIO card on mainline
  `jz4740_mmc` (the SDIO fix, see 2).
- `635fd961b` wifi: silence the boot-time warnings on 7.x (see 3).
- `bc75c43ec` docs: kernel 7.1.13 handoff.

Uncommitted (new this session):

```
0013-clk-ingenic-t31-fix-pll-od-mapping-and-divider-handshake.patch
0014-i2c-jz4780-select-x1000-profile-for-t31.patch
0015-pinctrl-ingenic-allow-t31-shadow-window.patch
0016-misc-add-ingenic-rmem-device.patch
```

Uncommitted (intentionally):

- `configs/cameras/cinnado_d1_t31l_sc2336_atbm6031/cinnado_d1_t31l_sc2336_atbm6031_defconfig`
  has `BR2_ISP_PRINT_LEVEL_0=y` - a **debug** setting used to see the ISP /
  sensor `ISP_INFO` lines. Revert to the t31 default (drop the line) when the
  pipeline work is done.

Patch series in `package/all-patches/linux/7.1.13/`:

```
0001 linux-7.1.13-to-thingino        (big cumulative patch)
0002 mips: only build FIT image for generic kernel
0003 dt: thingino-t31 match sfc layout
0004 mtd: mtdblock avoid blk-mq sched init hang
0005 spi-ingenic-sfc bound sr-end poll
0006 pinctrl-ingenic add t31 mmc1 sdio pins
0007 dt: thingino-t31 add isp node and msc1 pinctrl
0008 dt-bindings: pinctrl-ingenic compat shim
0009 mmc: jz4740 honour ingenic,sdio-clk
0010 mmc: jz4740 sdio-clk debug       <-- debug patch, drop when done
0012 pinctrl: ingenic: register t31 gpio banks   (0011 is a numbering gap)
0013 clk: ingenic: t31: fix PLL OD mapping and divider handshake
0014 i2c: jz4780: select the X1000 profile for T31
0015 pinctrl: ingenic: allow the T31 shadow window
0016 misc: add the Ingenic rmem device
```

## 2. SDIO / WiFi (done)

The vendor Ingenic `ingenic_mmc` driver was ported but **hard-locked the SoC
on kernel 7.x** (`mmc_add_host` -> `mmc_power_up` -> `usleep_range` never
returned; the scheduler clockevent died; reproduced only when the vendor host
registered). It was dropped. The branch uses the **mainline `jz4740_mmc`**.

Root cause of the original SDIO failure: the ATBM6031 needs **~7-9 s after
power-on** before it answers CMD5. The vendor 3.10 board hid this behind a
userspace manual insert at ~7.4 s; a boot-time `non-removable` scan fails
with OCR 0 (`no support for card's volts`, `error -22`).

Fix (in the camera `.dtsi`, `&msc1`): keep the module in **poll mode** so the
core retries every second and the card registers at ~9 s:

```
&msc1 {
	status = "okay";
	pinctrl-names = "default";
	pinctrl-0 = <&msc1_pb>;
	ingenic,sdio_clk = <1>;
	max-frequency = <24000000>;
	broken-cd;
};
```

MSC1 has no `dmas` in the SoC dtsi (nor in the vendor tree), so the driver
prints `Failed to get dma_tx channel` and falls back to **PIO** - expected.
Do **not** "fix" this with `post-power-on-delay-ms`: it runs as a synchronous
sleep in the MMC probe at ~0.06 s and would stall the whole boot ~8 s.

## 3. WiFi warnings (done)

- `S36wireless` waits on `/sys/class/net/$IFACE/wireless` instead of grepping
  `/proc/net/wireless` (dropped the wext-deprecation warning).
- `package/wifi-atbm6031/0003-mac80211-use-eth_hw_addr_set.patch`: the
  vendored mac80211 sets `dev_addr` with `eth_hw_addr_set()` (fixes
  `Incorrect netdev->dev_addr` + `WARN dev_addr_lists.c:657`).
- `BR2_PACKAGE_WIRELESS_REGDB` is selected by the `BR2_PACKAGE_WIFI` menu
  (installs `/lib/firmware/regulatory.db`; fixes `failed to load
  regulatory.db`).

## 4. SC2336 (fixed)

The original symptoms were `sensor_detect` returning `-EIO` and the chip id
reading `0x00`. Three independent kernel bugs were found by comparing live
registers with 0.109 and by tracing libimp.

1. **PLL OD model was off by one (patch 0013).** `t31_pll_od_encoding` mapped
   register value N to divider N+1, so VPLL (0x0640510D) was computed as
   800 MHz instead of 1200, MPLL 750 instead of 1000 and APLL 672 instead of
   1008. `clk_set_rate(cim, 24 MHz)` therefore selected VPLL/34 = 35.3 MHz.
   The table now maps N -> N, yielding VPLL 1200 / MPLL 1000 / APLL 1008.
2. **The CIM/ISP/RSA dividers lacked the CE handshake (patch 0013).** T31
   uses CE bit 29, busy bit 28, stop bit 27. Without them `clk_set_rate()`
   updated the register but the hardware kept the bootloader ratio; the
   sensor MCLK stayed at 35.3 MHz. The 24 MHz divider is 50 (CIMCDR 0x31).
3. **T31 pinctrl never applied any mux (patch 0015).** The regmap access
   table only allowed 0x0000-0x2ffc, so writes to the PZ shadow window at
   0x7000 (GID2LD at 0x70f0) were rejected. `ingenic_shadow_config_pin()`
   failed silently. I2C0 PA12/13 stayed on the bootloader's function 2
   instead of function 1.
   Correction to the previous handoff: the PAT set/clear registers at
   0x34/0x38/0x44/0x48 are write-only (reads return 0), the real PAT0/PAT1
   are at 0x30/0x40, and the `tx-isp: T31 pinmux` line never appears because
   `pr_info` is compiled out under `TX_ISP_T31_NO_TRACE` - not because the
   call did not run.
4. **The I2C controller bound the wrong profile (patch 0014).** The DT lists
   `ingenic,t31-i2c` with a jz4780 fallback, so the driver used the 16-byte
   FIFO and the STPHLD/stop-hold path instead of the T31's 64-byte FIFO and
   X1000 SDA-hold register. Reads worked; the sensor init write array timed
   out (`write wait timeout`) and the adapter never disabled cleanly.
5. **`/dev/rmem` was missing (patch 0016).** libimp's `IMP_Alloc` mmaps the
   reserved rmem region through `/dev/rmem`. The cmdline already reserves
   `rmem=22M@0x2a00000` (outside `mem=42M`), but 7.1.13 has no rmem driver.
   Without it `IMP_Alloc` reports `alloc init failed`, `IMP_ISP_AddSensor`
   fails after a successful registration, and the streamer never starts.
   The new misc driver maps the pfn passed as the mmap offset with an
   uncached mapping; the region stays reserved by the boot argument.

Verified on .116 after a kernel-only OTA:

```
vpll 1200000000  mpll 1000000000  apll 1008000000
cim 24000000 (enabled)
sc2336 chip found @ 0x30 ... v = 0xcb / 0x3a
sc2336 s_stream(1): enter, data_interface=1
sc2336 s_stream: stream_on write_array ret=0
```

I2C0 PA12/13 are now function 1 and `/dev/rmem` exists.

## 5. OPEN: AVPU encoder (`IMP_System_Init`)

`timpsd` now gets past `IMP_ISP_AddSensor` and `IMP_ISP_EnableSensor`, then
fails with:

```
AL_Board_Create failed
[HAL_ING] IMP_System_Init busy, retry ... (ISP still releasing?)
[HAL_ING] IMP_System_Init failed after 5 tries
```

`AL_Board_Create` (libimp) opens `/dev/avpu` through its device pool. The
vendor 3.10 kernel provides it; 7.1.13 does not. The vendor T31 AVPU driver
sources are already in the open-tx-isp tree:

```
external/ingenic-sdk/4.4.94/avpu/t31/
```

Port facts gathered:

- Base `0x13200000`, size `0x100000`.
- IRQ 70 (`IRQ_HELIX0`: `IRQ_INTC_BASE` 8 + 62).
- Clocks: `el150` (mainline CGU mux/div/gate; vendor calls it
  `div_el150`/`mux_el150`/`gate_el150`) and `ahb1` (gate). Vendor default
  rate 440 MHz; the 3.10 clock tree actually runs the VPU at 400 MHz
  (VPLL/3). Use `clk_set_rate(el150, 400000000)`.
- The driver already has an OF match (`t31,avpu`) but also registers a
  hardcoded platform device (base, IRQ 70). Clock lookup by name needs a DT
  node with `clocks`/`clock-names`, or a clkdev alias.
- 4.4 -> 7.1 API fixes: `devm_ioremap_nocache` ->
  `devm_ioremap`; `vma->vm_flags |=` -> `vm_flags_set()`;
  `dma_cache_sync()` is gone (the flush ioctl can be a no-op for coherent
  DMA buffers); `class_create(THIS_MODULE, ...)` ->
  `class_create("...")`; `clk_enable()`/`clk_disable()` inside
  `avpu_ip.c` need prepared clocks (`clk_prepare_enable()` in probe).
- The T31 INTC in the mainline tree only instantiates **two** chips
  (`intc_2chip_of_init`, 64 IRQs). IRQ 70 is in the third bank. Add a
  3-chip init for `ingenic,t31-intc`, and widen the DT reg from `0x50` to
  at least `0x60` (use `0x1000`).
- Rootfs headroom is only ~20 KB (rootfs 4588/4608 KB, data 704 KB). The
  production ISP module already lives there; the AVPU `.ko` may not fit
  without freeing space or moving a partition boundary.

Suggested next steps:

1. Add the irqchip 3-chip support for T31 and the DT reg fix.
2. Port the AVPU driver as a module (ideally under the open-tx-isp module
   build) with the clock/API fixes above, plus a DT node or clkdev aliases.
3. Load it and confirm `/dev/avpu`, then `IMP_System_Init` reaches
   `IMP_ISP_EnableTuning` and frames flow.
4. Only then chase the recurring tx-isp trace (5) if it still appears.

## 6. Debug techniques that worked

- Compare live registers with .109 (`devmem` at CPCCR/VPLL/MPLL/CIMCDR/
  ISPCDR/CLKGR/GPIO PAT0/PAT1, shadow window), and read the vendor clock
  tree on .109:
  `cat /proc/jz/clock/clocks` (vpll 1200, mpll 1000, apll 1008, cgu_cim 24).
- The open-tx-isp module trace is off by default (`TX_ISP_T31_NO_TRACE`);
  `pr_info` is compiled out. For diagnosis, build it with
  `TX_ISP_T31_TRACE=y` and load the resulting `.ko` from `/tmp` after
  `rmmod` of the production modules (`t31_runtime_trace=1`). Do **not**
  ship that module: it is ~218 KB larger and does not fit the 704 KB
  data partition; it is not in the current build.
- libimp logs its own errors to stdout, which timpsd discards when it
  daemonizes. An `LD_PRELOAD` shim overriding `daemon()` and setting
  `stdout` to line buffered exposes messages such as
  `AL_Board_Create failed` and the allocator errors.
- `i2cdetect -y 0` quick-write is unreliable while the bus is float; use
  `i2cdetect -y -r 0` or a targeted `i2ctransfer`.

## 7. Cosmetic / expected (do not chase)

- `jitterentropy: Initialization failed with host not compliant` - benign
  early-boot RNG health check.
- `no support for card's volts` / `error -22` / `Card stuck being busy` -
  expected SDIO NAKs during the ~9 s settle (see 2).
- `Failed to get dma_tx channel` + `Using PIO, 1-bit mode` on mmc1 - MSC1 has
  no DMA channels anywhere; PIO is correct.
- `Send INSERT to MMC1` -> `No endpoint for MMC1` - mainline has no vendor
  `present` sysfs; harmless now that `broken-cd` polls. Could be trimmed from
  `S36wireless`.
- `Unknown kernel command line parameters "rmem=22M@0x2a00000"` - mainline
  has no `rmem=` parser; the region is already kept out of the kernel by
  `mem=42M`, and patch 0016 only exposes the device.

## 8. Build / run

```sh
# toolchain (only this one; the dir was renamed with the kernel bump)
export PATH=$HOME/thingino/toolchain/mipsel-thingino-linux-uclibc_sdk-buildroot-k7.1.13/bin:$PATH

# full build + flash
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.128 make

# kernel-only rebuild (re-preps + re-applies patches via BR2_LINUX_KERNEL_PATCH)
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.128 make rebuild-linux

# output tree
#   ~/output/feature/kernel-7.1/cinnado_d1_t31l_sc2336_atbm6031-7.1.13-uclibc-192.168.88.128/

# kernel-only OTA to the device at .116 while reusing the .128 output tree
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.116 \
    THINGINO_OUTPUT_DIR=$HOME/output/feature/kernel-7.1/cinnado_d1_t31l_sc2336_atbm6031-7.1.13-uclibc-192.168.88.128 \
    make ota-kernel

# U-Boot: `nuke` (sf probe; sf erase 0 10000; reset) re-enters DFU
```

- `patch 0013` and the `IMDBG` instrumentation from the vendor-driver
  debugging were removed in the previous session; do not reintroduce them.
- `CONFIG_DEBUG_ATOMIC_SLEEP` / `CONFIG_DEBUG_SPINLOCK` in
  `board/ingenic/xburst1/kernel/7.1.13/t31.generic.config` are back to
  "not set".
- `.109` runs 3.10.14 and is the behavioural reference; `/sys/module/...`,
  `devmem` at CPCCR/VPLL/MPLL/CIMCDR/ISPCDR/GPIO-port-A all read on both
  units.
