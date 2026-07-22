# Package Bundle System

Thingino's package bundle system lets you install precompiled software on a
running camera **without reflashing firmware**.  A bundle is a single `.tgz`
(Thingino Package Bundle) file — a compressed tar archive with a JSON manifest —
that is downloaded to the camera and extracted on top of the live filesystem.

Because Thingino uses an **overlayfs** (squashfs root + writable JFFS2 data
partition), files extracted by a bundle land in the writable upper layer and
survive reboots.  The package manager tracks every installed file so packages
can be cleanly removed.

> **Status:** Phase 1 — self-contained bundles, no dependency resolver, no
> kernel modules.  This is intentionally simple and incremental.

---

## Table of contents

- [Motivation](#motivation)
- [Architecture](#architecture)
- [Enabling the system](#enabling-the-system)
- [Bundle format](#bundle-format)
- [Creating bundles](#creating-bundles)
- [Installing on device](#installing-on-device)
- [Storage tiers](#storage-tiers)
- [Removing packages](#removing-packages)
- [Listing and inspecting](#listing-and-inspecting)
- [Bundle definition reference](#bundle-definition-reference)
- [Manifest reference](#manifest-reference)
- [Walkthrough: go2rtc bundle](#walkthrough-go2rtc-bundle)
- [Security considerations](#security-considerations)
- [Limitations & future work](#limitations--future-work)

---

## Motivation

Today, adding a package to a Thingino camera means:

1. Enabling the package in menuconfig
2. Rebuilding the entire firmware (`make clean; make`)
3. Flashing the full `.bin` image via OTA or programmer
4. Reconfiguring the camera from scratch

This is heavyweight.  Many users want to add a single tool — `go2rtc`,
`zerotier-one`, `telegrambot` — to an already-configured camera.  The bundle
system makes that a single command:

```sh
# On the camera:
thingino-pkg install https://bundles.thingino.com/t31/go2rtc-1.9.14-t31.tgz
```

---

## Architecture

### How it fits in the filesystem

```
┌─────────────────────────────────┐
│  /  (overlayfs, writable)       │
│    ┌─ upper: /overlay (JFFS2)  │  ← bundle files land here
│    └─ lower: /rom    (squashfs) │  ← read-only factory image
└─────────────────────────────────┘
```

When a bundle extracts files to `/usr/bin/go2rtc`, overlayfs writes them to the
data partition (`/overlay`).  The file appears at `/usr/bin/go2rtc` and survives
reboots because the data partition is persistent JFFS2.

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `thingino-pkg` | `/usr/sbin/thingino-pkg` | Device-side package manager (shell script) |
| `make-bundle.sh` | `scripts/make-bundle.sh` | Build-side bundle producer |
| `.bundle` files | `package/<name>/<name>.bundle` | Per-package file manifests |
| `BR2_THINGINO_PACKAGES` | `Config.in` | Buildroot config flag |

---

## Enabling the system

The bundle system is **opt-in**.  Enable it in menuconfig:

```
Extra Packages  →  Package Bundle System  →  [*] thingino-pkg
```

Or add to a config fragment:

```
BR2_THINGINO_PACKAGES=y
```

This selects two packages:

| Package | Purpose |
|---------|---------|
| `thingino-pkg` | The shell-script package manager |
| `thingino-jct` | JSON config tool (used for manifest parsing) |

Both are small — together they add roughly 60 KB to the firmware.

---

## Bundle format

A `.tgz` file is a **gzip-compressed tar archive** containing:

```
<name>-<version>-<soc_family>.tgz
├── thingino-pkg.json        ← manifest (always the first entry)
├── usr/bin/go2rtc
├── etc/go2rtc.yaml
└── etc/init.d/S97go2rtc
```

All file paths are **relative to `/`** (no leading slash).  The manifest is
always named `thingino-pkg.json` and must be the first file in the archive so
the device can extract and inspect it before committing to the full install.

---

## Creating bundles

### Prerequisites

- A completed firmware build for the target camera (`CAMERA=... make`)
- The package **must be enabled** in the Buildroot config (e.g. via
  `make menuconfig`).  It does *not* need to be included in the original
  firmware build — you can enable it after the fact and `make bundle-<pkg>`
  will build only the new package.
- A `.bundle` file in the package directory

### Via Make (recommended)

```bash
# 1. Enable the package in menuconfig
make menuconfig   # e.g. Streamer Packages → [*] go2rtc

# 2. Build and bundle (single command)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make bundle-go2rtc
```

This single command:

1. **Cleans** any previous build of the package (`<pkg>-dirclean`)
2. **Builds** the package via Buildroot's `<pkg>` target — configures, compiles,
   and installs into `per-package/<pkg>/target/`
3. **Strips** ELF binaries using the cross-compile strip tool
4. **Detects WebUI plugins**: if a `<pkg>.webui.json` manifest exists in the
   package's `files/` directory, rebuilds `thingino-webui` and runs
   `target/` directory, then runs `assemble_plugins.py` to inject the plugin
5. **Collects** the files listed in the `.bundle` manifest from both the
   per-package target and the global `target/` directory
6. Produces `<output-dir>/bundles/<name>-<version>-<soc_family>.tgz`

### Via script (advanced)

```bash
./scripts/make-bundle.sh <package> <camera> <output-dir>
```

The script expects the package to already be built.  It reads files from
`per-package/<pkg>/target/` (preferred) or the global `target/` directory.

### The `.bundle` file

Create `package/<name>/<name>.bundle` alongside the package's `.mk` and
`Config.in`.  It lists one file path per line (relative to target root, no
leading slash):

```
# package/go2rtc/go2rtc.bundle
# Files included in the go2rtc bundle
usr/bin/go2rtc
etc/go2rtc.yaml
etc/init.d/S97go2rtc
```

Lines starting with `#` are comments.  Blank lines are ignored.

### How it works

The `make bundle-<pkg>` target:

1. Runs `<pkg>-dirclean` to clean any previous build artifacts
2. Runs `<pkg>` — Buildroot configures, builds, and installs the package into
   `per-package/<pkg>/target/`
3. If a `<pkg>.webui.json` manifest exists, **rsyncs** the plugin's web files
   into the global `target/` and runs `assemble_plugins.py` directly to inject
   the plugin into `plugins.js` and the HTML pages
   (see [WebUI plugins](#webui-plugins) below)
4. Calls `make-bundle.sh`, which:
   - Reads the `.bundle` file from `package/<pkg>/`
   - Copies listed files, first from `per-package/<pkg>/target/`, then falling
     back to the global `target/` for files assembled there (e.g. WebUI output)
   - Strips ELF binaries with the cross-compile strip tool
   - Determines the package version from `build/<pkg>-<version>/`
   - Reads `SOC_FAMILY` from the build config
   - Generates the `.tgz` archive with embedded `thingino-pkg.json` manifest

### WebUI plugins

Packages that use the [WebUI plugin system](plugin-system.md) can include their
web files in the bundle.  When `make bundle-<pkg>` detects a
`files/<pkg>.webui.json` manifest, it rsyncs the plugin files into the
global target and runs `assemble_plugins.py` directly.  The assembled output
(`plugins.js`, modified HTML pages, injected script tags) is included in the
bundle.

**Caveat**: the assembled webui files overwrite the camera's existing webui
pages.  This is fine for a single plugin, but installing multiple webui plugins
from separate bundles may cause the last-installed plugin's `plugins.js` to
overwrite earlier ones.  Full multi-plugin support is a Phase 2 feature.

The `.bundle` file for a webui plugin should list:
- The plugin's own files (HTML pages, JS, CGI, `.webui.json` manifest)
- The assembled `var/www/a/plugins.js`

Example from `package/telegrambot/telegrambot.bundle`:

```
usr/sbin/telegrambot
etc/init.d/S93telegrambot
etc/telegrambot.json
var/www/config-telegrambot.html
var/www/a/config-telegrambot.js
var/www/x/json-telegrambot.cgi
var/www/x/ctl-telegrambot.cgi
var/www/a/plugins/telegrambot.webui.json
var/www/a/plugins.js
```

---

## Installing on device

### Prerequisites

- The camera must have `thingino-pkg` installed (built with
  `BR2_THINGINO_PACKAGES=y`)
- Network access to download bundles, or the bundle file already on the camera

### Commands

```sh
thingino-pkg install <url|path> [-t sdcard|overlay|tmp|auto]
thingino-pkg remove  <name>
thingino-pkg list
thingino-pkg info    <name>
thingino-pkg files   <name>
```

### Install from URL

```sh
thingino-pkg install https://bundles.thingino.com/t31/go2rtc-1.9.14-t31.tgz
```

The script:

1. Downloads the bundle to `/tmp`
2. Extracts the `thingino-pkg.json` manifest and validates it:
   - **SOC check**: manifest `soc_family` must match the device (`soc -f`)
   - **Conflict check**: manifest `conflicts` list checked against installed packages
   - **Already-installed check**: refuses if an older version is present (remove first)
3. Picks a storage tier based on available space
4. Extracts files
5. Saves manifest and file list to `/overlay/.pkg/`
6. Runs the `post_install` hook (if present)

### Install from local file

```sh
# scp the bundle to the camera first
scp -O go2rtc-1.9.14-t31.tgz root@192.168.1.42:/tmp/

# Then install
ssh root@192.168.1.42 thingino-pkg install /tmp/go2rtc-1.9.14-t31.tgz
```

### Force a specific tier

```sh
# Force SD card (fails if no SD card present)
thingino-pkg install /tmp/bundle.tgz -t sdcard

# Force overlay even if tight on space
thingino-pkg install /tmp/bundle.tgz -t overlay

# Volatile install for testing (lost on reboot)
thingino-pkg install /tmp/bundle.tgz -t tmp
```

---

## Storage tiers

The installer picks a tier automatically based on available space, or you can
force one with `-t`.

| Tier | Location | Size | Persistent | Best for |
|------|----------|------|-----------|----------|
| **overlay** | `/` → `/overlay/` (JFFS2) | 8MB flash: ~0.5 MB free<br>16MB flash: ~8 MB free | Yes | Small packages: config tools, small daemons |
| **sdcard** | `/mnt/mmcblk0p1/pkg/<name>/` + symlinks | GBs | Yes | Large packages: go2rtc, zerotier |
| **tmp** | `/tmp/pkg/<name>/` | RAM-sized | **No** (volatile) | Testing before committing |

### How auto-selection works

```
size_kb < overlay_free_kb  →  overlay
size_kb ≥ overlay_free_kb  →  sdcard (if available)
no SD card available        →  error, suggest -t tmp
```

### SD card behavior

Files are extracted to `/mnt/mmcblk0p1/pkg/<name>/` and **symlinked** into their
target paths.  For example, a bundle containing `usr/bin/go2rtc` is extracted
to:

```
/mnt/mmcblk0p1/pkg/go2rtc/usr/bin/go2rtc
```

and symlinked:

```
/usr/bin/go2rtc → /mnt/mmcblk0p1/pkg/go2rtc/usr/bin/go2rtc
```

**Caveat**: VFAT-formatted SD cards do not support symlinks or executable
permission bits.  Use ext4-formatted cards for SD-based package installs.

---

## Removing packages

```sh
thingino-pkg remove go2rtc
```

This:

1. Runs the `pre_remove` hook (e.g., stops the service)
2. Deletes every file listed in the package's file manifest
3. Removes symlinks (for SD card installs)
4. Deletes the SD card package directory (if applicable)
5. Removes the manifest from `/overlay/.pkg/manifests/`

Files that were **modified** after install are still deleted — the manifest
tracks what the bundle owns, not what the user has done since.  Back up
customized configs before removal.

---

## Listing and inspecting

```sh
# Show installed packages
thingino-pkg list
#   go2rtc                  1.9.14       5200 KB  Camera streaming application
#   mbedtls-certgen         1.0            12 KB  TLS certificate generator
#   2 package(s) installed

# Show manifest
thingino-pkg info go2rtc

# Show all files owned by a package
thingino-pkg files go2rtc
#   /usr/bin/go2rtc                  (5234567 bytes)
#   /etc/go2rtc.yaml                 (234 bytes)
#   /etc/init.d/S97go2rtc            (567 bytes)
```

---

## Bundle definition reference

### `.bundle` file

Location: `package/<name>/<name>.bundle`

```
# comment
path/relative/to/target/root
another/file
```

Rules:

- One file path per line
- Paths are relative to `/` (no leading slash)
- `#` starts a comment (must be at beginning of line)
- Blank lines are ignored
- Directory paths are supported (copied recursively)

### Checklist for a good bundle

1. **Self-contained**: the package should not rely on files from other packages
   unless they are guaranteed to be in the base firmware (e.g., libc, busybox).
2. **Static or bundled libs**: dynamic linking against libraries not in the base
   image will fail.  Go binaries with `CGO_ENABLED=0` are ideal.
3. **SOC-tagged**: bundles are SOC-family-specific (`t31`, `t40`, etc.).
   A bundle built for T31 will refuse to install on T40.
4. **No kernel modules**: Phase 1 does not handle `.ko` files or `depmod`.
5. **Config files**: include sensible defaults; the user can edit them after
   install (they're in the writable overlay).

---

## Manifest reference

### `thingino-pkg.json`

Embedded in every `.tgz` file.  Stored on device at
`/overlay/.pkg/manifests/<name>.json` after install.

```json
{
  "name": "go2rtc",
  "version": "1.9.14",
  "soc_family": "t31",
  "size_kb": 5200,
  "description": "Camera streaming application",
  "requires": [],
  "conflicts": ["lightnvr"],
  "post_install": "/etc/init.d/S97go2rtc start || true",
  "pre_remove": "/etc/init.d/S97go2rtc stop 2>/dev/null || true"
}
```

| Field | Required | Type | Purpose |
|-------|----------|------|---------|
| `name` | **Yes** | string | Package identifier, must match install directory |
| `version` | No | string | Human-readable version |
| `soc_family` | **Yes** | string | Target SOC family (`t31`, `t40`, `a1`, etc.) |
| `size_kb` | No | integer | Approximate installed size in KB (for space checks) |
| `description` | No | string | One-line summary |
| `requires` | No | string[] | *(Phase 2)* Package names required before install |
| `conflicts` | No | string[] | Package names that must NOT be installed |
| `post_install` | No | string | Shell command run after extraction |
| `pre_remove` | No | string | Shell command run before file removal |

### Hooks

**`post_install`** — typically used to start a service:

```json
"post_install": "/etc/init.d/S97go2rtc start || true"
```

**`pre_remove`** — typically used to stop a service before files are deleted:

```json
"pre_remove": "/etc/init.d/S97go2rtc stop 2>/dev/null || true"
```

Hooks are run with `eval` in the package manager's shell context.  They should
be idempotent and never fail hard — failures are logged but do not abort the
operation.

---

## Walkthrough: go2rtc bundle

### 1. Create the `.bundle` file

`package/go2rtc/go2rtc.bundle`:

```
usr/bin/go2rtc
etc/go2rtc.yaml
etc/init.d/S97go2rtc
```

### 2. Enable and build

Enable `BR2_THINGINO_PACKAGES=y` in your config (already done if you followed
[Enabling the system](#enabling-the-system)).  Then enable go2rtc itself via
menuconfig and bundle it:

```bash
# Enable go2rtc in menuconfig
make menuconfig   # Streamer Packages → [*] go2rtc

# First build the base firmware (only needed once)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make

# Build and bundle go2rtc (dirclean → build → strip → pack)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make bundle-go2rtc
```

Output:

```
>>> go2rtc 1.9.14 Building
...
>>> go2rtc 1.9.14 Installing to target
Stripping binaries...
Collecting files from .../per-package/go2rtc/target...
  usr/bin/go2rtc
  etc/go2rtc.yaml
  etc/init.d/S97go2rtc
Collected 3 files

Bundle created: .../bundles/go2rtc-1.9.14-t31.tgz
  Package:    go2rtc 1.9.14
  SOC family: t31
  Files:      3
  Size:       5386 KB
```

### 3. Transfer and install

```bash
scp -O output/.../bundles/go2rtc-1.9.14-t31.tgz root@192.168.1.42:/tmp/
ssh root@192.168.1.42 thingino-pkg install /tmp/go2rtc-1.9.14-t31.tgz
```

Camera output:

```
Installing go2rtc 1.9.14 to sdcard...
Bundle needs 5386KB, overlay has 312KB free
→ installing to SD card (/mnt/mmcblk0p1/pkg/go2rtc)
Creating symlinks...
Running post-install...
Done: go2rtc 1.9.14 (3 files)
```

### 4. Verify

```bash
ssh root@192.168.1.42 thingino-pkg list
#   go2rtc                  1.9.14      2183 KB  Camera streaming application
#   1 package(s) installed

ssh root@192.168.1.42 thingino-pkg files go2rtc
#   /usr/bin/go2rtc           → /mnt/mmcblk0p1/pkg/go2rtc/usr/bin/go2rtc
#   /etc/go2rtc.yaml                            (234 bytes)
#   /etc/init.d/S97go2rtc                       (567 bytes)
```

---

## Security considerations

1. **No signature verification (Phase 1)** — bundles are plain tarballs.
   Only install bundles from sources you trust.  Signature verification is a
   Phase 2 feature.

2. **Hooks run as root** — `post_install` and `pre_remove` scripts in the
   manifest execute with full root privileges.  Inspect manifests before
   installing untrusted bundles.

3. **SOC mismatch protection** — the installer refuses to install a bundle
   built for a different SOC family.  This prevents binary incompatibility but
   is not a security boundary.

4. **File overwrite protection** — `thingino-pkg` tracks which files belong to
   which package and will not overwrite files owned by another bundle.  It does
   *not* protect against overwriting files from the base firmware (those in the
   squashfs are safe since they are read-only; but files previously created in
   the overlay by the user or other means may be overwritten).

5. **Data partition wear** — JFFS2 is flash.  Repeated install/remove cycles
   will cause wear on the data partition.  This is no different from normal
   overlay writes.

---

## Limitations & future work

### Phase 1 limitations

| Limitation | Impact | Workaround |
|-----------|--------|------------|
| No dependency resolution | Bundles must be self-contained | Static linking, vendored libs |
| No kernel modules | Can't add `.ko` files | Rebuild firmware instead |
| No version upgrade path | Must remove before reinstalling | `remove` then `install` |
| No signature verification | Malicious bundles could run hooks | Only install from trusted sources |
| Busybox `wget` only | No HTTPS cert validation | Use HTTPS URLs; full TLS verification planned |
| SD card VFAT | No symlinks, no +x bits | Use ext4-formatted SD card |
| WebUI plugin multi-install | Installing two webui plugin bundles overwrites `plugins.js` | Install webui plugins together in one bundle, or rebuild firmware |

### Planned for Phase 2

- Package repository index (`Packages.json`) with auto-discovery
- `thingino-pkg upgrade <name>` — in-place upgrade
- `thingino-pkg search <term>` — search configured repos
- Bundle signing with Ed25519
- Kernel module bundles with `depmod` integration
- Dependency resolution
- Size estimation before download
- WebUI integration (install/remove from the camera's web interface)

### Planned for Phase 3

- Delta bundles (binary patches for large packages)
- Rollback support (keep previous version until new one is verified)
- Auto-update daemon
- Per-package build isolation (`BR2_PER_PACKAGE_DIRECTORIES`) for automatic
  bundle production
