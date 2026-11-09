# T41 (XBurst2) 7.3.1 port — handoff

> Originally written against 7.2.11 and updated for the 7.3.1 bump. The
> verification below was performed on 7.2.11.

State as of this session. The port **boots Thingino userspace on real Wyze
Cam 4 (T41NQ) hardware**, reaches a login prompt, keeps its overlay across
reboots and no longer resets on its own. The SPI NOR read and program paths
are fixed; what remains is the network/camera stack (MAC, USB, sensor, Wi-Fi,
audio) and SMP.

Earlier bring-up narrative (CPU/TLB, CGU, pinctrl, RTC, RNG, I2C, DMA):
`docs/dev/t41-7x-port.md`.

## Environment

| | |
|---|---|
| Worktree | `/home/paul/thingino/firmware/feature-k7` (branch `feature/kernel-7`) |
| Kernel tree (build, patched) | `/home/paul/output/feature/kernel-7/wyze_cam4_t41nq_os04d10_atbm6062s-7.3.1-uclibc-192.168.88.141/build/linux-7.3.1` |
| Camera | `wyze_cam4_t41nq_os04d10_atbm6062s`, SoC T41NQ, 16 MiB SPI NOR (zb25vq128, 64 KiB blocks, 4 KiB sectors), 128 MiB DRAM |
| DTS | `configs/cameras/wyze_cam4_t41nq_os04d10_atbm6062s/wyze_cam4_t41nq.dts` |
| Kernel fragment | `board/ingenic/xburst2/kernel/7.3.3/t41.generic.config` |
| Patches | `package/all-patches/linux/7.3.3/` (0001–0117; 0102 fixed, 0113–0117 new) |
| Console capture | `~/screen-sessions/screenlog-*.txt` (older sessions) |
| Camera root password | image default `root`; first login forces a change |

```bash
CAMERA=wyze_cam4_t41nq_os04d10_atbm6062s IP=192.168.88.141 make br-linux-rebuild
CAMERA=... IP=... make pack
scripts/qemu-dev up wyze_cam4_t41nq_os04d10_atbm6062s --no-wait   # QEMU check, log in /run/user/1000/thingino-qemu-dev/<camera>/uart1.log

# DFU (camera in bootrom; expect a108:c309 "bootrom T41NQ")
OUT=/home/paul/output/feature/kernel-7/wyze_cam4_t41nq_os04d10_atbm6062s-7.3.1-uclibc-192.168.88.141
$OUT/host/bin/thingino-dfu -l
$OUT/host/bin/thingino-dfu -i <idx> -r /tmp/flash.bin --firmware-dir $OUT/host/share/thingino-dfu/firmware
$OUT/host/bin/thingino-dfu -i <idx> -w $OUT/images/<camera>.bin --firmware-dir $OUT/host/share/thingino-dfu/firmware --reboot
$OUT/host/bin/thingino-dfu -i <idx> --erase -w <image> --reboot   # whole-flash erase first
```

DFU gotchas:
- The bootrom device can take several seconds to enumerate; poll `-l` in a loop.
- A UGREEN webcam on the same bus claims vendor id `a108`; select the c309
  entry by index, never "first a108 device".
- `-w` does **not** erase. `--erase -w` is the clean-slate path; without it
  the `data` partition keeps whatever the previous firmware wrote.
- `-r` needs `--firmware-dir` too, otherwise "loader file missing".
- The U-Boot command set is minimal (no `sf`, `mtd`, `md5sum`, `help`).
  `run nuke` erases the boot partition and resets into the bootrom DFU
  loader; that is the way to get back to DFU from Linux or U-Boot.

## Verified working on hardware

`prid=00132100`, `config4=e0fcc126` (IE=3), CGU PLLs 1104/1400/1080 MHz,
**BogoMIPS 1102**.

- Timers: `ingenic,t41-ost` global counter plus per-CPU compare timers,
  clocksource at 24 MHz, clockevent on the core's IP4. The T41 Core OST
  resets with its interrupt masked (`OSTMR` bit 0); clear it at init and
  before every `set_next`. The TCU is not a timer on this part and is kept
  only as the clock provider for the watchdog.
- Console: `ttyS1 at MMIO 0x10031000`, `base_baud 1500000`, real clocks and
  IRQ 50. The `/ext` node name matters (earlycon looks the clock up by name).
- Flash: MTD layout is correct (`spi2.0`, 6 partitions, `erasesize 0x10000`),
  squashfs mounts, init runs, overlay composes `/`.
