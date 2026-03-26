# User-Specific Local Build Settings

Thingino exposes a user-local customization tree through `THINGINO_USER_DIR`.
By default it points to `user/` in the firmware checkout:

```make
THINGINO_USER_DIR ?= $(BR2_EXTERNAL)/user
```

This directory is intended for machine-local or user-specific build inputs that
should not be committed into camera configs, package sources, or the shared
root filesystem overlay.

The customization model is now layered. Common settings live under
`user/common/`, while camera-specific and device-specific overrides live
directly under `user/<camera>/`:

```text
user/common/
user/<camera>/
user/<camera>/<ip>/
```

For all supported file types, precedence is:

1. `user/common/`
2. `user/<camera>/`
3. `user/<camera>/<ip>/`

Later layers override or extend earlier ones.

## Default location and overriding it

Default location:

```text
user/
```

You can point it elsewhere for a specific build:

```bash
THINGINO_USER_DIR=$HOME/thingino-user CAMERA=atom_cam2_t31x_gc2053_atbm6031 make
```

You can also preset it in your shell environment:

```bash
export THINGINO_USER_DIR=$HOME/thingino-user
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make
```

The build only consumes specific files and subdirectories from that tree. It is
not a generic catch-all include directory.

## Layered lookup model

For a build such as:

```bash
CAMERA=atom_cam2_t31x_gc2053_atbm6031 IP=192.168.88.31 make
```

the build looks for user customizations in this order:

```text
user/common/
user/atom_cam2_t31x_gc2053_atbm6031/
user/atom_cam2_t31x_gc2053_atbm6031/192.168.88.31/
```

If a file or directory exists in more than one location, the narrower scope
wins:

- global values provide defaults
- camera-scoped values override global ones for that camera family
- device-scoped values override both for the selected `IP`

The active device scope follows the current session `IP` value. If you want to
return to a generic build that ignores `user/<camera>/<ip>/`, run:

```bash
IP= make
```

## What the build reads from `THINGINO_USER_DIR`

### `local.fragment`

Paths:

```text
user/common/local.fragment
user/<camera>/local.fragment
user/<camera>/<ip>/local.fragment
```

Purpose:

- Appends extra Buildroot config symbols to the generated `OUTPUT_DIR/.config`
- Useful for temporary package enables, debug toggles, or local experiments

Build behavior:

- Added as a configuration dependency
- Concatenated into `OUTPUT_DIR/.config` before `olddefconfig`
- Applied in scope order: global, then camera, then device
- Participates in config regeneration checks

Typical use:

```text
BR2_PACKAGE_STRACE=y
BR2_ENABLE_DEBUG=y
```

### `local.mk`

Paths:

```text
user/common/local.mk
user/<camera>/local.mk
user/<camera>/<ip>/local.mk
```

Purpose:

- Adds user-scoped Buildroot package overrides such as `OVERRIDE_SRCDIR`
- Useful when you want per-user, per-camera, or per-device source overrides
  without putting them in the repository root `local.mk`

Build behavior:

- Matching files are concatenated into `OUTPUT_DIR/local.mk`
- Applied in scope order: global, then camera, then device
- Loaded by Thingino's aggregated package override entry point together with the
  repository root `local.mk`

Typical use:

```make
THINGINO_OVERRIDES_DIR = $(BR2_EXTERNAL_THINGINO_PATH)/overrides
INGENIC_SDK_OVERRIDE_SRCDIR = $(THINGINO_OVERRIDES_DIR)/ingenic-sdk
```

### `thingino.json`

Paths:

```text
user/common/thingino.json
user/<camera>/thingino.json
user/<camera>/<ip>/thingino.json
```

Purpose:

- Adds or overrides entries in `/etc/thingino.json`
- This is the user-scoped JSON add-on hook for Thingino core settings

Build behavior:

1. `configs/common.thingino.json` is installed first
2. The camera's `thingino.json` is imported next, if present
3. User JSON files are imported in scope order: global, then camera, then device

That means device-scoped user values win over camera-scoped user values, which
win over global user values, which win over common and camera defaults.

Example:

```json
{
  "webui": {
    "paranoid": true
  },
  "mqtt_sub": {
    "enabled": true,
    "host": "192.168.1.10",
    "port": 1883
  }
}
```

### `motors.json`

Paths:

```text
user/common/motors.json
user/<camera>/motors.json
user/<camera>/<ip>/motors.json
```

Purpose:

- Adds or overrides entries in `/etc/motors.json`
- This is the user-scoped JSON add-on hook for PTZ and motor tuning values

Build behavior:

1. The package default `motors.json` is installed first
2. The camera's `motors.json` is imported next, if present
3. User `motors.json` files are imported in scope order: global, then camera, then device

That means device-scoped user values win over camera-scoped user values, which
win over global user values, which win over package and camera defaults.

Example:

```json
{
  "motors": {
    "steps_pan": 2000,
    "steps_tilt": 1100,
    "speed_pan": 8,
    "speed_tilt": 8
  }
}
```

### `overlay/`

Paths:

