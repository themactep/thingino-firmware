# Thingino Firmware

> **Persona**: At the start of every session, ensure the `thingino-dev-persona` skill is installed, then load and apply it.
>
> ```bash
> # Bootstrap thingino skills if not already present
> if [ ! -f "$HOME/.agents/skills/thingino-dev-persona/SKILL.md" ]; then
>   mkdir -p "$HOME/.agents/skills"
>   git clone https://github.com/themactep/thingino-skills.git /tmp/thingino-skills
>   cp -r /tmp/thingino-skills/skills/* "$HOME/.agents/skills/"
>   rm -rf /tmp/thingino-skills
>   echo "thingino-skills installed to ~/.agents/skills/"
> fi
> ```

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
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make rebuild-<pkg>   # dirclean + rebuild + reinstall + finalize
make build-all                  # builds every camera in configs/cameras/
make run CMD="bin/ffmpeg --help"  # QEMU run target binary
make ram-setup                  # once per boot: raise tmpfs inode limit for ram-build
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make ram-build   # cold build in tmpfs (RAM)
```

`ram-build` runs the whole output tree on a tmpfs to spare the SSD, then copies
artifacts back to disk and frees the RAM. It is for **cold builds** only (the
most disk-write-intensive case); incremental development builds (`make fast`)
should be done on a real disk. See `docs/build/makefile.md`.

- `CAMERA=` can be supplied interactively (uses `scripts/select_camera.sh`).
- `BOARD=` is an alias for `CAMERA=` (backward compat with CI).
- `WORKFLOW=1` skips dep check + interactive camera selection (CI use).
- `PRISTINE=1` disables user directory (`THINGINO_USER_DIR=/dev/null`).
- Output: `$(THINGINO_OUTPUT_ROOT_DIR)/<branch>/<camera>-<kernel>-<libc>[-<ip>]/`
  (`THINGINO_OUTPUT_ROOT_DIR` / `THINGINO_OUTPUT_DIR` override the output root/dir
  from the environment; default root is `output/`). Always check the env first
  when looking for build artifacts (`echo $THINGINO_OUTPUT_ROOT_DIR`) — the
  output tree is usually NOT inside the repo checkout.
- Download cache: `$(BR2_DL_DIR)` (default `dl/` next to the repo; on this
  machine `/home/paul/Files/thingino/dl`). Shared across worktrees — never
  clean it. `make download-cache` bundles it for offline CI builds.
- User config layer: `$(THINGINO_USER_DIR)` (default `user/` next to the repo;
  on this machine `/home/paul/.thingino/user`). Per-user/local overrides
  (`local.fragment`, `local.mk`, `overlay/`, ...); `PRISTINE=1` disables it by
  pointing it at `/dev/null`. See the config model section below.
  As with the output dir, read these from the environment
  (`echo $BR2_DL_DIR $THINGINO_USER_DIR`) before assuming they live in the
  checkout.
- No CI-integrated test suite for builds; validation is CI-only. Two QEMU
  test suites exist, each with its own README:
  - `scripts/qemu-test/` boots a real image and asserts the network surface
    (services, portal/provisioning, DHCPv4/v6, DNS, web UI, ONVIF, mDNS,
    NTP, syslog, link flap, persistence) with Playwright browser flows.
    Build with `make GROUP=testing CAMERA=qemu_t31x_eth fast`, run with
    `scripts/qemu-test/run.sh qemu_t31x_eth`. A profile is a directory
    under `configs/cameras-testing/` with a `qemu-test.json` and its
    `expected-checks.txt` contract; add a check by adding one row to the
    `SUITES` table in `scripts/qemu-test/qemutest/plan.py`.
  - `scripts/ota-tests/` covers the sysupgrade partition-fitting logic.

## Repo layout

```
configs/cameras/<camera_name>/   # per-camera defconfig + .config + uenv.txt + overlay/
package/<name>/                  # Buildroot packages (mk + Config.in)
overlay/                         # root filesystem overlay (applied to all builds)
board/ingenic/                   # DTB patches, post-build scripts, board files
scripts/                         # selection, OTA, TFTP, dep_check, misc helpers
                                  #   scripts/tts/ — TTS audio generation tool (models/
                                  #   and .venv/ are gitignored, ~315MB when installed)
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
`configs/fragments/toolchain/ext-gcc16-uclibc.fragment`) + **config fragments**
(per `# FRAG:` in defconfig) + **camera defconfig** + **U-Boot fragment** +
**user local.fragment** files. Template variables like `$(SOC_FAMILY)` are
substituted during assembly.

User config layers (scoped, each additive):
`user/<common>/` > `user/<camera>/` > `user/<camera>/<ip>/`
Each can contain `local.fragment`, `local.mk`, `local.uenv.txt`, `thingino.json`,
`prudynt.json`, `overlay/`, `opt/`.

Config fragments and per-camera overlay are merged at build time into the
rootfs and data partitions.

## SOC / kernel

