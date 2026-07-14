# Overlay Backup

The `backup-overlay` Makefile target pulls the `/overlay/` directory from a running
Thingino camera via SSH and stores it as a timestamped tarball in a global backup
directory on the build host. No camera profile (`CAMERA=`) is required — the camera
image name is auto-detected from the device.

## Quick Start

```bash
make backup-overlay IP=192.168.1.10
```

This connects to `root@192.168.1.10`, reads the camera's `IMAGE_ID`, copies
`/overlay/`, and saves the archive to `~/.thingino/backups/`.

### Output

The tarball is named: `<camera>-<ip-safe>-<YYYYMMDD-HHMMSS>.tar.gz`

```
~/.thingino/backups/
└── wyze_cam3_t31x_gc2053_atbm6031-192-168-1-10-20260714-012211.tar.gz
```

### Custom Backup Directory

Override the default location by setting `THINGINO_BACKUP_DIR`:

```bash
# One-off
make backup-overlay IP=192.168.1.10 THINGINO_BACKUP_DIR=/mnt/nas/camera-backups

# Persistent (export in your shell)
export THINGINO_BACKUP_DIR=/mnt/nas/camera-backups
make backup-overlay IP=192.168.1.10
```

## How It Works

1. **SSH connection** — connects to `root@<IP>` (dropbear server on the camera)
2. **Camera detection** — reads `IMAGE_ID` from `/etc/os-release`, strips kernel version suffix
3. **Overlay stream** — runs `tar` on the camera (as root, so all files are readable regardless of permissions) and streams the gzipped tarball directly to the host
4. **Verification** — validates the tarball with `gzip -t`

The script is located at `scripts/backup_overlay.sh`.

## What Gets Backed Up

The `/overlay/` directory on a Thingino camera is the writable upper layer of the
overlay filesystem. It contains user customizations such as:

- Modified configuration files (e.g., `/etc/wpa_supplicant.conf`, `/etc/init.d/*`)
- Custom scripts and binaries placed on the camera
- User-scoped overlay files from `user/<camera>/overlay/` or `user/<camera>/<ip>/overlay/`

For details on the overlay filesystem, see [overlayfs.md](overlayfs.md).

## Why Back Up Overlay?

- **Pre-OTA safeguard** — capture user customizations before flashing new firmware
- **Migration** — move customizations from one camera to another of the same model
- **Version control** — keep a history of configuration changes outside the firmware tree
- **Disaster recovery** — restore overlay after a factory reset or accidental deletion

## Makefile Integration

### Target

| Target | Description |
|--------|-------------|
| `make backup-overlay IP=<ip>` | Backup `/overlay/` from camera at `<ip>` |

### Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IP` | *(required)* | Camera IP address |
| `THINGINO_BACKUP_DIR` | `~/.thingino/backups` | Directory to store backup tarballs |

The `backup-overlay` target is exempt from camera profile selection — it does not
require `CAMERA=` and works independently of the build configuration.

## Restoring an Overlay

To restore a backed-up overlay to a camera:

```bash
# Extract the tarball
tar -xzf ~/.thingino/backups/<camera>-<ip>-<timestamp>.tar.gz -C /tmp/overlay-restore/

# Copy files to the camera
scp -O -r /tmp/overlay-restore/. root@<camera-ip>:/overlay/

# Reboot the camera to apply changes
ssh root@<camera-ip> reboot
```

> **Note:** Restoring overlay files replaces the runtime configuration. Make sure
> the target camera is running the same firmware image as the source to avoid
> compatibility issues. Back up the target's own overlay first if needed.

## Direct Script Usage

You can call the script directly without `make`:

```bash
scripts/backup_overlay.sh <ip_address> <backup_dir>
```

Example:

```bash
scripts/backup_overlay.sh 192.168.1.10 /mnt/backups/
```

## Troubleshooting

### Connection Refused or Timeout

- Verify the camera is powered on and reachable: `ping 192.168.1.10`
- Confirm SSH is running: `ssh root@192.168.1.10 "echo ok"`
- The camera uses dropbear SSH server — no special client configuration needed

### Empty Backup

If `/overlay/` on the camera is empty (stock firmware with no customizations), the
script creates a near-empty tarball. This is expected. Check the output for:

```
Warning: /overlay on camera is empty or inaccessible.
```

### Permission Denied

The camera-side `tar` runs as root, so file permissions (e.g. mode 000 on
`crond.reboot`) are not an issue. If you see authentication errors, verify
the root password matches your camera's configuration. The default password
is set in the camera's defconfig.

### Backup Directory Not Writable

Ensure `THINGINO_BACKUP_DIR` exists and is writable. The script creates it
automatically (`mkdir -p`), but parent directory permissions may prevent this.
