# OpenIMP Package - Quick Start Guide

> Current integration supports OpenIMP on T31/Linux 3.10 and T40/Linux 4.4.
> Prefer `BR2_PACKAGE_THINGINO_OPEN_ISP=y` for the complete open-stack profile;
> see [`docs/open-isp-stack.md`](../../docs/open-isp-stack.md).

## What is OpenIMP?

OpenIMP is an **optional** open-source replacement for Ingenic's proprietary IMP (Image Media Process) library. When enabled, it will replace `/usr/lib/libimp.so` with an open-source implementation.

## Quick Enable

### Option 1: Using menuconfig
```bash
make menuconfig
```
Navigate to:
```
Thingino Firmware
  └─ System Packages
      └─ [*] OpenIMP
```
Save and exit, then:
```bash
make
```

### Option 2: Add to defconfig
```bash
# Add this line to your defconfig
BR2_PACKAGE_OPENIMP=y

# Then build
make your_defconfig
make
```

### Option 3: Quick command
```bash
# Enable in current config
echo 'BR2_PACKAGE_OPENIMP=y' >> .config
make olddefconfig
make openimp
```

## What Happens When Enabled?

1. **Build Order**:
   - ingenic-sdk builds first (kernel modules)
   - ingenic-lib builds second (proprietary libraries)
   - **openimp builds and overwrites libimp.so**
   - **Target finalize hook ensures libimp.so stays overridden**

2. **Files Installed**:
   - `/usr/lib/libimp.so` - OpenIMP version (~136KB)

3. **Compatibility**:
   - Drop-in replacement for proprietary library
   - Streamer packages build after the selected replacement
   - Runtime coverage remains platform- and API-dependent

4. **Override Protection**:
   - Uses a finalize hook to ensure the OpenIMP library is installed LAST
   - Prevents other packages from overwriting it during build

## Verify Installation

After flashing firmware:
```bash
# Check the installed provider
ls -lh /usr/lib/libimp.so

# Check library type
file /usr/lib/libimp.so

# Test with streaming app
prudynt-t
```

## Disable OpenIMP

To revert to proprietary library:
```bash
make menuconfig
# Uncheck OpenIMP
make clean
make
```

## Supported Platforms

Auto-detected based on your SoC selection:
- T31 with Linux 3.10
- T40 with Linux 4.4

## Troubleshooting

### Build fails
- Ensure System Packages is enabled
- Check that ingenic-sdk and ingenic-lib are selected
- Try: `make openimp-dirclean openimp`

### Runtime issues
- Check kernel modules: `lsmod | grep ingenic`
- Check device nodes: `ls -l /dev/jz-*`
- Review app logs for errors

## More Information

See `package/openimp/README.md` for detailed documentation.

## Source Code

Repository: https://github.com/opensensor/openimp
