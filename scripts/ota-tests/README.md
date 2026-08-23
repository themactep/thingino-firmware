# OTA partition-fitting test suite (QEMU)

End-to-end tests for the partition-fitting algorithm in
`package/thingino-sysupgrade/files/flash-ota`. The suite boots a QEMU
machine with a file-backed MTD flash, runs the *unmodified* `flash-ota`
script against synthetic or real images, and verifies on the host, byte for
byte, where the bytes landed and what the U-Boot env `mtdparts` says
afterwards.

The scope is deliberately narrow: **fitting a source image into a target
partition layout**. The rest of the OTA flow (SSH transfer, streamer
shutdown, config backup, host orchestration in `scripts/fw_ota.sh`) is not
replicated here.

## Problem statement

Partition sizes are derived from image sizes at build time
(`ROOTFS_PARTITION_SIZE = ROOTFS_BIN_SIZE_ALIGNED` in the top-level
Makefile; `DATA_PARTITION_SIZE` is always the remainder of the flash). A
build whose rootfs grew past the layout carved on the device fails to flash:

```
flashcp: /tmp/rootfs.bin bigger than /dev/mtd4
ERROR: flash rootfs failed
```

Because `rootfs + data` is constant for any given flash size, the two
partitions are always treated as one region: `flash_eraseall` both, write
rootfs at the rootfs offset and data right after it with `dd` (never
`flashcp`, which refuses files bigger than a partition), then repoint
`mtdparts` so the kernel carves the new boundaries. This suite exercises
that path (success and every guard failure) and asserts the exact bytes
written.

## Architecture

```
host                                                         QEMU guest (x86_64, KVM)
----                                                         ------------------------
scripts/ota-tests/
  build.sh        kernel + busybox + initramfs  ───────────►  vmlinuz + initramfs.cpio.gz
  run-tests.sh    per scenario:                              │
    setup_flash     flash.img = 0xFF + old env blob ──────►  │  -drive file=flash.img (virtio)
    run_vm          qemu -append "mtdparts=<old layout>" ──► │  block2mtd -> /dev/mtd0..6
    verify          dd/fw_printenv against flash.img ◄────── │  /init: insmod block2mtd,
                  (after VM exits; flash.img persists)       │         gen images, run flash-ota
                                                             │  flash-ota writes mtd + env,
                                                             │  reboot -f -> QEMU exits
```

### Flash emulation

- `block2mtd` maps a QEMU virtio disk into an 8 MiB MTD device with 64 KiB
  erase blocks — the same geometry as the cameras' SPI NOR (`jz_sfc`).
- The disk is a plain host file (`flash.img`), so it survives the guest's
  reboot; all verification happens on the host after the VM exits.
- The **patched** `block2mtd` module (see `build.sh`) reports
  `MTD_NORFLASH` instead of `MTD_RAM`. libubootenv's `fw_printenv`/`fw_setenv`
  — the same tools the cameras use — reject non-NOR/NAND MTD types, so the
  stock driver would make the env tools fail with `Cannot initialize
  environment`. The erase-first write semantics are unchanged.
- The old layout is passed twice, mirroring the camera: `mtdparts=` on the
  kernel cmdline (what the kernel carves into `/proc/mtd`) and the same
  string baked into the env partition of `flash.img` via `mkenvimage` (what
  `fw_printenv mtdparts` returns).

### Guest environment

- Minimal x86_64 kernel (built from `/usr/src/linux-source-*`, `O=` build
  against the root-owned read-only tree): `MTD`, `MTD_BLOCK`,
  `MTD_CMDLINE_PARTS`, `BLOCK2MTD`, `VIRTIO_BLK`, `SERIAL_8250_CONSOLE`,
  `DEVTMPFS`, initramfs, and `BINFMT_SCRIPT` (without it the kernel cannot
  exec the `/init` shell script — a classic allnoconfig gotcha).
- `block2mtd` is a *module* loaded by `/init` after `/dev/vda` appears; the
  built-in driver races virtio probing at boot and fails to open the device.
- Static busybox with `ash`, `dd`, `flashcp`, `flash_eraseall`, `md5sum`,
  `stat`, `head`, `tr`, ... plus libubootenv's `fw_printenv`/`fw_setenv`
  (host binaries + glibc, libubootenv, libz, libyaml copied into the
  initramfs) and `/etc/fw_env.config` pointing at `/dev/mtd1`.
