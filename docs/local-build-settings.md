# User-Specific Local Build Settings

Thingino exposes a user-local customization tree through `THINGINO_USER_DIR`.
By default it points to `user/` in the firmware checkout:

```make
THINGINO_USER_DIR ?= $(BR2_EXTERNAL)/user
```

This directory is intended for machine-local or user-specific build inputs that
should not be committed into camera configs, package sources, or the shared
root filesystem overlay.

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

## What the build reads from `THINGINO_USER_DIR`

### `local.fragment`

Path:

```text
user/local.fragment
```

Purpose:

- Appends extra Buildroot config symbols to the generated `OUTPUT_DIR/.config`
- Useful for temporary package enables, debug toggles, or local experiments

Build behavior:

- Added as a configuration dependency
- Concatenated into `OUTPUT_DIR/.config` before `olddefconfig`
- Participates in config regeneration checks

Typical use:

```text
BR2_PACKAGE_STRACE=y
BR2_ENABLE_DEBUG=y
```

### `local.thingino.json`

Path:

```text
user/local.thingino.json
```

Purpose:

- Adds or overrides entries in `/etc/thingino.json`
- This is the user-scoped JSON add-on hook for Thingino core settings

Build behavior:

1. `configs/common.thingino.json` is installed first
2. The camera's `thingino-camera.json` is imported next, if present
3. `user/local.thingino.json` is imported last, if present

That means user values win over common and camera values for the same keys.

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

### `overlay/`

Path:

```text
user/overlay/
```

Purpose:

- Seeds files into the writable config overlay partition
- Best for user-specific config files, init scripts, certificates, and other
  files you want present on first boot but still editable on the device

Build behavior:

- Synchronized with `rsync --delete` into `OUTPUT_DIR/config/`
- Packed into `images/config.jffs2`
- Not included in `rootfs.squashfs`
- Not included in `rootfs.tar`

Path mapping mirrors the target filesystem. For example:

```text
user/overlay/etc/init.d/S99local
```

becomes:

```text
/etc/init.d/S99local
```

Use this when you want to provide a full file as-is.

### `opt/`

Path:

```text
user/opt/
```

Purpose:

- Adds user content to the extras partition mounted at `/opt`
- Suitable for optional binaries, models, helper scripts, and other large or
  user-managed add-ons that do not belong in the main rootfs

Build behavior:

- Files from `OUTPUT_DIR/target/opt/` are first copied into `OUTPUT_DIR/extras/`
- Then `user/opt/` is copied into the same extras staging directory
- The result is packed into `images/extras.jffs2`

Important detail:

- The build does not delete old files already sitting in `OUTPUT_DIR/extras/`
- If you remove something from `user/opt/`, clean the extras staging area or run
  a clean build before repacking

### `local.uenv.txt`

Path:

```text
user/local.uenv.txt
```

Purpose:

- Adds local U-Boot environment entries
- Useful for extra boot arguments or user-specific environment variables

Build behavior:

1. `configs/common.uenv.txt` is read
2. The camera's `<camera>.uenv.txt` is read
3. `user/local.uenv.txt` is read
4. Comment lines and blank lines are removed
5. The combined file is deduplicated with `sort -u`
6. Generated partition-specific lines such as `mtdparts`, `bootcmd`,
   `kern_addr`, and `kern_size` are rewritten at the end

In practice, use this for additional environment keys, not for replacing the
auto-generated partition layout.

## JSON add-ons: what is supported and what is not

The only user-scoped JSON import hook wired into the build is:

```text
user/local.thingino.json
```

Other JSON files are handled differently:

- `/etc/thingino.json` supports user-layered import through `local.thingino.json`
- `prudynt.json` camera defaults are controlled through camera-scoped
  `prudynt-override.json`, not through `THINGINO_USER_DIR`
- Other JSON configs such as `/etc/prudynt.json` or `/etc/timelapse.json` do not
  have a generic user-side merge hook in the current build system

If you need to seed one of those files from your user tree, provide the full file
through `user/overlay/`, for example:

```text
user/overlay/etc/prudynt.json
user/overlay/etc/timelapse.json
```

That replaces the file content in the config overlay rather than merging JSON
objects key-by-key.

## Choosing the right mechanism

Use `local.fragment` when you need to change Buildroot symbols.

Use `local.thingino.json` when you need to add or override keys in
`/etc/thingino.json`.

Use `user/overlay/` when you need to place complete files into the writable
config partition.

Use `user/opt/` when you need files in the extras partition at `/opt`.

Use `local.uenv.txt` for additional U-Boot environment variables.

## Minimal example tree

```text
user/
├── local.fragment
├── local.thingino.json
├── local.uenv.txt
├── opt/
│   └── bin/
│       └── my-helper
└── overlay/
    └── etc/
        ├── init.d/
        │   └── S99local
        └── ssl/
            └── my-ca.pem
```

## Related documents

- `docs/overlayfs.md` explains why `user/overlay/` ends up in the writable
  overlay partition
- `docs/local-overrides.md` covers package source overrides through `local.mk`
- `docs/makefile.md` covers the general build workflow and config generation