- **Persistence:** a 256 KiB random file written to `/overlay`, `sync`ed and
  read back after a reboot keeps the same md5. No jffs2 or squashfs
  errors in the boot log.
- Peripherals: `jz4740-rtc`, `ingenic-trng`, three `jz4780-i2c` at 400 kHz,
  four gpiochips, pinctrl.
- Serial/MAC/hostname: the T41 efuse is the JZ4780/T31 controller at
  0x13540000 (the vendor T41 boot code uses CTRL 0x0 / STATUS 0x8 /
  DATA0 0xc). The node is enabled with `T41_CLK_EFUSE`, `t41-efuse` is
  bound to the T31 nvmem data (`0118`) and the driver is built in. The
  raw +0x200 window then returns the serial and the SoC-type words;
  S04hostname generates `ing-wyze-cam4-<4 hex>` (`c7a5` on this unit).
- Watchdog: counter runs from 24 MHz/512 with the TCSR prescaler; the
  userspace `watchdog -T 60 /dev/watchdog` daemon pings every ~30 s and the
  board stays up indefinitely. `TCER` bit 0 is the enable.

## Resolved: SFC data path

Symptoms were jffs2 `Magic bitmask ... not found` / `Node header CRC failed`
on the first boot after a clean erase, `Input/output error` on overlay writes
and, later, `SQUASHFS error: Failed to read block ... -EIO` panics during
boot. A full-flash DFU read showed the `data` partition contained a **valid**
node where the kernel had reported a bad CRC: the media was right and the
kernel's read was wrong.

Root causes, in the order they were found:

1. PIO data reads cannot complete on the T41: the RX FIFO threshold raises
   RREQ mid-transfer, nothing drains the FIFO, END never arrives. The driver
   timed out and fell back to DMA, but the aborted transfer leaves the
   controller in a state where the following reads return stale data. The
   fallback was removed for this part (`ingenic,t41-sfc`, `dma_only`): every
   data phase uses DMA from the first transfer.
2. DMA moved whole words into cached destinations. Even with correct cache
   maintenance the CPU could read stale lines (the failures were 4–8 byte
   holes containing unrelated kernel strings such as `/init`). All transfers
   now run through one **uncached coherent buffer** (`dmam_alloc_coherent`)
   and are copied in/out. This is slower than a direct mapping but reliable;
   an attempt to fix the cache path directly was not made.
3. The IRQ handler completed on any controller interrupt without looking at
   SR. It now completes only on END (or a FIFO error) and the DMA path
   validates `SR_END` before using the buffer.
4. The FIFO threshold was set to 63 (nearly full). The T41 now uses 32,
   half the FIFO, like the vendor driver.
5. The 256-byte op cap (fitted to PIO) is lifted for DMA parts to one page.
6. `supports_op` still rejected unaligned RX reads above 256 bytes -- the
   exact size of a JFFS2 node (389/262/275 bytes). The PIO limits are now
   gated on `!dma_only`, so those reads run through the DMA bounce buffer.
7. ~~`data.jffs2` was built with the default page size while the T41 SFC
   advertises `writesize 1`. It is now formatted with `--pagesize=1`.~~
   Reverted: `mkfs.jffs2 --pagesize` is the maximum data-node size, not the
   MTD `writesize`. Setting it to 1 emits one node per byte, which fills the
   data partition on small-flash boards. The unaligned reads are handled by
   fix 6, so the packer keeps the 4 KiB default.

Verified on hardware after a whole-flash erase: clean xattr build, zero
`xdatum`/`xref`, and 389/275/262-byte reads from `/dev/mtd5` return valid
data with no SPI or JFFS2 errors in dmesg.

## Resolved: silent resets (watchdog)

The T41 watchdog is **not** the JZ4740 one behind the TCU clock provider:

- The counter runs from a fixed **24 MHz/512 = 46875 Hz** clock.
- `TCSR` bits 5:3 are a 4^n prescaler and bit 1 selects the TCU RTC input;
  `TDR` is `rate * seconds / 4^n`.
- Writing `TCNT` does **not** reload the counter; setting `TCSR` bit 10 does.
  That is the ping.
- A bootloader-running watchdog is adopted (`WDOG_HW_RUNNING`) so the core
  keeps it alive until userspace opens the device.

