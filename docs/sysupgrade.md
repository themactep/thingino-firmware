# Sysupgrade & Flash-OTA

Thingino has two camera-side upgrade utilities:

| Script | Used for | Uploaded by |
|---|---|---|
| `flash-ota` | boot, kernel, rootfs partial upgrades | `fw_ota.sh` (host-driven Makefile targets) |
| `sysupgrade` | full firmware upgrades, on-camera GitHub downloads | `fw_ota.sh` (full mode) or user-invoked on camera |

## Partition Layout

All SFC (SPI NOR) builds share a fixed early-partition layout:

```
mtdparts=...:256k(boot),64k(env),64k(backup),1600k(kernel),*k(rootfs),*k(data),*@0(all)

mtd0   boot       256KB   fixed   U-Boot SPL + image
mtd1   env         64KB   fixed   U-Boot environment
mtd2   backup      64KB   fixed   config backup (raw, cfg-backup)
mtd3   kernel    1600KB   fixed   uImage
mtd4   rootfs     varies  dynamic squashfs
mtd5   data       varies  dynamic JFFS2 overlay
mtd6   all        varies  virtual — full chip
```

Kernel is fixed at 1600KB (the largest kernel across all cameras), so rootfs always starts at the same offset — enabling partial upgrades.

## flash-ota (partial upgrades)

`flash-ota` is a minimal, single-purpose script uploaded to the camera by
`fw_ota.sh` for boot, kernel, and rootfs OTA. It receives **pre-assembled,
partition-sized files** — no extraction, no magic detection, no GitHub
downloads.

```
flash-ota boot   /tmp/boot.bin /tmp/env.bin
flash-ota kernel /tmp/kernel.bin
flash-ota rootfs /tmp/rootfs.bin /tmp/data.bin
```

For rootfs mode, `flash-ota`:
1. Resolves MTD device names from `/proc/mtd` while rootfs is still rw.
2. Clones busybox to `/tmp/flash-ota.d/` so it survives the rootfs erase.
3. Remounts `/` read-only so the kernel allows writes to the MTD device.
4. Flashes using `flashcp -A` (auto-erase) when available, falling back to
   `flash_eraseall` + `flashcp`.
5. Reboots.

Boot and kernel modes skip the busybox-clone / remount step since they do not
touch the rootfs partition.

## sysupgrade (full upgrades)

The `sysupgrade` utility handles full firmware upgrades and on-camera GitHub
downloads. It validates image magic, supports config backup, and uses a
two-stage detached flash process with watchdog takeover.

```
sysupgrade -f              full upgrade from GitHub (flash entire image)
sysupgrade -b              bootloader only from GitHub
sysupgrade -k              kernel only from GitHub
sysupgrade -r              rootfs + data from GitHub
sysupgrade -B | --backup   create config backup before any flash
sysupgrade -d DATE         request a specific GitHub release date

sysupgrade <file>          auto-detect magic and flash accordingly
sysupgrade <URL>           download from URL, then auto-detect
```

## Make Targets (OTA)

From the build host, use `make` targets to build and flash over the network.
All targets require `IP=<camera-ip>`.

```sh
make ota                  # full firmware upgrade (same as ota-full)
make ota-full             # full firmware (uses sysupgrade)
make ota-kernel           # kernel only (uses flash-ota)
make ota-uboot            # bootloader + env (uses flash-ota)
make ota-rootfs           # rootfs + data (uses flash-ota)
make ota-upgrade          # rootfs + data + config backup (uses flash-ota)
```

Shared environment variables:

| Variable | Effect |
|---|---|
| `IP=<addr>` | Camera IP address (required) |
| `CAMERA=<name>` | Camera config name (auto-detected from device if omitted) |
| `FORCE=1` | Skip IMAGE_ID mismatch check |
| `BACKUP=1` | Create config backup before flash (built-in for `ota-upgrade`) |

Examples:
```sh
IP=192.168.88.127 make ota-upgrade
IP=192.168.88.127 make ota-kernel FORCE=1
```

### How host-driven OTA works

1. `fw_ota.sh` pads partition files to exact MTD sizes on the host (boot to
   256KB, env to 64KB, rootfs to 64KB-aligned, data as-is).
2. Uploads `flash-ota.sh` and the partition files to `/tmp/` on the camera.
3. Invokes `flash-ota.sh <mode> <file> [file2]` which flashes each partition
   directly to its MTD device and reboots.
4. `fw_ota.sh` closes the SSH mux and exits — the camera reboots independently.

For full firmware (`ota-full` / `ota`): the legacy `sysupgrade` script is
uploaded instead, along with the complete `thingino-*.bin` image. `sysupgrade`
handles extraction and two-stage detached flashing.

## Magic Validation (sysupgrade)

`sysupgrade` validates image magic bytes before flashing. Wrong image → wrong
partition is always rejected.

| Flag | Accepted input magic | Action |
|---|---|---|
| `-b` | `06050403` (U-Boot) | extract bootloader → mtd0 |
| `-k` | `06050403` (U-Boot) | extract kernel from full image → mtd3 |
| `-k` | `27051956` (uImage) | flash standalone kernel → mtd3 |
| `-r` | `06050403` (U-Boot) | extract rootfs+data from full image → mtd4+mtd5 |
| `-r` | `68737173` (squashfs) | flash pre-trimmed or standalone rootfs → mtd4+mtd5 |
| (auto) | `06050403` | full upgrade → each partition individually |
| (auto) | `27051956` | kernel → mtd3 |
| (auto) | `68737173` | rootfs → mtd4 |

Anything else → aborts with an error.

> **Note**: `flash-ota` does not validate magic — it receives files already
> known to be correct (padded to partition size by `fw_ota.sh` on the host).
> Validation is done at build time when the partition files are produced.

## Config Backup (`--backup` / `-B`)

Stores selected config files to the raw 64KB backup partition (mtd2) before flashing.

```sh
# Manually (on the camera):
cfg-backup write                     # backs up everything in /etc/cfg-backup.list
cfg-backup write /etc/myextra.conf   # backs up list file + custom paths
cfg-backup restore                   # restores after upgrade
```

Default manifest (`/etc/cfg-backup.list`):
```
/etc/passwd /etc/shadow               # user accounts
/etc/wpa_supplicant.conf              # WiFi
/etc/TZ /etc/timezone                 # timezone
/etc/dropbear                         # SSH host keys
/root/.ssh/authorized_keys            # SSH access
/etc/thingino.json                    # Thingino config
```

The list file itself is always included in the backup, so a restore gives you back the exact manifest that was used.

Format: 64-byte text header (magic `THNG_BCKUP`, size, MD5) followed by an uncompressed tar archive. Fits in one 64KB erase block.
