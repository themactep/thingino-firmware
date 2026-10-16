# Firmware variants

Thingino builds one of three package profiles, chosen by a Kconfig choice:

| Variant | Kconfig symbol | Contents |
| --- | --- | --- |
| Full (default) | `BR2_PACKAGE_THINGINO_VARIANT_FULL` | Everything Thingino ships today. |
| 8 MB flash | `BR2_PACKAGE_THINGINO_VARIANT_FLASH8` | Full trimmed to fit an 8 MB SPI NOR chip. |
| Minimal | `BR2_PACKAGE_THINGINO_VARIANT_MINIMAL` | Kernel, shell, SSH only. Fast incremental dev builds. |

Full is the choice default, so a camera that does not set a variant builds
exactly as before.

## Selecting a variant

Set the symbol in any of the three configuration layers:

- **menuconfig** - `Thingino Firmware` -> `Firmware variant`.
- **camera defconfig** - add the line to
  `configs/cameras/<camera>/<camera>_defconfig`.
- **user overlay** - add the line to
  `user/<common|camera|device>/local.fragment`.

```kconfig
# 8 MB image on an 8 MB chip
BR2_PACKAGE_THINGINO_VARIANT_FLASH8=y

# development image
BR2_PACKAGE_THINGINO_VARIANT_MINIMAL=y
```

The 8 MB variant is a package profile, not a partition layout. Pair it with a
camera that declares `FLASH_SIZE_MB=8` (or edit the value in menuconfig);
the variant does not force the flash size, so an explicit camera value still
wins.

## What each variant enables

The variant selects two hidden tier symbols in
`package/thingino-variant/Config.in`:

- `BR2_PACKAGE_THINGINO_VARIANT_APPS` - the baseline app layer. Enabled by
  Full and 8 MB.
- `BR2_PACKAGE_THINGINO_VARIANT_APPS_EXTRA` - Full-only extras, trimmed from
  the 8 MB profile.

| Package | Full | 8 MB | Minimal |
| --- | --- | --- | --- |
| `mdnsd` (+ HTTP, mquery) | yes | yes | no |
| `thingino-diag`, `-gpio`, `-system`, `-sysupgrade`, `-isp-inspector` | yes | yes | no |
| `thingino-agent` | yes | via streamer | no |
| `thingino-ha`, mosquitto | yes | no | no |
| `thingino-vpn` (WireGuard default) | yes | no (None) | no |
| WebUI, uhttpd, ONVIF, sounds | yes | partial | no |
| streamer (prudynt) | yes | yes | no |
| dropbear, busybox, core, kopt, SSL | yes | yes | yes |

Minimal keeps the system layer (`BR2_THINGINO_SYSTEM_PACKAGES`) so dropbear,
busybox, the kernel-option tooling, and the Ingenic platform libraries still
build. It drops the app layer, the WebUI, the web server, and the streamer.
It still pulls mbedTLS (dropbear) and a `jct`/`libubox`/`odhcp6c` chain via
IPv6 support.

## How it is wired

- `package/thingino-variant/` is a virtual package (no source), following the
  `thingino-ssl` pattern. `external.mk` picks up its `.mk` automatically; its
  `Config.in` is sourced near the top of the top-level `Config.in`.
- The app-layer `=y` lines that used to live in
  `configs/fragments/core.fragment` are now `select`s on the tier symbols.
  A fragment line can only turn a symbol on, so Kconfig `select`s are what let
  a variant turn a package off. Structural lines (toolchain, kernel, rootfs,
  U-Boot, busybox config, host packages) stay in the fragment.
- Choice members cannot be forced with `select`, so the VPN, streamer, and web
  server choices use variant-conditional `default`s instead.
- Minimal gating lives in the top `Config.in`: the optional
  `BR2_THINGINO_SYSTEM_PACKAGES` selects and the hardware-derived ones carry
  `!BR2_PACKAGE_THINGINO_VARIANT_MINIMAL`, the streamer group and the
  development group default off, and the web server choice defaults to None.

## Adding a package to a tier

1. Baseline (Full + 8 MB): add `select BR2_PACKAGE_<name>` to
   `BR2_PACKAGE_THINGINO_VARIANT_APPS`.
2. Full-only (trimmed from 8 MB): add it to
   `BR2_PACKAGE_THINGINO_VARIANT_APPS_EXTRA`.
3. A `select` cannot turn a symbol off. If the package has `default y` and must
   be down in a tier, add `# BR2_PACKAGE_<name> is not set` to
   `configs/fragments/core.fragment` (as MDNSD's SSH advertisement does).
4. If the package is a Buildroot symbol, gate it from the Thingino side with a
   `select`; never edit `buildroot/`'s `Config.in`.

## Caveats

- **Streamer coupling.** The default streamer (prudynt) `select`s
  `thingino-agent`, `thingino-onvif`, `thingino-send2`, `thingino-jct`, and
  (with Opus) `thingino-sounds`. Those reappear in the 8 MB profile no matter
  what `APPS_EXTRA` says. Gating them out of a tier means gating the streamer's
  own `Config.in`, not the tier symbol.
- **The 8 MB trim list is provisional.** It must be confirmed by a real image
  fit (`rootfs.squashfs` + `data.jffs2` <= flash minus the fixed partitions).
  The fit, not this table, settles the final membership.
- **Minimal is not a shippable camera image.** It has no streamer and no web
  UI; it exists to make incremental development builds fast.

## See also

- [Firmware image structure](../firmware/firmware-image-structure.md)