The driver has an `ingenic,t41-watchdog` variant implementing this. A daemon
timeout of 60 s programs `TDR=0xABA9`, `TCSR=0x1A` and pings every ~30 s;
uptime crosses several minutes without a reset. Older builds reset after
~42 s because the daemon was started with a 60 s timeout while the hardware
counter (using the wrong rate) expired at ~42 s.

## Not started

- Networking: the board is Wi-Fi only (there is no Ethernet jack; the T41
  MAC would only matter for a USB-Ethernet adapter). `lsusb` and `lssdio`
  are both empty, so the camera is fully offline:
  - Wi-Fi is SDIO-attached (ATBM6062S). The SDHCI host is now up (see the
    MMC section); the card itself does not enumerate yet.
  - USB: device mode works (CDC-NCM, see below); host mode untested.
- Camera stack: OS04D10 sensor + open-tx-isp on this SoC, ATBM6062S Wi-Fi,
  audio. `timpsd` starts and stops there.
- SMP (secondary cores; the per-CPU OST pages are already described by the
  DT).

## MMC / SDIO

The T41 MSC is a standard SDHCI block at **0x13060000 / 0x13070000**; the
card clock comes from the CGU `T41_CLK_MSC0/1` mux+divider (MSC0CDR/MSC1CDR,
CLKGR bits 4/5) and the board carries card-detect and reset GPIOs. A thin
`sdhci-ingenic` driver on top of `sdhci_pltfm` (fixed vendor capabilities,
`mmc_of_parse()` for CD/pwrseq, the CGU clock left at its maximum so the
SDHCI divider selects the card clock) is in `0119` and builds as
`ingenic_sdhci_sdio.ko`, the name S09mmc already uses for XBurst2.

On hardware both controllers register:

```
ingenic-sdhci 13060000.msc: Got CD GPIO
ingenic-sdhci 13060000.msc: allocated mmc-pwrseq
mmc0: SDHCI controller on 13060000.msc [13060000.msc] using ADMA
ingenic-sdhci 13070000.msc: allocated mmc-pwrseq
mmc1: SDHCI controller on 13070000.msc [13070000.msc] using ADMA
mmc1: Failed to initialize a non-removable card
```

The SD slot (msc0) is up and the ATBM6062S on msc1 **enumerates**:
`mmc2: new high speed SDIO card at address 022d`, vendor `0x007a`,
device `0x6011`. The ATBM driver binds to the function and reaches its firmware/probe
path. `wlan0` is not created consistently yet: some boots report
`atbm_get_chiptype, chipver=0x0` and the probe never completes, while
manual reloads after enumeration reached `chipver=0x5a` and created
`wlan0`. This is the next Wi-Fi item.

The MSC mux defaults to SCLKA (APLL/2, 552 MHz), which the 10-bit SDHCI
divider cannot divide down to the 400 kHz identification clock. `0119`
now gates the MSC, switches the parent to EXTAL (24 MHz), and restores
`host->max_clk` before programming the divider. CCF refuses a parent
change on an enabled clock (`CLK_SET_PARENT_GATE`), hence the gate.

Switching to MPLL or VPLL after identification makes the ATBM stop
answering data commands (ETIMEDOUT on the first transfer), even at 1 MHz.
The card therefore stays on EXTAL with the CGU divider at /4 and the
SDIO card clock capped at 1.5 MHz. Higher throughput needs a glitch-free
parent switch or the vendor phase/tuning sequence.

S09mmc applies `mmc_en`, the active-low rails (`61o 59o`) and the WLAN
reset (GPIO 78), loads the host, then rebinds the ingenic-sdhci
controllers. The first host init leaves the card unable to complete the
ATBM firmware download; the rebind enumerates it again (`address 0002`)
and is the instance the driver should use.

The ATBM probe still reports `chipver=0x0` and wedges in `D` on a fresh
power-up even after the rebind, while manual tests on a card that had
been through several soft reboots reached `chipver=0x5a` and created
`wlan0`. Verbose logging (`atbm_printk_mask=0xff`) shows the failure:
`atbm_direct_read_reg_32: can't read config register` repeating with a
timeout, then `chipver=0x0` and a stall before the firmware download.
The card answers enumeration (CCCR/CIS) but not the driver's function-1
config register reads. Next step: compare against the vendor SDIO
bring-up (function enable, 32 kHz/LPO, voltage/phase) and the exact
power-up timing. ATBM loading is backgrounded so a wedged probe does not
stall boot.

