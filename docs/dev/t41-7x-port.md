# T41 (Wyze Cam v4) Linux 7.2 bring-up

## Status

- 7.2.11 machine types and DTBs for T40/T41 are in
  (`0052-mips-ingenic-add-t40-t41-machines.patch`).
- The T41NQ SFC NOR U-Boot is trimmed to 239140 bytes and the boot
  partition is 256 KiB (`0004-t41nq-trim-uboot.patch`).
- Kernel 7.2.11 build, image packing and `mtdparts` generation work.
- QEMU `ingenic-t41` boots U-Boot, loads the kernel from `0x60000`, and
  the kernel now reaches `calibrate_delay()` with a working early console
  and the authored command line.
- Two early-boot fixes were needed to get that far:
  - `0107`: the fork's `XBurst2-MXU3.1` core reports PRID `0x00132100`
    (COMP `0x13`, IMP `0x2100`) and `cpu_probe_ingenic()` only knew the
    `0x2000` IMP for XBurst2, so it panicked with "Unknown Ingenic
    Processor ID!" in `setup_arch()`, before `arch_mem_init()` parses
    the command line and brings up the early console. The panic was
    invisible on the wire and only findable in the printk ring buffer in
    guest RAM.
  - `0108`: the same core reports Config4.IE = 3, and `decode_config4()`
    set `MIPS_CPU_TLBINV` only for IE == 2. Without TLBINV the kernel
    took the legacy `r4k_tlb_uniquify()` path, which rewrites every TLB
    entry with a 4 KiB PageMask, FTLB indices included. QEMU's FTLB
    write check rejects those with a machine check (ExcCode 24) before
    `trap_init()` has installed a vector, so the guest looped through the
    handler U-Boot left at its own exception base (0x800f8000).
- Current stop: `timer_probe: no matching timers found`, then
  `calibrate_delay()` spins on `jiffies` forever. `of_irq_init` reports
  "children remain, but no parents". Booting with the stock `lpj=`
  parameter gets past the calibration and the kernel runs the rest of
  `start_kernel()` and the initcalls -- memory, devtmpfs, NET, squashfs,
  jffs2 -- until it stalls in the crypto self-tests, which have no
  tick to complete. The next blockers are the CGU (clocks) and the
  OST/TCU (clocksource and clockevents); the T41 core INTC from `0106`
  is in place but is not binding yet.
- The fixed layout is built and packed: boot 256K, env 64K, backup 64K,
  kernel 3072K, rootfs 6144K, data 6784K. The image table and the
  U-Boot `mtdparts` agree; the camera DTS carries the matching
  `partitions` node and `/chosen/bootargs`.
- The T41 UART has the `ingenic,8250-uart` compatible and a fixed
  24 MHz / polled bring-up path.
- The T31/T20 reference image (2013.07 U-Boot, 192K boot) boots to
  userspace in QEMU. Their console path is the built-in `earlycon`
  plus `OF_EARLYCON_DECLARE(..., "ingenic,t31-uart", ...)`, the `/ext`
  24 MHz clock, and the T31 CGU/INTC/pinctrl.
- The T41 has the `ingenic,8250-uart` earlycon entry and the T31-style
  `CONFIG_CMDLINE="earlycon keep_bootcon ..."`, and with `0107` accepted
  it prints from `OF: fdt` onwards. `MIPS_CMDLINE_DTB_EXTEND` means the
  effective line is the DTS `/chosen/bootargs`, then the U-Boot
  `bootargs`, then the built-in one; the `mem=`/`console=` arguments are
  therefore printed twice, which is harmless but worth tidying.
- The 0104/0105 SCACHE experiment was negative: dropping
  `MIPS_CPU_SCACHE` from the T-series machines did not change the early
  stop, so the SCACHE was never the hang.
- The T41 core INTC is added (`0106`, four banks at 0x100, parented by
  `cpuintc`). It does not change the early stop either: the stop was the
  PRID panic and then the FTLB machine check, both upstream of the INTC.

## Fixed layout decision

The Wyze Cam v4 profile uses a fixed layout so the kernel does not need
the dynamic U-Boot `mtdparts` to find its partitions:

| partition | offset   | size   |
|-----------|----------|--------|
| boot      | 0x000000 | 256 KiB |
| env       | 0x040000 | 64 KiB |
| backup    | 0x050000 | 64 KiB |
| kernel    | 0x060000 | 3 MiB |
| rootfs    | 0x360000 | 6 MiB |
| data      | 0x960000 | 6784 KiB |
| all       | 0x000000 | 16 MiB |

