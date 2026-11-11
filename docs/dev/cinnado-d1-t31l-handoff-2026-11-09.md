# Cinnado D1 (T31L / SC2336 / ATBM6031) - session handoff

Date: 2026-11-09
Branch: `feature/kernel-7` (ahead of origin, not pushed)
Board: `cinnado_d1_t31l_sc2336_atbm6031`, 8 MB SFC NOR, kernel 7.3.3, OpenIMP
Device: `192.168.88.125` - up, console on serial, streaming
Last flashed image: `2ff8d2613b54928427c072acdca1a2cea5022e5bdc5d22d071b3048700265a27`
Kernel on device (2026-11-11): 7.3.3 `#9`, `uImage` md5
`d898544f8126bd4649bec90c10184daa`, no `keep_bootcon`

## What changed

Committed this session:

- `d275dde04` build: stop packing `data.jffs2` with mkfs pagesize 1
- `35d539db0` t31: drop `keep_bootcon` (later reverted in effect)
- `584775307` xburst1: drop `keep_bootcon` from the remaining 7.3.3 configs
  (later reverted in effect)
- `20f37bd5e` xburst1: restore `keep_bootcon`, the `ttyS1` handover hangs
- `61ff7c2d8` open-tx-isp: resolve the T31 sensor from DT only

Uncommitted in the tree (not this task): the `wuuk_y0510` move back to
`configs/cameras/`, `package/open-tx-isp/0045`-`0048`, `open-tx-isp.mk`,
`package/wifi/files/S36wireless.in`, `docs/dev/t120-open-stack-kickoff.md`.

## Why

### 1. New image bootlooped

`d4436d49a` added `JFFS2_PAGE_SIZE := 1` and `mkfs.jffs2 --pagesize=1`,
misreading the MTD `writesize` as the JFFS2 node size. `--pagesize` is the
maximum data-node size, so the packer emitted one node per byte:

- broken `data.jffs2`: 7172 inode nodes, data partition 640 K used / 0 free
- good 3.10 image: 33 inode nodes

`/init` could not create `/overlay/.overlay-migrated`, `mount_overlay` failed,
PID 1 exited and the board rebooted forever.

Fix: drop `JFFS2_PAGE_SIZE` and the `--pagesize` argument, keep mkfs' 4 KiB
default (matches 4 KiB kernel pages). Rebuilt image: 27 inode nodes, 112 K
payload in the 640 K partition.

### 2. Doubled console lines, then lost console

`keep_bootcon` kept the `t31_uart0` earlycon boot console alive next to
`ttyS1`, so every line printed twice. Removing it is **not** safe on this SoC:
the log stops at

```
printk: console [ttyS1] enabled
printk: legacy bootconsole [t31_uart0] disabled
```

and the board never reaches userspace (no network, no further log). This is
the historical open bug already recorded in `cinnado-d1-t31l-handoff.md`.
`keep_bootcon` was restored on all xburst1 7.3.3 configs
(`t10/t20/t21/t23/t30/t31/t32/t33`) because they all include `t31.dtsi`.
Duplicates are back and accepted until `ttyS1` is fixed.

The T41/Noorio fix (`111422584`) does not transfer: its DTS was actually wired
in `0124-mips-dts-ingenic-t41-wire-up-the-console-uart.patch` (serial1 alias,
stdout-path, `ext` node, per-UART clocks). T31 has those already; its
`ttyS1` still dies at the handover.

### 3. Sensor probed at 0x37

timps reads `/proc/jz/sensor/sensor0`; at the first ISP open the DT client had
not bound, the registry was empty, and `timps/src/config.c:2174` forced the
`0x37` fallback (`if (c->sensor.i2c_addr == 0) c->sensor.i2c_addr = 0x37;`).
open-tx-isp then created a vendor I2C client at that address, the sc2336
driver probed it, found no OF endpoint and failed `-22`, so the ISP deferred
and a second open happened ~3.4 s later.

Fix (`0049`): on kernels >= 5.0 the bridge only resolves the DT-bound V4L2
subdev by name and defers when it is not ready. It never creates a client from
a userspace-supplied address. The vendor path is kept for pre-5.0 kernels.

Verified on the device: `dmesg | grep -c 0x37` = 0; first open defers;
`sc2336 0-0030` binds, matches, streams.

### 4. Recovery

U-Boot was erased from its prompt (`sf erase 0 10000; reset`), so the board
enumerated as bootrom `a108:c309`. `make dfu` wrote the full 8 MB image and
rebooted. The camera came back up and is reachable.

## Files touched

- `Makefile`, `Makefile.utils` - JFFS2 pagesize fix
- `docs/dev/t41-7x-port-handoff.md` - corrected the pagesize=1 note
- `board/ingenic/xburst1/kernel/7.3.3/t{10,20,21,23,30,31,32,33}.generic.config`
  - `keep_bootcon` removed, then restored
