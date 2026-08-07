# OpenIMP Package for Thingino Firmware

> For the complete open-stack profile and support matrix, see
> [`docs/open-isp-stack.md`](../../docs/open-isp-stack.md).

This package provides an open-source implementation of the Ingenic IMP (Image Media Process) library.

## Overview

OpenIMP is a reverse-engineered implementation of Ingenic's proprietary `libimp.so` library. When enabled, this package will:

1. Build after `ingenic-sdk` and `ingenic-lib`
2. Compile the OpenIMP library from source
3. **Override** the proprietary `usr/lib/libimp.so` with the open-source version

## Configuration

To enable OpenIMP in your build:

1. Run `make menuconfig` or `make xconfig`
2. Navigate to: **Thingino Firmware → System Packages → ISP stack**
3. Select **Open ISP stack (experimental)**
4. Save and exit

Alternatively, add this line to your defconfig:
```
BR2_PACKAGE_THINGINO_ISP_OPEN=y
```

## Dependencies

This package requires:
- `BR2_PACKAGE_INGENIC_SDK` - Ingenic SDK (kernel modules and drivers)
- `BR2_PACKAGE_INGENIC_LIB` - Ingenic libraries (will be overridden)

The ISP provider choice selects these dependencies automatically.

## Build Order

The package is configured to build in the correct order:

1. **ingenic-sdk** - Builds kernel modules and SDK components
2. **ingenic-lib** - Installs proprietary Ingenic libraries (including libimp.so)
3. **openimp** - Builds and **overwrites** libimp.so with the open-source version

## Platform Support

OpenIMP automatically detects its current upstream device targets:

- T31 on Linux 3.10
- T40 on Linux 4.4
- T41 on Linux 4.4

The platform is automatically determined from the `SOC_FAMILY` variable.
The current T31 build is video-focused and does not yet implement IMP audio
or every optional OSD/IVS entry point.

## What Gets Installed

### Staging Directory (for development)
- Headers: `/usr/include/imp/*.h`
- OpenIMP headers: `/usr/include/openimp/*.h`
- Libraries: `/usr/lib/libimp.so` (shared)

### Target Directory (on device)
- `/usr/lib/libimp.so` - **Replaces proprietary version**
- `/usr/bin/openimp-tuningd` - runtime image-policy daemon
- `/etc/openimp-tuning.conf` - tuning profile configuration

## Source Repository

The package fetches source code from:
- Repository: https://github.com/opensensor/openimp
- Branch: main
- Version: `d64b80f8b35e5946d7856d6decffc9a1be579b91`

To use a specific commit, edit `package/openimp/openimp.mk` and set:
```makefile
OPENIMP_VERSION = <commit-hash>
```

## Build Process

The package uses OpenIMP's `build-for-device.sh` entry point with the
Buildroot cross-toolchain:

1. **Build**: Compiles all source files with the target cross-compiler
2. **Strip**: Removes debug symbols to reduce library size
3. **Install**: Copies libraries to staging and target directories
4. **Finalize**: Uses a target finalize hook to ensure libimp.so is installed LAST

Build flags:
- `TOOLCHAIN_PREFIX` - Buildroot cross-compiler prefix without the final dash
- `THINGINO_DIR` - Thingino source tree
- `T31_OUTPUT_DIR` / `T40_OUTPUT_DIR` / `T41_OUTPUT_DIR` - per-SoC build output
- `T40_HEADERS` - T40 1.3.1 IMP headers supplied by raptor-hal
- `T41_HEADERS` - T41 1.2.0 IMP headers supplied by raptor-hal

### Override Mechanism

To ensure the OpenIMP library always replaces the proprietary version, the package uses a **target finalize hook**. This hook runs after ALL packages have been installed, guaranteeing that our libimp.so is the final version in the target filesystem, even if other packages (like prudynt-t) trigger ingenic-lib to reinstall.

## Compatibility

OpenIMP targets the proprietary IMP ABI, but it remains experimental. Validate
the exact streamer, sensor, and IMP entry points used by each camera profile.

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

3. Test with your streaming application (e.g., prudynt-t, strero)

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
1. Select **Proprietary Ingenic ISP stack** in menuconfig
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

OpenIMP is identified by upstream as MIT licensed.

## Contributing

To contribute to OpenIMP:
- Repository: https://github.com/opensensor/openimp
- Issues: Report bugs and feature requests on GitHub
- Pull Requests: Submit improvements and fixes

## References

- [OpenIMP GitHub Repository](https://github.com/opensensor/openimp)
- [Thingino Firmware](https://github.com/thingino/firmware)
- [Buildroot Documentation](https://buildroot.org/downloads/manual/manual.html)