The rootfs squashfs is about 4160 KiB, leaving ~1.8 MiB unused in the
rootfs partition. The data partition loses the same amount compared
with the dynamic split. The image builder and U-Boot `sf` addresses must
use the same numbers; the camera `.dts` carries the matching
`partitions` node and `/chosen/bootargs`.

## Phases

1. **Fixed layout and authored boot arguments** (layout done; console pending)
   - camera `.dts`: fixed `partitions` node, `/chosen/bootargs` with
     `console=ttyS1,115200 root=/dev/mtdblock4 rootfstype=squashfs`.
     Done, mirrored in the DTSI for the family tree.
   - image builder: pin kernel 3072 KiB, rootfs 6144 KiB, data 6784 KiB.
     Done through `KERNEL_PARTITION_SIZE_KB`/`ROOTFS_PARTITION_SIZE_KB`.
   - U-Boot env: fixed `kern_addr`/`kern_size`, `rootfs`/`data`
     addresses; no dependency on the dynamic `mtdparts`. Done; the
     kernel still has to consume the authored bootargs.
2. **Core INTC** at `0x12300000` (`ingenic,core-intc`). Required by the
   UART, SFC, MMC and the timer blocks.
3. **CGU** at `0x10000000` (`ingenic,t41-clocks`). Feeds UART
   module/baud, MMC, SFC and OST. The UART can then drop the fixed
   clock/polled scaffold.
4. **Core OST/TCU** at `0x12000000` / `0x10002000` for clocksource,
   clockevents and the watchdog.
5. **SFC v2** at `0x13440000` (`ingenic,sfc`) for the MTD partitions
   and the squashfs rootfs.
6. **Pinctrl and SDHCI MMC** (`ingenic,t41-pinctrl`, msc0/msc1) for the
   SD card and the ATBM6062S SDIO.
7. **Camera stack**: DWC2 USB/PHY, ATBM6062S WiFi (the vendor driver is
   4.4-only), OS04D10 + open-tx-isp (4.4-only for T41), internal audio
   codec, and SMP.

## QEMU

The Ingenic QEMU fork (`github.com/gtxaspec/qemu`, branch `ingenic-txx`)
has an `ingenic-t41` machine:

```sh
qemu-system-mipsel -M ingenic-t41 -m 128M -display none \
    -serial null -serial stdio \
    -drive file=thingino-wyze_cam4_t41nq_os04d10_atbm6062s.bin,format=raw,if=none,id=flash0
```

UART1 is the second serial, which is why the first `-serial` is null.
The current checkpoint is `calibrate_delay()`; the next one is the first
timer tick, then the squashfs mount and `/init`.

`scripts/qemu-dev up wyze_cam4_t41nq_os04d10_atbm6062s` boots the built
image and `scripts/qemu-dev monitor -- 'info registers'` names the
instruction the guest is stuck on. When a panic happens before the
console is up, the message is still in the printk ring buffer: dump
RAM with QMP `pmemsave` and read `__log_buf` from `System.map`.

Before the OST driver exists, `calibrate_delay()` never returns because
`jiffies` does not move. Stop at the U-Boot prompt and boot by hand with
`lpj=1000000` in `bootargs` to skip the calibration and reach the next
blocker:

```sh
scripts/qemu-dev up wyze_cam4_t41nq_os04d10_atbm6062s --uboot
scripts/qemu-dev uboot -- 'sf probe; sf read 0x81000000 0x60000 0x300000'
scripts/qemu-dev uboot -- 'setenv bootargs console=ttyS1,115200 \
    root=/dev/mtdblock4 rootfstype=squashfs init=/init mem=100M@0x0 \
    earlycon lpj=1000000'
scripts/qemu-dev uboot -- 'bootm 0x81000000'
```

## References

- Vendor 4.4 trees: `T41-1.2.6-4.4.94` and `T40-main` in the cached
  `thingino-linux` git.
- T41 DT: `arch/mips/boot/dts/ingenic/t41.dtsi`, `marmot.dts`.
- Kernel patches: `package/all-patches/linux/7.2.11/0052`, `0101`,
  `0102`.
- U-Boot patch: `package/all-patches/uboot/2026.07/0004`.
- Camera profile: `configs/cameras/wyze_cam4_t41nq_os04d10_atbm6062s`.