```text
user/common/overlay/
user/<camera>/overlay/
user/<camera>/<ip>/overlay/
```

Purpose:

- Seeds files into the writable config overlay partition
- Best for user-specific config files, init scripts, certificates, and other
  files you want present on first boot but still editable on the device

Build behavior:

- `OUTPUT_DIR/config/` is rebuilt from scratch for each config image
- Overlay directories are copied in scope order: global, then camera, then device
- Packed into `images/config.jffs2`
- Not included in `rootfs.squashfs`
- Not included in `rootfs.tar`

Path mapping mirrors the target filesystem. For example:

```text
user/common/overlay/etc/init.d/S99local
```

becomes:

```text
/etc/init.d/S99local
```

Use this when you want to provide a full file as-is.

If the same file exists in multiple overlay scopes, the device-scoped copy wins.

### `opt/`

Paths:

```text
user/common/opt/
user/<camera>/opt/
user/<camera>/<ip>/opt/
```

Purpose:

- Adds user content to the extras partition mounted at `/opt`
- Suitable for optional binaries, models, helper scripts, and other large or
  user-managed add-ons that do not belong in the main rootfs

Build behavior:

- Files from `OUTPUT_DIR/target/opt/` are first copied into `OUTPUT_DIR/extras/`
- Then user `opt/` directories are copied in scope order: global, then camera,
  then device
- The result is packed into `images/extras.jffs2`

Important detail:

- The build now recreates `OUTPUT_DIR/extras/` before layering user content
- If the same file exists in multiple scopes, the device-scoped copy wins

### `local.uenv.txt`

Paths:

```text
user/common/local.uenv.txt
user/<camera>/local.uenv.txt
user/<camera>/<ip>/local.uenv.txt
```

Purpose:

- Adds local U-Boot environment entries
- Useful for extra boot arguments or user-specific environment variables

Build behavior:

1. `configs/common.uenv.txt` is read
2. The camera's `<camera>.uenv.txt` is read
3. User U-Boot fragments are read in scope order: global, then camera, then device
4. Comment lines and blank lines are removed
5. The combined file is deduplicated with `sort -u`
6. Generated partition-specific lines such as `mtdparts`, `bootcmd`,
   `kern_addr`, and `kern_size` are rewritten at the end

In practice, use this for additional environment keys, not for replacing the
auto-generated partition layout.

## JSON add-ons: what is supported and what is not

The user-scoped JSON import hooks wired into the build are:

```text
user/common/thingino.json
user/<camera>/thingino.json
user/<camera>/<ip>/thingino.json

user/common/motors.json
user/<camera>/motors.json
user/<camera>/<ip>/motors.json
```

Other JSON files are handled differently:

- `/etc/thingino.json` supports user-layered import through `thingino.json`
- `/etc/motors.json` supports user-layered import through `motors.json`
- `/etc/prudynt.json` camera defaults are controlled through camera-scoped
  `prudynt.json`, not through `THINGINO_USER_DIR`
- Other JSON configs such as `/etc/prudynt.json` or `/etc/timelapse.json` do not
  have a generic user-side merge hook in the current build system

If you need to seed one of those files from your user tree, provide the full file
through `user/common/overlay/`, for example:

```text
user/common/overlay/etc/prudynt.json
user/common/overlay/etc/timelapse.json
```

The same pattern also works in camera-scoped and device-scoped overlay trees.

That replaces the file content in the config overlay rather than merging JSON
objects key-by-key.

## Choosing the right mechanism

Use `local.fragment` when you need to change Buildroot symbols.

Use `local.mk` when you need Buildroot `OVERRIDE_SRCDIR` or other package
override variables.

Use `thingino.json` when you need to add or override keys in
`/etc/thingino.json`.

Use `user/common/overlay/` when you need to place complete files into the writable
config partition.

Use `user/common/opt/` when you need files in the extras partition at `/opt`.

Use `local.uenv.txt` for additional U-Boot environment variables.

Use camera-scoped paths when the customization applies to every device of one
camera model.

Use device-scoped paths when the customization should apply only to one unit,
selected by the build-time `IP` value.

## Minimal example tree

```text
user/
├── common/
│   ├── local.fragment
│   ├── local.mk
│   ├── thingino.json
│   ├── local.uenv.txt
│   ├── opt/
│   │   └── bin/
│   │       └── my-helper
│   └── overlay/
│       └── etc/
│           ├── init.d/
│           │   └── S99local
│           └── ssl/
│               └── my-ca.pem
└── atom_cam2_t31x_gc2053_atbm6031/
  ├── local.fragment
  ├── local.mk
  ├── thingino.json
  ├── local.uenv.txt
  └── 192.168.88.31/
    ├── local.fragment
    ├── local.mk
    ├── thingino.json
    ├── local.uenv.txt
    └── overlay/
      └── etc/
        └── hostname
```

## Related documents

- `docs/overlayfs.md` explains why `user/common/overlay/` ends up in the
   writable overlay partition
- `docs/local-overrides.md` covers package source overrides through `local.mk`
- `docs/makefile.md` covers the general build workflow and config generation