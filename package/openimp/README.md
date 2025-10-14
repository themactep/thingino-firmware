# OpenIMP Package for Thingino Firmware

This package provides an open-source implementation of the Ingenic IMP (Image Media Process) library.

## Overview

OpenIMP is a reverse-engineered implementation of Ingenic's proprietary `libimp.so` library. When enabled, this package will:

1. Build after `ingenic-sdk` and `ingenic-lib`
2. Compile the OpenIMP library from source
3. **Override** the proprietary `usr/lib/libimp.so` with the open-source version

## Configuration

To enable OpenIMP in your build:

1. Run `make menuconfig` or `make xconfig`
2. Navigate to: **Thingino Firmware → System Packages → OpenIMP**
3. Enable the `BR2_PACKAGE_OPENIMP` option
4. Save and exit

Alternatively, add this line to your defconfig:
```
BR2_PACKAGE_OPENIMP=y
```

## Dependencies

This package requires:
- `BR2_PACKAGE_INGENIC_SDK` - Ingenic SDK (kernel modules and drivers)
- `BR2_PACKAGE_INGENIC_LIB` - Ingenic libraries (will be overridden)

These dependencies are automatically selected when you enable the System Packages menu.

## Build Order

The package is configured to build in the correct order:

1. **ingenic-sdk** - Builds kernel modules and SDK components
2. **ingenic-lib** - Installs proprietary Ingenic libraries (including libimp.so)
3. **openimp** - Builds and **overwrites** libimp.so with the open-source version

## Platform Support

OpenIMP automatically detects the target platform based on your SoC selection:

- T21 (Ingenic T21 family)
- T23 (Ingenic T23 family)
- T30 (Ingenic T30 family)
- T31 (Ingenic T31 family) - Default
- T40 (Ingenic T40 family)
- T41 (Ingenic T41 family)
- C100 (Ingenic C100)

The platform is automatically determined from `BR2_SOC_FAMILY_INGENIC_*` configuration variables.

## What Gets Installed

### Staging Directory (for development)
- Headers: `/usr/include/imp/*.h`
- Libraries: `/usr/lib/libimp.so` (shared)
- Libraries: `/usr/lib/libimp.a` (static)

### Target Directory (on device)
- `/usr/lib/libimp.so` - **Replaces proprietary version**

Note: `libsysutils.so` is built but not installed, as it's not part of the standard Ingenic IMP API.

## Source Repository

The package fetches source code from:
- Repository: https://github.com/opensensor/openimp
- Branch: main
- Version: HEAD (latest)

To use a specific commit, edit `package/openimp/openimp.mk` and set:
```makefile
OPENIMP_VERSION = <commit-hash>
```

## Build Process

The package uses the OpenIMP Makefile with cross-compilation:

1. **Build**: Compiles all source files with the target cross-compiler
2. **Strip**: Removes debug symbols to reduce library size
3. **Install**: Copies libraries to staging and target directories
4. **Finalize**: Uses a target finalize hook to ensure libimp.so is installed LAST

Build flags:
- `CROSS_COMPILE=$(TARGET_CROSS)` - Use Buildroot's cross-compiler
- `PLATFORM=$(OPENIMP_PLATFORM)` - Set platform-specific defines
- `CFLAGS` - Include target flags and PIC (Position Independent Code)
- `LDFLAGS` - Link with pthread and rt libraries

### Override Mechanism

To ensure the OpenIMP library always replaces the proprietary version, the package uses a **target finalize hook**. This hook runs after ALL packages have been installed, guaranteeing that our libimp.so is the final version in the target filesystem, even if other packages (like prudynt-t) trigger ingenic-lib to reinstall.

## Compatibility

OpenIMP is designed to be a drop-in replacement for the proprietary Ingenic IMP library. Applications that use the IMP API should work without modification.

Supported modules:
- System module (IMP_System_*)
- ISP module (IMP_ISP_*)
- FrameSource module (IMP_FrameSource_*)
- Encoder module (IMP_Encoder_*)
- Audio module (IMP_Audio_*)
- OSD module (IMP_OSD_*)
- IVS module (IMP_IVS_*)

## Testing

After building and flashing your firmware:

1. Check that the library is installed:
   ```bash
   ls -lh /usr/lib/libimp.so
   ```

2. Verify it's the OpenIMP version (should be ~136KB stripped):
   ```bash
   file /usr/lib/libimp.so
   ```

3. Test with your streaming application (e.g., prudynt-t, thingino-streamer)

## Troubleshooting

### Build Fails
- Ensure `ingenic-sdk` and `ingenic-lib` are enabled
- Check that your SoC family is correctly selected
- Review build logs in `output/build/openimp-*/`

### Runtime Issues
- Check kernel modules are loaded: `lsmod | grep ingenic`
- Verify device nodes exist: `ls -l /dev/jz-*`
- Check application logs for IMP-related errors

### Reverting to Proprietary Library
To switch back to the proprietary Ingenic library:
1. Disable `BR2_PACKAGE_OPENIMP` in menuconfig
2. Rebuild: `make clean && make`

## Development

To modify the OpenIMP source during development:

1. Use Buildroot's override mechanism:
   ```bash
   echo 'OPENIMP_OVERRIDE_SRCDIR = /path/to/local/openimp' >> local.mk
   ```

2. Make changes to your local copy

3. Rebuild:
   ```bash
   make openimp-rebuild
   ```

## License

OpenIMP is licensed under the MIT License. See the LICENSE file in the source repository.

## Contributing

To contribute to OpenIMP:
- Repository: https://github.com/opensensor/openimp
- Issues: Report bugs and feature requests on GitHub
- Pull Requests: Submit improvements and fixes

## References

- [OpenIMP GitHub Repository](https://github.com/opensensor/openimp)
- [Thingino Firmware](https://github.com/thingino/firmware)
- [Buildroot Documentation](https://buildroot.org/downloads/manual/manual.html)