- `docs/dev/cinnado-d1-t31l-handoff.md` - recorded the failed removal
- `package/open-tx-isp/0049-t31-resolve-the-sensor-from-dt-only.patch` - new

## Commands run

```sh
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.125 make rebuild-linux
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.125 make
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.125 make ota
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.125 make dfu
```

Build gotcha: `rebuild-open-tx-isp` (and `rebuild-<pkg>` generally) installs
into `per-package/<pkg>/target` and removes the install stamps, so the
`ROOTFS_DIRTY_INPUTS` check in `Makefile.utils` does not fire and `make pack`
repacks the **old** rootfs. Run a full `make` (fast) to finalize; verify the
module hash inside `rootfs.squashfs` before flashing.

Verification used:

```sh
strings build/linux-7.3.3/vmlinux | grep -c 'earlycon keep_bootcon ieee754=relaxed'
unsquashfs -l images/rootfs.squashfs | grep tx-isp-t31.ko
ssh root@192.168.88.125 'dmesg | grep -iE "sc2336|0x37|subdev"'
```

## Open follow-ups

1. ~~Root-cause the T31 `ttyS1` handover.~~ **Fixed 2026-11-11** - see "ttyS1
   handover: FIXED" below. The boot-console unregistration is now deferred to a
   work item, so the SRCU barrier runs once the kernel is schedulable.
2. Remove `keep_bootcon` from the other xburst1 7.3.3 configs
   (t10/t20/t21/t23/t30/t32/t33) and re-verify on each board. T31 is done;
   the rest still carry the duplicated console output. Do not remove them
   blind - the boards were not reachable for testing here.
3. Extend the DT-only rule to T20 and T41:
   - T20 `driver/t20/sdk/source/tx-isp-video-in.c` still falls back to
     `v4l2_i2c_new_subdev_board`.
   - T41 uses the recovered client path in
     `driver/t41/tx_isp_t41_recovered.c`.
4. Stop the app-side guess: timps still defaults `sensor.i2c_addr` to `0x37`
   (`timps/src/config.c:2174`). The kernel now ignores it, but sending a made-up
   address is contrary to DT-as-source-of-truth.
5. Improve the ISP log: "no mainline V4L2 sensor named ..." is misleading when
   the DT client exists but has not bound yet; say it is unbound/deferred.

## ttyS1 handover: root-cause progress (follow-up session)

The hang was reproduced on the device with `keep_bootcon` removed from
`CONFIG_CMDLINE` (`earlycon ignore_loglevel initcall_debug`) and instrumented
`kernel/printk/printk.c`. It is **not** the UART driver or the pad/pinmux:

- UART1 at `0x10031000` is muxed to `uart1-data-b` (PB23/PB24), the CGU gate
  `CLKGR0` bit 15 is clear (enabled), `uartclk` is 24 MHz, the divisor latches
  hold 13, and an internal loopback (MCR LOOP, write THR, read RBR) returns the
  written byte. The early console and the real `ttyS1` console both write fine
  while the boot console is alive.
- With `keep_bootcon` off the log always stops immediately after
  `printk: legacy bootconsole [t31_uart0] disabled`, then the board resets.

Instrumented markers placed through `unregister_console_locked()` showed the
kernel passes `__pr_flush` and disables the boot console's `CON_ENABLED` flag,
then hangs in `synchronize_srcu(&console_srcu)` - the marker after it never
prints:

```
KILO:1 after-disabled
KILO:1b after-braille res=0
KILO:2 pre-pr_flush
KILO:3 post-pr_flush
KILO:4 disabled-flags
KILO:5 pre-sync-srcu          <- last line
```

The state at that point (logged by a later probe):

```
depth=0  (no console_srcu reader held)
rcu_nest=0  preempt=0
system_state=SYSTEM_SCHEDULING (1)
rcu_scheduler_active=RCU_SCHEDULER_RUNNING (2)
```

So it is **not** a leaked reader and **not** a plain-RCU read-side
self-deadlock. The SRCU grace-period callback (`rcu_gp_wq` work) simply does not
make progress this early, so `synchronize_srcu()` never returns.

Two follow-on experiments:

1. Skipping only `synchronize_srcu()` (guard: `!(flags & CON_BOOT) ||
   system_state >= SYSTEM_RUNNING`) lets the kernel boot once, but a rebuild
   with the guard and **no** extra printk still hung at the same line.
2. The same guarded kernel **with** the KILO `con_printk()` markers booted
   cleanly to userspace with `earlycon ieee754=relaxed` and no `keep_bootcon`.