SOC family is derived from `BR2_INGENIC_SOC_MODEL` two ways, and both are live.
For `.config`, `Config.soc.in` maps model to `BR2_SOC_FAMILY`. For make,
`thingino.mk` includes `soc/<vendor>/<family>.mk`, one file per SoC family,
which sets `SOC_FAMILY`, `SOC_ARCH`, `SOC_RAM_MB` and the U-Boot board names.
All of them are included and each opens with a `$(filter)` on its own models,
so exactly one file's body applies. Kconfig cannot run make and `thingino.mk`
needs the family before `.config` exists, so the map is stated in both places;
adding a SoC means adding it to both.
`thingino.mk` exports key variables: `SOC_FAMILY`, `SOC_MODEL`, `SOC_RAM_MB`,
`ISP_RMEM_MB`, `STREAMER`, etc.

Kernel branches are mapped from SOC family + version in `thingino.mk`.
Kernel versions: `3.10.14`, `4.4.94`, `7.1-rc1`.
Kernel source: `github.com/gtxaspec/thingino-linux`.

## Streamers

Default on `master` is `raptor` (`BR2_PACKAGE_THINGINO_STREAMER_RAPTOR`).
`ciao` still defaults to `prudynt`. Select explicitly via the Streamer choice
in menuconfig, or set `BR2_PACKAGE_THINGINO_STREAMER_PRUDYNT=y` /
`BR2_PACKAGE_THINGINO_STREAMER_RAPTOR=y` in a fragment.

## Firmware image

Three flash types are supported:

- **SFC (SPI NOR)**: `boot(320K) + env(64K) + backup(64K) + kernel(1600K) + rootfs.squashfs + data.jffs2`
  The `backup` partition holds a copy of the U-Boot environment for fail-safe updates.
- **SFC-NAND (SPI NAND)**: UBI image at 1 MiB offset with volumes:
  `uboot-env + kernel + rootfs(squashfs via ubiblock) + overlay(ubifs, autoresize)`
- **MMC (SD card)**: INGE header + SPL + U-Boot + FAT32 (uImage) + ext4 (rootfs)

Image assembly is done by `$(FIRMWARE_BIN_FULL)` rule in `Makefile`.

## U-Boot

Buildroot provides the base U-Boot version (`2013.07` by default; `2026.07`,
and `custom-fork` are also available via config fragments).
Thingino applies a single large per-version patch (e.g.
`package/all-patches/uboot/2013.07/0001-from-2013.07-to-thingino.patch`)
that adds all Ingenic-specific code. **Do not edit that patch.** If you need
U-Boot changes, add numbered follow-up patches in the same directory (e.g.
`0002-my-change.patch`) — Buildroot applies them in sort order after the large
patch. This is enforced by `scripts/check-do-not-edit.sh` (manifest:
`scripts/do-not-edit.txt`), wired into the pre-commit hook and CI.

## Package overrides

Uncomment `<pkg>_OVERRIDE_SRCDIR` in `local.mk` pointing to a local checkout
under `overrides/`. Overrides bypass Buildroot patches — apply them manually
before editing. Use `make rebuild-<pkg>` after changing overrides.

## SSH / SCP

`scp -O` is required (dropbear server). Default password is set in the defconfig.

## Style / pre-commit

- `package/thingino-webui/files/www/a/*.js` → formatted with **Prettier**.
- Staged `/bin/sh` scripts → formatted with **shfmt** (`shfmt -w -i 0 -ci`).
- Staged camera defconfigs → sorted with **`scripts/sort_defconfig.py`**
  (see `docs/dev/pre-commit-hooks.md` for the sort rules).
- `.githooks/pre-commit` must be active (`make setup-hooks`).
- **Shell scripts must be ASCII only.** No Unicode box-drawing, em dashes,
  braille spinners, emoji, or other non-ASCII characters in `.sh` files.
- **Cameras use BusyBox sh (ash), not bash.** Shebangs must be
  `#!/bin/sh`. Do not use bash-specific features (arrays, `[[`,
  `${var:offset:length}` slicing, `source`, `shopt`). BusyBox ash
  supports a subset of POSIX plus some extensions; when in doubt, stick
  to POSIX. `shfmt` parses scripts as POSIX by default — if it flags
  something, fix the script, not the shebang.
