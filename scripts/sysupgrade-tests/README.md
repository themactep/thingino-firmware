# sysupgrade QEMU test suite

End-to-end tests for the layout handling in `sysupgrade` and `flash-ota`.
A QEMU guest boots with an old partition layout, runs the real camera-side
scripts against synthetic partition images, and the host verifies the
resulting flash byte for byte.

The suite reuses the kernel, static busybox, and patched `block2mtd` module
built by `scripts/ota-tests/build.sh`. Only the initramfs is built here.

## What it covers

- Full upgrades (`sysupgrade-stage2 full`) where the new build's boot
  partition is smaller, larger, or equal to the one on the device.
- Config backup relocation: the snapshot is written to the old backup
  partition, dumped to tmpfs, and rewritten at the offset derived from the
  new image.
- Bootloader-only flashes (`flash-ota boot`) on a matching and a mismatched
  layout. A mismatch must be refused before anything is erased.
- Kernel-only and rootfs-only flashes on a matching and a mismatched
  layout.
- Branch selection in stage1: the default branch resolves the `firmware`
  series through `/releases/latest`, `-t master` resolves `master-*` through
  the releases API, and arbitrary branches resolve `<branch>-*`. Partial
  upgrades with `-t` are refused before any download.

## Architecture

```
host                                                         QEMU guest
----                                                         ----------
scripts/sysupgrade-tests/
  build.sh        reuse ota-tests kernel/busybox/block2mtd   │
                  + initramfs with the real scripts            │
  run-tests.sh    per scenario:                               │
    setup_flash   flash.img = old layout + fill patterns ───► │  /init:
    run_vm        qemu -append "mtdparts=<old layout>           │    build new image
                  t_*=..."                                     │    run sysupgrade-stage2
    verify        dd/xxd/md5sum against flash.img ◄────────── │    or flash-ota
                  (after VM exits; flash.img persists)         │  reboot -f -> QEMU exits
```

The old layout is passed on the kernel command line as `mtdparts=`, so
`/proc/mtd` looks like the device. The new layout is passed as `t_*` sizes.
The guest builds a full image with the new layout and a uImage magic at the
new kernel offset, which is what `find_backup_offset` scans for.

The guest runs the real `find_backup_offset` by extracting it from the
stage1 script. The stage2 script runs with its tools in `/tmp/sysupgrade`,
the same way stage1 sets it up.

## Usage

```bash
scripts/sysupgrade-tests/build.sh
scripts/sysupgrade-tests/run-tests.sh
scripts/sysupgrade-tests/run-tests.sh scenario_full_shrink
```

Artifacts land in `${THINGINO_OUTPUT_ROOT_DIR:-output}/sysupgrade-tests/`.
Per-run logs are `run-<scenario>.log`.

## Scenario catalog

The flash is 8 MiB. Env, backup, and kernel sizes are fixed at 64, 64, and
1600 KiB. Rootfs is 5120 KiB, so data is the remainder.

| # | scenario | mode | old boot | new boot | expect |
|---|---|---|---|---|---|
| 1 | `full-same` | full + backup | 192K | 192K | flash; backup relocated to the same offset |
| 2 | `full-shrink` | full + backup | 320K | 192K | flash; backup moves from 320K to 256K |
| 3 | `full-grow` | full + backup | 192K | 320K | flash; backup moves from 256K to 320K |
| 4 | `full-shrink-nobackup` | full | 320K | 192K | flash; backup slot stays erased |
| 5 | `part-boot-same` | boot | 192K | 192K | boot + env flashed |
| 6 | `part-boot-shrink` | boot | 320K | 192K | refuse; flash unchanged |
| 7 | `part-boot-grow` | boot | 192K | 320K | refuse; flash unchanged |
| 8 | `part-kernel-same` | kernel | 192K | 192K | kernel flashed at the device offset |
| 9 | `part-kernel-different` | kernel | 320K | 192K | kernel flashed at the device offset |
| 10 | `part-rootfs-same` | rootfs | 192K | 192K | rootfs + data flashed |
| 11 | `part-rootfs-grow` | rootfs | 192K | 320K | rootfs + data flashed; data tail erased |
| 12 | `part-rootfs-shrink` | rootfs | 320K | 192K | error; flash unchanged |
| 13 | `branch-full-default` | branch/full | - | - | requests `/releases/latest/download/...` |
| 14 | `branch-full-master` | branch/full `-t master` | - | - | requests `master-2026-01-01` |
| 15 | `branch-full-other` | branch/full `-t figata` | - | - | requests `figata-2026-02-02` |
| 16 | `branch-kernel-reject` | branch/kernel `-t master` | - | - | refuse; no download |
| 17 | `branch-rootfs-reject` | branch/rootfs `-t master` | - | - | refuse; no download |
| 18 | `branch-boot-reject` | branch/boot `-t master` | - | - | refuse; no download |

Scenarios 6 and 7 cover the `flash-ota boot` guard: the padded boot image
no longer matches the device boot partition, so env would land at the wrong
offset.

Scenarios 13-18 run stage1 itself with a fake `curl` on `PATH`. The fake
answers `api.github.com` with a fixed release list and logs any other
request as `CURL-REQ ...`, then fails, so URL selection is observable in
the guest log while nothing is downloaded or flashed.

## Verification

For each scenario the host asserts:

1. The guest log shows the expected path and, for refusals, the error text.
2. Region contents via `md5sum` and `xxd`:
   - full: new boot, env, kernel, rootfs, and data at the new offsets; the
     synthetic snapshot at the new backup offset (magic, payload, erased
     tail); the old backup block now holds image bytes.
   - single partition: the flashed partition holds the new fill; every
     other region keeps the old fill.
3. For refusal and error scenarios, `flash.img` is byte-identical to the
   pre-run image.

## Requirements

| dependency | notes |
|---|---|
| kernel source | downloaded from kernel.org (6.18.63) into the scratch dir; override with `KERNEL_SRC` or `KERNEL_VERSION` |
| busybox tarball | picked from the thingino dl cache, override with `BUSYBOX_TARBALL` |
| qemu-system-x86_64 | KVM used automatically when `/dev/kvm` is present |
| build tools | cpio, gzip, md5sum, xxd, gcc, make |

The first `build.sh` run delegates to `scripts/ota-tests/build.sh` and can
take a few minutes while the kernel and busybox are built. Later runs are
no-ops until the artifacts are deleted.

## Debugging

Each run leaves `run-<scenario>.log` with the kernel boot, `/proc/mtd`, the
new image layout, the `sysupgrade-stage2` streaming log or the `flash-ota`
transcript, and the final state. Run a single scenario while iterating:

```bash
scripts/sysupgrade-tests/run-tests.sh scenario_full_shrink
```
