# Thingino Firmware

**BR2_EXTERNAL** tree for Ingenic SoC IP cameras. Extends Buildroot
(`buildroot/` + `linux/` are git submodules). Forked from
[themactep/thingino-firmware](https://github.com/themactep/thingino-firmware).

## Build commands

```bash
make update                     # pull + submodule update + Buildroot patches + toolchain bundles
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make   # build (default = clean + parallel + pack)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make fast   # incremental (no clean)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make dev    # serial build (noisy, for debugging)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make menuconfig
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make saveconfig
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make edit-defconfig
CAMERA=atom_cam2_t31x_gc2053_atbm6031 IP=192.168.1.42 make ota
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make rebuild-<pkg>   # dirclean + rebuild + reinstall + finalize
make build-all                  # builds every camera in configs/cameras/
make run CMD="bin/ffmpeg --help"  # QEMU run target binary
```

- `CAMERA=` can be supplied interactively (uses `scripts/select_camera.sh`).
- `BOARD=` is an alias for `CAMERA=` (backward compat with CI).
- `WORKFLOW=1` skips dep check + interactive camera selection (CI use).
- `PRISTINE=1` disables user directory (`THINGINO_USER_DIR=/dev/null`).
- Output: `output/<branch>/<camera>-<kernel>-<libc>[-<ip>]/`
- No test suite. Validation is CI-only.

## Repo layout

```
configs/cameras/<camera_name>/   # per-camera defconfig + .config + .uenv.txt + overlay/
package/<name>/                  # Buildroot packages (mk + Config.in)
overlay/                         # root filesystem overlay (applied to all builds)
board/ingenic/                   # DTB patches, post-build scripts, board files
scripts/                         # selection, OTA, TFTP, dep_check, misc helpers
thingino.mk                      # SOC/kernel/flash/ISP/streamer variable definitions
board.mk                         # camera selection logic
external.mk                      # auto-includes package/*/*.mk
local.mk                         # override sources for local dev (commented out by default)
overrides/                       # local source overrides (wired by local.mk)
```

## Camera naming

```
<brand>_<model>_<soc>_<sensor>_<wifi_chip>   # e.g. atom_cam2_t31x_gc2053_atbm6031
```

First line of defconfig: `# NAME: <human-readable>`; second line: `# FRAG: <fragments>`.

## Config model

`.config` is assembled from: **toolchain fragment** (e.g.
`configs/fragments/toolchain/ext-gcc15-musl.fragment`) + **config fragments**
(per `# FRAG:` in defconfig) + **camera defconfig** + **U-Boot fragment** +
**user local.fragment** files. Template variables like `$(SOC_FAMILY)` are
substituted during assembly.

User config layers (scoped, each additive):
`user/<common>/` > `user/<camera>/` > `user/<camera>/<ip>/`
Each can contain `local.fragment`, `local.mk`, `local.uenv.txt`, `thingino.json`,
`prudynt.json`, `overlay/`, `opt/`.

Config fragments and per-camera overlay are merged at build time into the
config and rootfs partitions respectively.

## SOC / kernel

SOC family is derived from `BR2_INGENIC_SOC_MODEL` via `Config.soc.in` and the
SoC database (`scripts/soc_database.txt`). `thingino.mk` exports key variables:
`SOC_FAMILY`, `SOC_MODEL`, `SOC_RAM_MB`, `ISP_RMEM_MB`, `STREAMER`, etc.

Kernel branches are mapped from SOC family + version in `thingino.mk`.
Kernel versions: `3.10.14`, `4.4.94`, `7.1-rc1`.
Kernel source: `github.com/gtxaspec/thingino-linux`.

## Streamers

Default is `prudynt`. Set `BR2_PACKAGE_RAPTOR_IPC=y` to use `raptor` instead.

## Firmware image

- **SFC (SPI flash)**: `u-boot + env + config.jffs2 + uImage + rootfs.squashfs + extras.jffs2`
- **MMC (SD card)**: INGE header + SPL + U-Boot + FAT32 (uImage) + ext4 (rootfs)
- Image assembly is done by `$(FIRMWARE_BIN_FULL)` rule in `Makefile`.

## U-Boot

Buildroot provides the base U-Boot version (`2026.04` by default). Thingino
applies a single large patch (`package/all-patches/uboot/2026.04/0001-from-2026.04-to-thingino.patch`)
that adds all Ingenic-specific code. **Do not edit that patch.** If you need
U-Boot changes, add numbered follow-up patches in the same directory (e.g.
`0002-my-change.patch`) — Buildroot applies them in sort order after the large
patch.

## Package overrides

Uncomment `<pkg>_OVERRIDE_SRCDIR` in `local.mk` pointing to a local checkout
under `overrides/`. Overrides bypass Buildroot patches — apply them manually
before editing. Use `make rebuild-<pkg>` after changing overrides.

## SSH / SCP

`scp -O` is required (dropbear server). Default password is set in the defconfig.

## Style / pre-commit

- `package/thingino-webui/files/www/a/*.js` → formatted with **Prettier**.
- Staged `/bin/sh` scripts → formatted with **shfmt** (`shfmt -w -i 0 -ci`).
- `.githooks/pre-commit` must be active (`make setup-hooks`).

## Docker

```bash
make docker-shell    # builds image (debian:trixie) and drops into container
make docker-build    # build image only
```

Container engine auto-detects podman → docker fallback.

## Thingino skills

Installable skills for OpenCode/Copilot are maintained at
[github.com/themactep/thingino-skills](https://github.com/themactep/thingino-skills).
These cover NFS dev deploy, package overrides, RTSP stress testing,
diagnostics, OTA workflows, adding streamers, and more.

## Git credentials

Use the user's git config for commit/patch authorship:

```bash
git config user.name && git config user.email
```

Always supply `Signed-off-by:` matching the git config when creating patches.

## Work procedures

- **Never delete files irreversibly.** Files that need to be removed from the
  build should be handled in one of these ways (in order of preference):
  1. Ensure the file is committed into the repo so it can be restored later.
  2. Rename in place to exclude from the build (e.g. `.patch` → `.patch.disabled`).
  3. Move to a dedicated `trash/` directory (e.g. `trash/<original-path>/`),
     leaving it up to the user to decide when to permanently delete.

## Important constraints

- Repo path must not contain spaces (checked by `dep_check.sh`).
- Only `x86_64` and `aarch64` hosts are supported.
- `make update` applies Buildroot patches from `package/all-patches/buildroot/` —
  do not run `git pull` directly.
- Keep changes surgical — this is a cross-compilation build system where a
  mistake can waste 30+ minutes of rebuild time.
