# T41 (XBurst2) 7.2.11 port — handoff

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
| Kernel tree (build, patched) | `/home/paul/output/feature/kernel-7/wyze_cam4_t41nq_os04d10_atbm6062s-7.2.11-uclibc-192.168.88.141/build/linux-7.2.11` |
| Camera | `wyze_cam4_t41nq_os04d10_atbm6062s`, SoC T41NQ, 16 MiB SPI NOR (zb25vq128, 64 KiB blocks, 4 KiB sectors), 128 MiB DRAM |
| DTS | `configs/cameras/wyze_cam4_t41nq_os04d10_atbm6062s/wyze_cam4_t41nq.dts` |
| Kernel fragment | `board/ingenic/xburst2/kernel/7.2.11/t41.generic.config` |
| Patches | `package/all-patches/linux/7.2.11/` (0001–0117; 0102 fixed, 0113–0117 new) |
| Console capture | `~/screen-sessions/screenlog-*.txt` (older sessions) |
| Camera root password | image default `root`; first login forces a change |

```bash
CAMERA=wyze_cam4_t41nq_os04d10_atbm6062s IP=192.168.88.141 make br-linux-rebuild
CAMERA=... IP=... make pack
scripts/qemu-dev up wyze_cam4_t41nq_os04d10_atbm6062s --no-wait   # QEMU check, log in /run/user/1000/thingino-qemu-dev/<camera>/uart1.log

# DFU (camera in bootrom; expect a108:c309 "bootrom T41NQ")
OUT=/home/paul/output/feature/kernel-7/wyze_cam4_t41nq_os04d10_atbm6062s-7.2.11-uclibc-192.168.88.141
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
  - Wi-Fi is SDIO-attached (ATBM6062S), but the SDIO host does not register.
    The DTS declares the MSCs as `ingenic,sdhci` while 7.2.11 has no such
    driver (`CONFIG_MMC_SDHCI` is off, only `jz4740_mmc` is built). Port the
    SDHCI-based T41 host (or the vendor's MMC block) and set `lssdio`.
  - USB: the DWC2 core now probes (see below), but the PHY is not usable yet.
- Camera stack: OS04D10 sensor + open-tx-isp on this SoC, ATBM6062S Wi-Fi,
  audio. `timpsd` starts and stops there.
- SMP (secondary cores; the per-CPU OST pages are already described by the
  DT).

## USB (attempted, blocked)

The controller/CGU side is sound: with the CGU as `simple-mfd`, a
`usb-phy@3c` child and the DWC2 node wired to it, `dwc2` probes in both
host and peripheral mode, registers 9 endpoints / SPRAM in gadget mode,
and the userspace creates `usb0`. In host mode `lsusb` shows the root hub
(`1d6b:0002 ... DWC OTG Controller`).

The T41 CPM USB map differs from the T31's: USBPCR 0x3c, USBRDT 0x40,
USBPCR1 0x48, OPCR 0x24 (bit 7 SPENDN0, bit 23 PHY gate), **SRBC 0xc4**
(the T31 uses 0x34), and the UTMI block at 0x10060000. Reusing the
mainline `phy-ingenic-usb` T-series path is wrong for these offsets.

What blocks it: every write that changes the PHY state - USBPCR bit 31
(host mode) or the USBPCR1 D+/D- pulldown bits 28/29 - stalls the AHB and
hangs the boot. The vendor BSP sequence does exactly these writes, so
something it assumes (PHY power/clock, or a bootloader handshake) is
missing on this board. `__raw_*` instead of `writel`/`readl` did not help;
clearing OPCR bit 23 (PHY gate) first did not help; moving the init into
the DWC2 `phy_init` chain did not help. The no-op PHY variant boots and
probes the DWC2, but the host then sees no device and the port loops on
"Overcurrent change detected".

The port is a powered device port (the bootrom DFU uses it), so USB
gadget/ECM is the plausible use; host mode additionally needs VBUS. The
next step is the vendor `ingenic,innophy` driver (usb_phy API, CPM syscon
plus the 0x10060000 UTMI block) or finding the missing PHY power/clock
sequence, not the mainline T-series PHY path. The camera was restored to
the last known-good image (f148de734) after these experiments.

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

The patch series was applied to `linux-7.2.11.tar.xz` and the result matches
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