- The initramfs carries the real `flash-ota` script (copied verbatim from
  the repo) and generates synthetic images from test parameters on the
  cmdline: `dd if=/dev/zero | tr '\0' '\252'`-style fill patterns.
- Real images (`rootfs.squashfs`, `data.jffs2`, `uImage`,
  `u-boot-lzo-with-spl.bin`, `u-boot-env.bin`) can be baked in as
  `/images/*`; they override the synthetic ones.

## Usage

```bash
scripts/ota-tests/build.sh                          # build everything (idempotent)
scripts/ota-tests/run-tests.sh                      # run all 12 scenarios
scripts/ota-tests/run-tests.sh scenario_rootfs_grew # run one scenario
scripts/ota-tests/run-tests.sh scenario_rootfs_grew scenario_too_big
```

Artifacts land in `${THINGINO_OUTPUT_ROOT_DIR:-output}/ota-tests/`
(that is, `/home/paul/output/ota-tests` on the developer machine). Per-run
serial logs are `run-<scenario>.log`.

### Requirements

| dependency | notes |
|---|---|
| kernel source | `/usr/src/linux-source-*`, override with `KERNEL_SRC` |
| busybox tarball | picked from the thingino dl cache, override with `BUSYBOX_TARBALL` |
| qemu-system-x86_64 | KVM used automatically when `/dev/kvm` is present |
| u-boot-tools / libubootenv | `mkenvimage`, `fw_printenv`, `fw_setenv` |
| build tools | gcc, make, cpio, gzip, shfmt, shellcheck |

The first `build.sh` run takes a few minutes (kernel + busybox); afterwards
it is a no-op until artifacts are deleted.

## Scenario catalog

Layouts use the standard thingino partition scheme (`boot 256k, env 64k,
backup 64k, kernel 1600k` at offset 0..1984k, then rootfs/data, then
`8192k@0(all)`).

| # | scenario | old layout | new images | expect |
|---|---|---|---|---|
| 1 | `fit-normal` | rootfs 5120k, data 1088k | rootfs 4608k, data 640k | unified flash; data partition recomputed to 1600k; env updated |
| 2 | `exact-fit` | rootfs 5760k, data 448k | rootfs 5760k, data 448k | unified flash; layout unchanged; env untouched |
| 3 | `rootfs-grew` | rootfs 5568k, data 640k | rootfs 5760k, data 448k | unified flash; env updated |
| 4 | `rootfs-shrunk` | rootfs 5760k, data 448k | rootfs 5120k, data 1088k | unified flash; env updated |
| 5 | `rootfs-only` | rootfs 5568k, data 640k | rootfs 5760k, no data | unified flash; data area erased |
| 6 | `too-big` | rootfs 5568k, data 640k | rootfs 5760k, data 1024k | error; nothing written |
| 7 | `no-all` | no `(all)` partition | rootfs 5760k, data 448k | error; nothing written |
| 8 | `non-adjacent` | 64k `reserved` between rootfs and data | rootfs 5504k, data 512k | error; nothing written |
| 9 | `kernel` | standard | 1600k fill image | kernel partition flashed |
| 10 | `kernel-real` | standard | real `uImage` (IMG_DIR) | kernel partition flashed |
| 11 | `boot` | standard | real U-Boot + env blob (IMG_DIR) | boot+env flashed; env = new layout |
| 12 | `real-images` | rootfs 5568k, data 640k | real `rootfs.squashfs` + `data.jffs2` (IMG_DIR) | unified flash; env updated |

Scenarios 3 and 12 reproduce the original failure mode
(`flashcp: /tmp/rootfs.bin bigger than /dev/mtd4`) end to end. In every
rootfs scenario the two images are flashed with `flash_eraseall` + `dd`
through the `all` partition at chip offsets - `flashcp` is never used.

`IMG_DIR` defaults to the cinnado_d1_t31l_sc2336_atbm6031
(`192.168.88.34`) build output
(`$THINGINO_OUTPUT_ROOT_DIR/ciao/<camera>-3.10.14-uclibc-192.168.88.34/images`).
Scenarios using real images are skipped with a warning when it is missing.

## Verification

After the VM exits, the host asserts, per scenario:

1. **Log path**: the `flash-ota` output shows the expected behavior —
   `Writing rootfs (...KiB) to /dev/mtd6 at ...KiB` (the `dd` write) for a
   successful flash, the error message for error scenarios.