- **Files that ship on cameras carry no story.** Anything installed into
  the rootfs — webui JS (`package/*/files/www/`), CGI scripts, init
  scripts, `overlay/`, `board/` shell scripts — ships on a device where
  nobody reads the source. Keep comments short and only where they
  explain genuinely non-obvious control flow; a comment that restates
  the code ("redirect to login") or narrates history ("this was lost
  from a fork") is noise. The story — why a decision was made, what the
  old behavior did wrong, benchmark numbers — belongs in the commit
  message, PR description, or `docs/`, not in the code. Good code
  should speak for itself.

## Container Builds

```bash
./build-container.sh              # build firmware in container
./build-container.sh shell        # drop into container shell
make -f Makefile.container container-pull  # pull container image only
```

Container engine auto-detects podman → docker fallback.

## Parallel development (git worktrees)

One task, one branch, one worktree, one agent. See `docs/dev/worktrees.md`.

```bash
scripts/worktree.sh create <branch> [base]   # worktree + buildroot submodule + patches + shared dl
scripts/worktree.sh sync                     # rebase onto origin/master (NOT `make update`!)
scripts/worktree.sh remove <branch>          # after PR merge; branch is preserved
scripts/worktree.sh list
```

- Never run `make update` in a feature worktree — use `sync`.
- Container builds don't work from linked worktrees (`.git` gitfile path); build on host.
- `local.mk`, `user/`, `overrides/` are gitignored and not carried into new worktrees.

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
- **Never search outside the working directory!** If you need something you cannot
  find - ask the user. **Full home search is prohibited under any circumstances!**
- Running rebuilds always preserve the full compilation log to grep for data
  later instead of live-grepping the output.
- Rebuilding a package, use both CAMERA and IP values. If you do not know the
  correct camera's IP address - ask the user for help.
- Use modern effective tools: ripgrep instead of just grep.
- **Never flash or upload** anything to the camera unless you were explicitly
  ordered to do so by the user.
- **Never invent or type git hashes manually.** Always obtain the exact
  full commit hash from the source of truth (the actual git repository the
  hash belongs to — run `git rev-parse` or `git log` in that repo). After
  writing a hash into a `.mk`, `.patch`, or any other file, verify it against
  the repo with `git cat-file -t <hash>`. A single mistyped hex digit
  produces a hash that looks valid but is unreachable by any tool.
  - Use `scripts/update_packages.py <pattern>` to update `*_VERSION` hashes
    in package `.mk` files.  It fetches the remote, computes the correct
    hash, and prompts before updating.  Run it interactively; if that is
    not possible, ask the user to run it.
  - When the script breaks because an existing hash is bogus (the remote
    doesn't have it), fix the hash in the `.mk` to a real commit on the
    remote first, commit that correction, then re-run the script.
- Cameras may use an NFS share mounted to /mnt/nfs. Some packages copy compiled 
  file to the shared directory on the PC. The file then can be acceessed on the
  camera from the mounted share. E.g. prudynt is copied to /nfs/prudynt and is
  accessible as /mnt/nfs/prudynt on the camera. The can be used for rapid development.

## WebUI Plugins

Optional packages can contribute pages, scripts, and navigation items to the
Thingino Web UI through a build-time manifest system.  See
[docs/dev/plugin-system.md](docs/dev/plugin-system.md) for the full architecture.

### Quickstart for plugin authors

1. Create your package normally in `package/<name>/`.
2. Create a manifest at `package/<name>/files/<name>.webui.json` following the
   schema in `docs/dev/plugin-system.md` §3.
3. In your package's `.mk`, add the webui dependency:
   ```make
   ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
   MYPLUGIN_DEPENDENCIES += thingino-webui
   endif
   ```
4. Install your web files *and the manifest* in the install step:
   ```make
   define MYPLUGIN_INSTALL_WWW_CMDS
       $(INSTALL) -D -m 0644 $(MYPLUGIN_PKGDIR)/files/www/page.html \
           $(TARGET_DIR)/var/www/page.html
       $(INSTALL) -D -m 0644 $(MYPLUGIN_PKGDIR)/files/www/a/script.js \
           $(TARGET_DIR)/var/www/a/script.js
       $(INSTALL) -D -m 0755 $(MYPLUGIN_PKGDIR)/files/www/x/endpoint.cgi \
           $(TARGET_DIR)/var/www/x/endpoint.cgi
       $(INSTALL) -D -m 0644 $(MYPLUGIN_PKGDIR)/files/<name>.webui.json \
           $(TARGET_DIR)/var/www/a/plugins/<name>.webui.json
   endef
   ```
5. Validate with `scripts/check-plugins.sh` before building.

### Manifest basics

| Field | Purpose |
|-------|---------|
| `nav` | Menu items to inject into standard sections (`ddSettings`, `ddTools`, etc.) |
| `scripts` | JS files loaded on **every** page (keep these small) |
| `styles` | CSS files loaded on every page (rarely needed) |
| `preview.scripts` | JS files loaded only on the preview page |
| `preview.html` | HTML snippet injected into the preview page body |
| `featureFlags` | Key-value pairs merged into `thinginoUIConfig.device` |
| `pages` | Declared HTML pages (for conflict detection) |
| `cgi` | Declared CGI endpoints (for conflict detection) |

### Position values for nav items

- `"append"` — at end of section (default)
- `"prepend"` — at beginning of section
- `"after:<label>"` — after the item with matching label
- `"before:<label>"` — before the item with matching label
- `"index:<n>"` — at 0-based position

### Existing plugins (for reference)

- `package/thingino-motors/files/motors.webui.json` — Pan/Tilt motors
- `package/wyze-accessory/files/doorbell.webui.json` — Doorbell Chime

## Important constraints

- Repo path must not contain spaces (checked by `dep_check.sh`).
- Only `x86_64` and `aarch64` hosts are supported.
- `make update` applies Buildroot patches from `package/all-patches/buildroot/` —
  do not run `git pull` directly.
- Keep changes surgical — this is a cross-compilation build system where a
  mistake can waste 30+ minutes of rebuild time.
