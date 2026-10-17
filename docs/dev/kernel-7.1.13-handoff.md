# Session Handoff - Thingino kernel 7.1.13 (cinnado_d1_t31l)

Branch: `feature/kernel-7.1`
Camera: `cinnado_d1_t31l_sc2336_atbm6031` (T31L, SC2336, ATBM6031)
Devices: `192.168.88.116` (this branch, flashed, online on wlan0)
         `192.168.88.109` (reference unit, 3.10.14 vendor kernel, sensor works)
         `192.168.88.128` (the IP used for `make ... IP=...` / DFU)

## 1. Where the branch stands

Kernel 7.1.13 built from the official kernel.org tarball plus one cumulative
patch (`package/all-patches/linux/7.1.13/0001-linux-7.1.13-to-thingino.patch`)
and the numbered follow-ups in the same directory. The branch boots to
userspace, WiFi is up, video is not.

Committed in this session:

- `b84650112` toolchain: 7.1: standardize the kernel version and select the
  local SDK (7.1-rc1 -> 7.1.0-rc1 then the 7.1.13 rework).
- `dd9e0ccb3` linux: 7.1 t31: take the rootfs/data layout from the U-Boot
  mtdparts (mtdparts id must be `spi0.0`, not `jz_sfc`/`spi1.0`).
- `429d3879e` uboot: add a `nuke` macro (also carries a `loadaddr` bump to
  `0x81000000`).
- `73a98f15c` linux: 7.1 t31: enumerate the ATBM6031 SDIO card on mainline
  `jz4740_mmc` (the SDIO fix, see 2).
- `635fd961b` wifi: silence the boot-time warnings on 7.x (see 3).

Uncommitted (intentionally):

- `configs/cameras/cinnado_d1_t31l_sc2336_atbm6031/cinnado_d1_t31l_sc2336_atbm6031_defconfig`
  has `BR2_ISP_PRINT_LEVEL_0=y` - a **debug** setting used to see the ISP /
  sensor `ISP_INFO` lines. Revert to the t31 default (drop the line) when the
  sensor work is done.

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

## 4. OPEN: image sensor (SC2336) not detected on 7.x

Symptom (dmesg, repeating every ~5-60 s):

```
sc2336 probe: mclk cgu_cim rate=23529411 Hz, enabled
probe ok ------->sc2336
-----sensor_detect: 583 ret = -5, v = 0x00      (x5)
chip found @ 0x30 (10050000.i2c) is not an sc2336 chip.
g_chip_ident failed for sc2336: -5
```

The sensor's I2C register reads fail with `-EIO`; `i2cdetect -y 0` /
`i2ctransfer` at 0x30 also fail. The 3.10 reference unit clocks the sensor
(`mclk div_cim rate=24000000 Hz, enabled`) and streams it fine.

Code: sensor source is in the external `open-tx-isp` build tree
(`build/open-tx-isp-custom/sensor-src/t31/sc2336.c`); the chip-id check is
`sensor_detect()` (~line 578, reads reg 0x3107/0x3108) called from
`sensor_g_chip_ident()` (~line 782). The probe (~line 1012) enables the MCLK
via `private_clk_get(NULL, "cgu_cim")` and muxes the clock output with
`private_jzgpio_set_func(GPIO_PORT_A, GPIO_FUNC_1, 0x8000)` (PA15). That
helper is `driver/t31/tx_isp_core.c:4900`; on >= 5.0 it writes raw T31 GPIO
"PAT0/PAT1" registers (0x38/0x44) and prints
`tx-isp: T31 pinmux P%c mask=... function=...`.

Two concrete faults were found by comparing against 0.109:

1. **VPLL (the CIM parent) is disabled.** Register `0x100000e0`:
   `.109 = 0x0640510D` (bit0 enable + bit3 stable set);
   `.116 = 0x06405100` (disabled). CIMCDR (0x7c) has mux=VPLL.
   Note: enabling VPLL at runtime with `devmem 0x100000e0 32 0x0640510D`
   did **not** make the sensor answer, so this is necessary but not
   sufficient.
