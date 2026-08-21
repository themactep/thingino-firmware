Firmware Image Structure
========================

Thingino firmware consists of multiple partitions that are combined into a single binary image file.

## Firmware Image Types

### Full Firmware Image

**Filename**: `thingino-<camera>.bin`

This image contains all partitions including U-Boot bootloader and is used for:
- Initial installation on new cameras
- Complete firmware replacement
- Recovery from serious system failures

## Partition Layout

The firmware consists of the following partitions, written sequentially to flash:

| Partition | Size    | Type   | Description |
|-----------|---------|--------|-------------|
| U-Boot    | 256 KB  | Fixed  | Bootloader (first stage and SPL) |
| Env       | 64 KB   | Fixed  | U-Boot environment variables |
| Kernel    | Dynamic | Dynamic| Linux kernel (uImage format) |
| RootFS    | Dynamic | Dynamic| Root filesystem (SquashFS, compressed) |
| Data      | Dynamic | Dynamic| JFFS2 overlay upperdir covering full filesystem |

### Partition Details

#### U-Boot Partition (256 KB, fixed)
Contains the bootloader that initializes the hardware and loads the kernel.

#### Env Partition (64 KB, fixed)
Stores U-Boot environment variables in a binary format generated from the `uenv.txt` configuration files.

#### Kernel Partition (dynamic size)
Contains the Linux kernel image. Size is calculated based on the actual kernel size, aligned to 64 KB blocks.

#### RootFS Partition (dynamic size)
A compressed SquashFS filesystem containing:
- All system binaries and libraries
- Web interface files
- Default configuration templates
- Size depends on selected packages and features

#### Data Partition (dynamic size, fills remaining flash)
A single JFFS2 filesystem mounted as the overlayfs upperdir, covering the entire root filesystem. Contains:
- User overlay files from `user/common/overlay/`, camera- and device-scoped overlays
- User opt files from `user/common/opt/`, camera- and device-scoped opt directories
- All runtime configuration changes and package installations
- Acts as both the persistent config storage (replacing the old fixed config partition) and the `/opt/` writable area (replacing the old extras partition)

## Flash Size Considerations

Thingino supports various flash chip sizes:
- **8 MB** - Minimal installation
- **16 MB** - Standard installation
- **32 MB** - Extended installation with more features

The build system automatically calculates partition sizes based on:
1. Flash chip size (configured per camera model)
2. Actual size of compiled kernel and rootfs

### Partition Size Calculation

- **Fixed partitions**: U-Boot (256K), Env (64K) always use the same sizes
- **Dynamic partitions**: Kernel and RootFS sizes are aligned to 64 KB block boundaries
- **Data partition**: Size = (Flash Size - Sum of all other partitions), padded to fill the remaining flash

## Building Firmware Images

The build process:

1. **Compilation**: Buildroot compiles all packages, kernel, and creates the rootfs
2. **Partition Creation**:
   - `u-boot-with-spl-lzma.bin` - bootloader binary (LZMA-compressed payload)
   - `u-boot-env.bin` - environment binary from uenv.txt
   - `uImage` - kernel binary
   - `rootfs.squashfs` - compressed root filesystem
   - `data.jffs2` - single JFFS2 data partition containing overlay upperdir with user overlays and opt files
3. **Image Assembly**: `make pack` combines partitions into final images

### Build Commands

```bash
# Build firmware from scratch
make CAMERA=your_camera

# Rebuild kernel and rootfs, repack image
make CAMERA=your_camera repack

# Clean and rebuild everything
make CAMERA=your_camera cleanbuild
```

## Flashing Firmware

### Over-the-Air Update (OTA)

```bash
# Flash complete firmware image
make CAMERA=your_camera ota IP=192.168.1.10
```

### Using a Programmer

When installing Thingino for the first time or recovering a bricked camera:

1. Connect the flash chip to a programmer (e.g., CH341A)
2. Use `snander` or similar tool to write the full firmware image:
   ```bash
   snander -w thingino-camera.bin
   ```

### Via TFTP in U-Boot

1. Set up a TFTP server with the firmware image
2. Boot the camera and interrupt U-Boot
3. Flash the firmware:
   ```bash
   sf probe 0
   sf erase 0x0 0x800000
   tftpboot 0x80000000 thingino-camera.bin
   sf write 0x80000000 0x0 ${filesize}
   ```

## Partition Alignment

All partitions are aligned to 64 KB (0x10000) boundaries to match the erase block size of most NOR flash chips. This ensures:
- Efficient flash operations
- Proper JFFS2 filesystem function
- Compatibility with various flash chip models

## Firmware Image Verification

Each firmware image includes a SHA256 checksum file:
- `thingino-camera.bin.sha256sum` - for full image

Verify before flashing:
```bash
sha256sum -c thingino-camera.bin.sha256sum
```

## See Also

- [Firmware Dumping](firmware.md) - How to backup existing firmware
- [Camera Recovery](camera-recovery.md) - Recovering from failed updates