Kernel-config trap: after a rebuild the output `.config` had lost
`MACH_INGENIC_SOC`/`MACH_T41` (it selected MIPS32_R1), so `MIPS` no longer
had the machine and the KOPT `MMC_SDHCI_INGENIC=m` fixup was dropped.
Always check `CONFIG_MACH_T41` and `CONFIG_MMC_SDHCI_INGENIC` after a
kernel rebuild. Do not reload a module built against a different `.config`
into the running kernel: an `insmod` of the new SDHCI module oopsed in the
old kernel (different struct layout). Flash kernel and rootfs together. The pwrseq was the wrong owner for the reset: its
active-low reset was left asserted after power-on, so the card never left
reset. msc1 now has no pwrseq; S09mmc raises `mmc_en`, drives both
active-low rails and pulses GPIO 78 (10 ms low, then high) before loading
the host. The card still reports `mmc1: Failed to initialize a
non-removable card`, so the remaining suspects are the 32 kHz LPO/pinmux
or the rail wiring, not the reset order.

The master branch runs this camera's Wi-Fi on 4.4.94 with the vendor
SDHCI and ATBM drivers. Our 7.3 port now enumerates the same card with
the mainline SDHCI core plus the T41 glue, and the ATBM driver binds to
it. Association and throughput have not been tested yet.

The working 7.x SDIO reference is the Cinnado D1 T31L (ATBM6031): it
builds the driver from the `themactep/atbm-wifi` **`kernel-7.x`** branch
with `CONFIG_CFG80211=y` and the kernel's mac80211 disabled (the driver
vendors its own), and its msc1 uses `broken-cd` polling because the ATBM
needs 7-9 s after power before it answers CMD5 - a one-shot boot scan
fails with OCR 0. The T31L is wired to PB8-11/PB13-14; the Wyze uses the
PC group (PB14 is its IR LED).

msc1 now polls (`broken-cd`) instead of scanning once, but the 6062S card
still does not appear on the T41's PC pins. The ATBM6062S package should
move to the `kernel-7.x` driver branch; that branch has no 6062S config
or firmware yet (only 6012/6031/6032/6132), so the 606x chip support has
to be brought over. The current `wifi-atbm6062s` 4.x package stays
disabled on 7.x.

The factory MMC map (master `cameras-exp`) is `mmc_en: 57` (power
enable), `mmc_power: 61 + 59 active-low` (SD and SDIO rails) and
`mmc_cd: 58`. The feature-k7 copy had only a bare `mmc_power: 61`, which
S09mmc drove high (off), and no 59; the rail was never on before the host
probe. S09mmc now raises `mmc_en` and applies the power sequence before
loading the host. The branch's `jct`/S09mmc does not parse the master's
array form, so the camera JSON uses the equivalent legacy string
`"61o 59o"`. GPIO 78 (`wlan`) is the SDIO reset (pulsed by S09mmc);
GPIO 61 is a power switch, not a reset, so the wrong msc0 `mmc-pwrseq`
is gone.

Build-system fixes that came with this: the KOPT now maps XBurst2 to
`sdhci-ingenic` on **every** kernel (the 7.x branch used to force
`jz4740-mmc` for all SoCs), `thingino-mmc` picks `jz4740_mmc` for 7.x
XBurst1 and `ingenic_sdhci_sdio` for XBurst2, and S09mmc loads
`pwrseq_simple` before the host so the pwrseq suppliers do not leave the
MSC probes deferred.

## Large ports still open (scoped)

- **Camera.** open-tx-isp ships `driver/t41` and the OS04D10 IQ blob, but
  the package marks t41 as 4.4-only: there is no `sensor-src/t41`, and
  `driver/t41` is written against the vendor ABI. A 7.x port needs the
  T41 ISP driver adapted to 7.3.1 plus an OS04D10 `sensor-src/t41`
  rewrite in the T31 7.x sensor style.
  Hardware note from a user report: OS04D10 detection is marginal across
  units and becomes reliable when PA15 drive strength is set to 2
  (T41 PDS1 bit 15, via PxPDS1S/PxPDS1C at 0x144/0x148). Apply it with
  the sensor/ISP port.
- **SMP.** `MACH_T41` has no `SYS_SUPPORTS_SMP` and the mainline tree has
  no `xburst2_smp_ops`. The vendor 4.4 code (CCU reset-entry/mailbox, the
  bounce trampoline, per-CPU IRQ/timer, `play_dead`) is the reference; the
  per-CPU OST bases are already handled by the timer patch.