That makes the failure a **timing-sensitive race**: the extra `printk()`/flush
calls during the handover serialise something that otherwise deadlocks. The
missing SRCU barrier is what the race needs, but the barrier itself cannot run
that early. A correct fix has to make the barrier work or defer the
unregistration to a point where it does (e.g. move the boot-console
unregistration out of `register_console()` and into a later initcall/work,
where `synchronize_srcu()` completes). Do not ship the "skip the barrier"
guard: it is not reliable on its own.

Recovery used during this investigation (no reflash of the bootloader needed):

- Flash a test kernel with `flashcp <uImage> /dev/mtd3` over SSH, reboot.
- If it hangs and the watchdog does not reset it, power-cycle. U-Boot is
  caught by holding Ctrl-C during its 1 s autoboot window
  (`KEY: ... Press Ctrl-C now ...`, stop string `\x03`).
- At `isvp_t31#`, boot the already-flashed (possibly bad) kernel with
  `keep_bootcon` added by hand, which skips the whole unregistration path:

  ```
  setenv bootargs keep_bootcon mem=42M@0x0 rmem=22M@0x2a00000 console=ttyS1,115200n8 panic=2 root=/dev/mtdblock4 rootfstype=squashfs init=/init mtdparts=spi0.0:192k(boot),64k(env),64k(backup),2304k(kernel),4928k(rootfs),640k(data),8192k@0(all)
  sf probe
  sf read 0x81000000 0x50000 0x240000
  bootm 0x81000000
  ```

  Then flash the known-good `uImage` over SSH and reboot normally.
- `loady`/`loadx` over the serial console are unreliable on this U-Boot (the
  last attempt transferred only ~8 KB), so network/SSH is the practical path.

The camera was left on the known-good `keep_bootcon` kernel
(`md5 75b54e05ce3eb6e41629cdb2194df4e2`) and reachable at `192.168.88.125`.
`board/ingenic/xburst1/kernel/7.3.3/t31.generic.config` was restored to
`CONFIG_CMDLINE="earlycon keep_bootcon ieee754=relaxed"`.

## ttyS1 handover: FIXED (2026-11-11)

The barrier cannot run from `register_console()` on this platform, so the
boot-console unregistration is deferred instead. New patch
`package/all-patches/linux/7.3.3/0157-printk-defer-boot-console-unregistration.patch`:

- adds `unregister_boot_consoles()` work + `unregister_boot_consoles_work`;
- `register_console()` now `schedule_work()`s it instead of calling
  `unregister_console_locked()` in the initcall context;
- the work takes `console_list_lock()`, unregisters every `CON_BOOT` console
  (so `synchronize_srcu()` now runs from a scheduler/workqueue context), and
  calls `printk_kthreads_check_locked()`.

Ordering is preserved: the real console is enabled and prints its "enabled"
line first; the boot console goes away shortly after. `keep_bootcon` is now
removed from `board/ingenic/xburst1/kernel/7.3.3/t31.generic.config`
(`CONFIG_CMDLINE="earlycon ieee754=relaxed"`).

Verified twice on the device, including a clean `make linux-rebuild` from the
patch (kernel `#9`, `uImage` md5 `d898544f8126bd4649bec90c10184daa`):

```
printk: legacy bootconsole [t31_uart0] enabled
printk: console [ttyS1] disabled
printk: console [ttyS1] enabled            <- printed twice: both consoles share UART1
printk: legacy bootconsole [t31_uart0] disabled
... full userspace boot, login prompt ...
```

Single log lines after the handover (the only remaining duplicates are the
"enabled"/"disabled" pair itself, written while both consoles are still
registered, and legitimate repeats such as `udhcpc: broadcasting discover`).
The camera reached the login prompt and SSH with `keep_bootcon` absent.

Note: the earlycon `t31_uart0` and `ttyS1` are the **same physical UART**
(`0x10031000`), which is why messages appear twice while both consoles exist.

## Risks / assumptions to revisit

- `keep_bootcon` is only off for T31 so far; the other xburst1 7.3.3 configs
  still keep the boot console and print every line twice. The printk patch is
  SoC-independent, but those boards were not re-tested.
- The deferred work runs once the kernel is schedulable; if a boot console's
  `write` were still in use by a reader at that point, the barrier waits for
  it, which is the intended behaviour.
- `0049` assumes the sensor driver binds the DT client. If a sensor ships as a
  module, the deferral relies on OF modalias autoload; verify on that board.
- JFFS2 keeps the 4 KiB mkfs default, which assumes 4 KiB kernel pages (true
  for the current MIPS configs).
- T20/T41 console behavior was not re-tested after this session's config
  churn; their `keep_bootcon` state is unchanged (T41 removed, T20 kept).