2. **Byte placement** (via `dd` + `md5sum` of `flash.img`):
   - success: rootfs at the rootfs offset, data at `rootfs_offset +
     new_rootfs_size` (the new data partition), with the data-partition
     tail beyond the image still erased (0xFF);
   - error: `flash.img` is byte-identical to the pre-run image.
3. **Untouched regions**: boot (0x11 fill), backup (0x22), kernel (0x33)
   remain unchanged — catches over-eager erases that would clobber the
   bootloader or kernel.
4. **Env `mtdparts`** (read back with the real `fw_printenv -c` against
   `flash.img`):
   - error, or success with an unchanged rootfs size: unchanged;
   - success with a changed rootfs size: the old string with rootfs/data
     sizes replaced by the aligned new sizes (computed the same way
     `flash-ota` computes them).

`region_md5_bytes` trims reads to exact byte counts, so non-64k-aligned real
images (uImage, U-Boot) are compared precisely.

## Adding a scenario

1. Add a function in `scenarios.sh`, e.g.:

   ```bash
   scenario_my_case() {
       NAME=my-case
       OLD_MTDPARTS="$BASE,5568k(rootfs),640k(data)$ALL_TAIL"
       MODE=rootfs
       ROOTFS_K=5760; DATA_K=448; FILL=aa; FILLD=55
       EXPECT=flash; ERR_MSG=
   }
   ```

   Fields: `NAME`, `OLD_MTDPARTS` (layout on the "device"),
   `MODE` (rootfs|kernel|boot), image sizes in KiB (`ROOTFS_K`, `DATA_K`,
   `KERNEL_K`, `BOOT_K`, `ENV_K`), fill bytes (`FILL`, `FILLD`),
   `EXPECT` (flash|error), `ERR_MSG` (error scenarios),
   `RESERVED_K` (non-adjacent layouts), `REAL_IMAGES` (use real images).

2. Add the function name to `ALL_SCENARIOS` in `run-tests.sh`.
3. `verify()` dispatches on `MODE`/`EXPECT`; extend it if your scenario
   asserts something new (most need nothing — the standard branches cover
   flash/error for rootfs mode and the fixed assertions for kernel/boot).

## Debugging

- Each run leaves `run-<scenario>.log` with the full serial console:
  kernel boot, `/proc/mtd`, the `flash-ota` transcript, and the post-flash
  state.
- Quick iteration: `run-tests.sh <one scenario>` prints the PASS/FAIL
  summary; inspect the log for the VM side.
- Known failure modes and their causes:

  | symptom | cause |
  |---|---|
  | `Failed to execute /init (error -8)` | `CONFIG_BINFMT_SCRIPT` missing from the kernel |
  | `block2mtd: error: cannot open device /dev/vda` | built-in driver raced virtio; it must be a module loaded from `/init` |
  | `Cannot initialize environment` (fw_printenv) | stock block2mtd reports `MTD_RAM`; libubootenv only accepts NOR/NAND — the patched module fixes this |
  | `flashcp: invalid option -- 'A'` | busybox flashcp has no `-A`; the probe must match both `unrecognized` and `invalid option` |
  | VM hangs after `System halted` | `poweroff` without ACPI halts instead of exiting; `/init` ends with `reboot -f` (QEMU `-no-reboot` exits) |
  | `arithmetic syntax error` at read_mtd_layout | the `/proc/mtd` header line (`dev: size erasesize name`) is not skipped |

## Design notes / alternatives considered

- **Why `block2mtd` and not `mtdram`?** `mtdram` is RAM-backed and dies
  with the VM, forcing in-guest verification before reboot. `block2mtd` on
  a virtio disk is a plain file: the guest reboots freely and the host
  inspects the flash afterward with ordinary `dd`/`fw_printenv`.
- **Why x86_64?** The algorithm is pure shell; there is no mips-specific
  code under test, so the fastest architecture (host-native, KVM) is the
  right one.
- **Why the patched block2mtd?** To exercise the *real* env tools against
  the emulated flash. Without it, `fw_setenv` cannot be tested at all.
- **Why not boot the full rootfs?** The suite tests the fitting algorithm,
  not the whole sysupgrade; booting a squashfs and mounting overlay would
  add time and machinery without exercising anything new.