2. **The CIM MCLK output pin is not muxed.** The `tx-isp: T31 pinmux ...`
   line never appears in dmesg, and the PAT registers (0x34/0x38/0x44/0x48)
   read 0 on both cameras. So even with the CIM clock alive, 24 MHz never
   reaches the sensor (no master clock -> the sensor NACKs its I2C).

Also: the CIM rate is 23.53 MHz, not 24 MHz. CIMCDR `.116 = 0x88000021`
(mux 2 / div 33), `.109 = 0x80000031` (mux 2 / div 49). The mainline
`t31-cgu.c` CIM parents are `{ SCLKA, MPLL, VPLL }` (`SCLKA` is muxed to
APLL in CPCCR, so plain 24 MHz is not a direct parent). `clk_set_rate(cim,
24000000)` lands on 23529411 (= 400MHz/17-ish), i.e. not an exact multiple of
24 MHz. Use `0x10000000` (CPCCR), `0xe0` (VPLL), `0x7c` (CIMCDR), `0x80`
(ISPCDR), `0x20` (CLKGR) on both units for comparison.

### Suggested next steps (in this order)

1. Find the correct T31 pin-function register/layout for the sensor MCLK
   output pin (the open-ISP's PAT pokes are wrong for T31), and mux it via
   the **mainline pinctrl** (`pinctrl-ingenic` T31 data) - add a pinctrl
   state for it and reference it from the ISP/sensor path. Confirm with a
   `devmem` read-back of the pin's function.
2. Make the `cim` clock run at exactly 24 MHz: either add `EXCLK` (24 MHz) as
   a CIM mux parent in `t31-cgu.c`, or fix the parent/div so
   `clk_set_rate(24 MHz)` is exact. Verify the sensor ident read then
   succeeds (`-----sensor_detect: ... v = 0x23` for the SC2336).
3. Fix the VPLL disabled state - likely `clk_disable_unused` gating it since
   nothing references it at boot; ensure the CIM enable propagates to it.
4. Unrelated but seen: a recurring (60 s) `Call Trace` from the tx-isp module
   (raw addresses, modules not in kallsyms) - capture with `print_level=0`
   and symbolize when the sensor work resumes.

## 5. Cosmetic / expected (do not chase)

- `jitterentropy: Initialization failed with host not compliant` - benign
  early-boot RNG health check.
- `no support for card's volts` / `error -22` / `Card stuck being busy` -
  expected SDIO NAKs during the ~9 s settle (see 2).
- `Failed to get dma_tx channel` + `Using PIO, 1-bit mode` on mmc1 - MSC1 has
  no DMA channels anywhere; PIO is correct.
- `Send INSERT to MMC1` -> `No endpoint for MMC1` - mainline has no vendor
  `present` sysfs; harmless now that `broken-cd` polls. Could be trimmed from
  `S36wireless`.

## 6. Build / run

```sh
# toolchain (only this one; the dir was renamed with the kernel bump)
export PATH=$HOME/thingino/toolchain/mipsel-thingino-linux-uclibc_sdk-buildroot-k7.1.13/bin:$PATH

# full build + flash
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.128 make

# kernel-only rebuild (re-preps + re-applies patches via BR2_LINUX_KERNEL_PATCH)
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.128 make rebuild-linux

# output tree
#   ~/output/feature/kernel-7.1/cinnado_d1_t31l_sc2336_atbm6031-7.1.13-uclibc-192.168.88.128/

# U-Boot: `nuke` (sf probe; sf erase 0 10000; reset) re-enters DFU
```

- `patch 0013` and the `IMDBG` instrumentation from the vendor-driver
  debugging were removed; do not reintroduce them.
- `CONFIG_DEBUG_ATOMIC_SLEEP` / `CONFIG_DEBUG_SPINLOCK` in
  `board/ingenic/xburst1/kernel/7.1.13/t31.generic.config` are back to
  "not set".
- `.109` runs 3.10.14 and is the behavioural reference; `/sys/module/...`,
  `devmem` at CPCCR/VPLL/CIMCDR/GPIO-port-A all read on both units.
