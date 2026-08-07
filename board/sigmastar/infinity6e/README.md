# SSC30KQ (Infinity6E)

## Images

`thingino-<camera>.bin` is the whole flash, laid out as the table below. It
contains the bootloader, so a full sysupgrade replaces mtd0 — the one write on
this board that cannot be undone in software. It stops at the end of the rootfs
rather than padding to 16MB; sysupgrade erases the partition before writing, so
the overlay area is already erased and `/init` formats it on first boot.

The pieces are emitted separately as well:

| artifact | offset | partition |
|---|---|---|
| `u-boot-ssc30kq-nor.bin` | 0x000000 | mtd0 `boot` |
| `u-boot-env.bin` | 0x040000 | mtd1 `env` |
| `uImage` | 0x050000 | mtd2 `kernel` |
| `rootfs.squashfs` | 0x250000 | mtd3 `rootfs` |

`u-boot-ssc30kq-nor.bin` is the mask-ROM container — IPL, MXP_SF and IPL_CUST at
fixed offsets in the first 128KB with the compressed U-Boot appended. It is not
`u-boot.bin`, and writing that instead produces a board that does not boot and
cannot be recovered over the network.

## Partitions

Generated per build by `ssc30kq-post-image.sh`, sized to the images:

```
NOR_FLASH:256k(boot),64k(env),<kernel>k(kernel),<rootfs>k(rootfs),<data>k(data),16384k@0(all)
```

`boot` and `env` are fixed: the bootloader is compiled with `CONFIG_ENV_OFFSET
0x40000` and `CONFIG_ENV_SIZE 0x10000`, so changing either means changing
`sstar-common.h` to match. `kernel` and `rootfs` are cut to the images and
64KB-aligned, `data` is the remainder, and `all` overlaps the whole chip because
`thingino-sysupgrade` refuses to run without it.

`data` replaces the OEM's `rootfs_data`, and the name is load-bearing: `/init`
matches the overlay loosely as `/data/` in `mount_jffs2` but strictly as
`/"data"/` in `format_overlay`, so under the OEM name the format-on-corruption
recovery path resolves to an empty device and fails.

Sizing to the images means offsets move when the images do. If the kernel or
rootfs crosses a 64KB boundary every partition after it shifts, and the
environment describing them is correct only for that one build — so kernel,
rootfs and environment are flashed together, which is what the full image does.

## If the environment is lost

A bad CRC in mtd1 makes the bootloader fall back to its compiled defaults, which
still carry the OEM table and a 5120k rootfs. A larger rootfs then reads as
truncated: it appears to mount and fails later, looking like filesystem
corruption rather than a partition problem. Re-apply `uenv.txt` before
concluding anything about the image.

This is worse under our own bootloader than under the OEM one, because
`0001-cmd_sf-drop-retrospective-rootfs-auto-sizing.patch` also removes the
accident that used to rescue it — the OEM `sf probe` would read the real rootfs
and raise `rootmtd`, where ours leaves the compiled value standing. That patch
is still correct: the auto-sizing described the image already on the chip rather
than the one being written, so it sized every partition for the previous image
and no image could ever cross the threshold.
