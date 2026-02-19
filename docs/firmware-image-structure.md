Firmware Image Structure
========================

Thingino firmware consists of multiple partitions that are combined into a single binary image file. The build system creates two types of firmware images:

## Firmware Image Types

### Full Firmware Image

**Filename**: `thingino-<camera>.bin`

This image contains all partitions including U-Boot bootloader and is used for:
- Initial installation on new cameras
- Complete firmware replacement
- Recovery from serious system failures

### Update Image (No-Boot)

**Filename**: `thingino-<camera>-update.bin`

This image excludes the U-Boot bootloader partition and is used for:
- Regular firmware updates on cameras already running Thingino
- Faster updates since bootloader doesn't need to be reflashed

## Partition Layout

The firmware consists of the following partitions, written sequentially to flash:

| Partition | Size    | Type   | Description |
|-----------|---------|--------|-------------|
| U-Boot    | 256 KB  | Fixed  | Bootloader (first stage and SPL) |
| Env       | 32 KB   | Fixed  | U-Boot environment variables |
| Config    | 224 KB  | Fixed  | JFFS2 filesystem for persistent configuration |
| Kernel    | Dynamic | Dynamic| Linux kernel (uImage format) |
| RootFS    | Dynamic | Dynamic| Root filesystem (SquashFS, compressed) |
| Extras    | Dynamic | Dynamic| Optional additional files (JFFS2) |

### Partition Details

#### U-Boot Partition (256 KB, fixed)
Contains the bootloader that initializes the hardware and loads the kernel.

#### Env Partition (32 KB, fixed)
Stores U-Boot environment variables in a binary format generated from the `.uenv.txt` configuration files.

#### Config Partition (224 KB, fixed)
A JFFS2 filesystem containing:
- System configuration files from `user/overlay/`
- Persistent settings that survive firmware updates
- Network configuration, credentials, etc.

#### Kernel Partition (dynamic size)
Contains the Linux kernel image. Size is calculated based on the actual kernel size, aligned to 32 KB blocks.

#### RootFS Partition (dynamic size)
A compressed SquashFS filesystem containing:
- All system binaries and libraries
- Web interface files
- Default configuration templates
- Size depends on selected packages and features

#### Extras Partition (dynamic size, optional)

**New Behavior (Optimized for Smaller Images)**

The extras partition is now handled intelligently to reduce firmware image size:

- **For Release Builds**: If the `/opt/` directory in the build is empty (no custom files), the extras partition is **NOT included** in the firmware image. The partition will be automatically created and formatted on the camera at first boot when needed.

- **For Development Builds with Custom Files**: If there are custom files in `/opt/` (from local builds or overlays), the extras partition is created, populated with the files, and **padded to the full calculated partition size** to fill the flash.

This approach provides several benefits:
- **Smaller images for standard builds**: 8MB images can fit on 16MB/32MB flash chips without wasting space
- **Faster downloads and flashing**: Less data to transfer
- **Efficient use of flash**: Empty space isn't pre-allocated
- **Custom files supported**: Developer builds with local files still work as expected

The partition typically contains:
- Additional packages and tools (installed to `/opt/`)
- Large optional components
- User-installed applications

## Flash Size Considerations

Thingino supports various flash chip sizes:
- **8 MB** - Minimal installation
- **16 MB** - Standard installation
- **32 MB** - Extended installation with more features

The build system automatically calculates partition sizes based on:
1. Flash chip size (configured per camera model)
2. Actual size of compiled kernel and rootfs
3. Whether custom files exist in `/opt/`

### Partition Size Calculation

- **Fixed partitions**: U-Boot (256K), Env (32K), Config (224K) always use the same sizes
- **Dynamic partitions**: Kernel and RootFS sizes are aligned to 32 KB block boundaries
- **Extras partition**:
  - If empty: Excluded from image, created at first boot
  - If has content: Size = (Flash Size - Sum of all other partitions)

## Building Firmware Images

The build process:

1. **Compilation**: Buildroot compiles all packages, kernel, and creates the rootfs
2. **Partition Creation**:
   - `u-boot-lzo-with-spl.bin` - bootloader binary
   - `u-boot-env.bin` - environment binary from uenv.txt
   - `config.jffs2` - config partition from user/overlay/
   - `uImage` - kernel binary
   - `rootfs.squashfs` - compressed root filesystem
   - `extras.jffs2` - optional extras partition (only if has content)
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
# Flash bootloader only (rarely needed)
make CAMERA=your_camera upboot_ota IP=192.168.1.10

# Flash kernel and rootfs (normal updates)
make CAMERA=your_camera update_ota IP=192.168.1.10

# Flash complete firmware including bootloader
make CAMERA=your_camera upgrade_ota IP=192.168.1.10
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

All partitions are aligned to 32 KB (0x8000) boundaries to match the erase block size of most NOR flash chips. This ensures:
- Efficient flash operations
- Proper JFFS2 filesystem function
- Compatibility with various flash chip models

## Firmware Image Verification

Each firmware image includes a SHA256 checksum file:
- `thingino-camera.bin.sha256sum` - for full image
- `thingino-camera-update.bin.sha256sum` - for update image

Verify before flashing:
```bash
sha256sum -c thingino-camera.bin.sha256sum
```

## See Also

- [Firmware Dumping](firmware.md) - How to backup existing firmware
- [Camera Recovery](camera-recovery.md) - Recovering from failed updates
- [Building from Sources](https://github.com/themactep/thingino-firmware/wiki/Building-from-sources) - Detailed build instructions