- **ATBM Wi-Fi.** The driver now builds on 7.3.1: fork
  `themactep/atbm-wifi`, branch `kernel-7.x-atbm6062s` at `be198b36`,
  uses the 606x WiFi6 tree with the 7.x mac80211 stack and the cfg80211
  call sites ported (station/channel/tx-power ops, MLO disassoc helpers,
  `rx_assoc_resp_data`). The package points at that commit. The card still
  does not answer CMD5 even with the corrected rails and reset.

## USB

The controller/CGU side is sound: with the CGU as `simple-mfd`, a
`usb-phy@3c` child and the DWC2 node wired to it, `dwc2` probes in both
host and peripheral mode, registers 9 endpoints / SPRAM in gadget mode,
and the userspace creates `usb0`. In host mode `lsusb` shows the root hub
(`1d6b:0002 ... DWC OTG Controller`).

The T41 CPM USB map differs from the T31's: USBPCR 0x3c, USBRDT 0x40,
USBPCR1 0x48, OPCR 0x24 (bit 7 SPENDN0, bit 23 PHY gate), **SRBC 0xc4**
(the T31 uses 0x34), and the UTMI block at 0x10060000. Reusing the
mainline `phy-ingenic-usb` T-series path is wrong for these offsets.

What looked like an AHB stall was the **OTG clock gate**: the T41 CGU
gates the OTG block (CLKGR0 bit 3), `clk_disable_unused` turns it off, and
any USBPCR/USBPCR1 write then hangs the bus. The mainline
`phy-ingenic-usb` T-series init also wrote T31's SRBC (0x34); the T41's is
0xc4. The T41 variant (`0120`, compatible `ingenic,t41-phy`) enables the
clock, resets the OTG core through 0xc4, and only then touches the PHY.
The PHY node's `reg` must be `0x1000003c` (USBPCR), not the CPM base.

Host mode is still untested. Device mode works as a CDC-NCM gadget:
`dwc2` in `dr_mode = "peripheral"` with `maximum-speed = "full-speed"`
(the core's reset DPTXFSIZN reports 63-word FIFOs - too small for a
512-byte high-speed bulk endpoint; full-speed uses 64-byte packets and
fits). The `usbnet` NCM package starts `g_ncm`; the camera is
172.16.0.1 and a Linux host binds `cdc_ncm` and gets an `enx...`
interface (ping and SSH verified). S36cdcnet waits for the late-probing
UDC and skips the vendor `usb-role` poke on XBurst2: the mainline DWC2
owns the role through DT.

## Patch status

`0102` was rewritten to a single line (`ingenic,8250-uart` on the x1000
configuration); the previous version also deleted the `uartclk` assignment
and is what silently broke the baud rate. The new kernel work is in
`0113`–`0117`:

- `0113` sysost: T41 variant
- `0114` timer: do not register the dead TCU timekeeping
- `0115` SFC: DMA-only, coherent bounce, END validation, threshold, op size
- `0116` CGU: open the TCU and OST module/OPCR gates
- `0117` watchdog: T41 variant and boot-enabled adoption

The patch series was applied to `linux-7.3.1.tar.xz` and the result matches
the tested build tree file-for-file. The DTS and the kernel fragment
(`CONFIG_INGENIC_SYSOST=y`) are in the repo.

## Traps learned (do not repeat)

- A dead console looks exactly like a hung kernel: the T41 console was once
  gated because its DT node declared no clocks.
- Pin states must be children of the pin controller; as siblings every
  consumer silently gets `-EPROBE_DEFER`.
- `ext`/`rtc` fixed-clock node names are load-bearing (earlycon and the TCU
  clock provider look parents up by name).
- QEMU does not model the T41 core intc/watchdog and its SFC model never sets
  `SR_END`, so QEMU passing says nothing about the flash or watchdog paths.
- jffs2's "Magic bitmask ... at 0xNNN" offset is relative to the **erase
  block**, not the partition.
- A PIO transfer that is aborted mid-flight leaves the T41 SFC delivering
  stale data to later DMA transfers; never start one.
- The T41 watchdog counter is not writable through `TCNT`; pings must set
  `TCSR` bit 10.
- On the USB serial console, the host tty can get XOFF-stopped and silently
  swallow input; send `^Q` before typing (or turn screen's flow control off).
  In U-Boot the same byte becomes part of the command line.
- `screen`'s `/dev/ttyUSB*` numbering is not stable across USB re-enumeration;
  map it via `/dev/serial/by-path` or the adapter's USB port.
