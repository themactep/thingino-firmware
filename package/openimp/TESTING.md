# OpenIMP Package - Testing Guide

This guide explains how to test the OpenIMP package to ensure it's working correctly.

## Pre-Build Testing

### 1. Verify Package Configuration

Check that the package is properly configured:

```bash
# Enable the package
make menuconfig
# Navigate to: Thingino Firmware → System Packages → OpenIMP
# Enable it and save

# Verify it's enabled
grep BR2_PACKAGE_OPENIMP .config
# Should show: BR2_PACKAGE_OPENIMP=y
```

### 2. Check Package Dependencies

Verify dependencies are resolved:

```bash
# Show package dependencies
make openimp-show-depends
# Should show: ingenic-sdk ingenic-lib

# Show recursive dependencies
make openimp-show-recursive-depends
```

## Build Testing

### 1. Clean Build

Start with a clean build to ensure everything works from scratch:

```bash
# Clean the openimp package
make openimp-dirclean

# Build the package
make openimp

# Or build the entire firmware
make
```

### 2. Monitor Build Output

Watch for the finalize hook message:

```bash
# During build, you should see:
# >>> openimp HEAD Installing to target
# OpenIMP: Ensuring libimp.so override is in place...
```

### 3. Check Build Directory

Verify the library was built correctly:

```bash
# Check the build directory
ls -lh output/build/openimp-HEAD/lib/

# Should show:
# libimp.a
# libimp.so
# libsysutils.a
# libsysutils.so

# Verify library size (stripped)
ls -lh output/build/openimp-HEAD/lib/libimp.so
# Should be approximately 136KB
```

### 4. Verify Target Directory

Check what was installed to the target:

```bash
# Check openimp's target directory
find output/target/usr/lib/ -name "libimp*" -o -name "libsysutils*"

# Should show ONLY:
# output/target/usr/lib/libimp.so

# Verify it's the OpenIMP version
ls -lh output/target/usr/lib/libimp.so
file output/target/usr/lib/libimp.so
```

### 5. Check Staging Directory

Verify staging installation:

```bash
# Check staging directory
ls -lh output/staging/usr/lib/libimp*

# Should show:
# libimp.a
# libimp.so

# Check headers
ls output/staging/usr/include/imp/

# Should show IMP headers
```

## Post-Build Testing

### 1. Verify Per-Package Directory

Check the per-package target directory:

```bash
# Find the per-package directory
OPENIMP_TARGET=$(find output/per-package/openimp/target -type d -name "usr" 2>/dev/null)

# Check what openimp installed
find output/per-package/openimp/target/usr/lib/ -name "*.so" 2>/dev/null

# Should show ONLY:
# ./usr/lib/libimp.so
# (NO libsysutils.so)
```

### 2. Check Build Log

Review the build log for any errors:

```bash
# Check for openimp in build log
grep -A 10 ">>> openimp" output/build/build-time.log

# Look for the finalize hook
grep "OpenIMP: Ensuring" output/build/build-time.log
```

## Device Testing

### 1. Flash Firmware

Flash the built firmware to your device:

```bash
# Use your normal flashing method
# For example:
scp output/images/rootfs.squashfs root@device:/tmp/
ssh root@device "sysupgrade /tmp/rootfs.squashfs"
```

### 2. Verify Library on Device

After the device boots:

```bash
# SSH to device
ssh root@device

# Check library exists
ls -lh /usr/lib/libimp.so

# Verify size (should be ~136KB for OpenIMP)
# If it's larger (e.g., 500KB+), it's the proprietary version

# Check library type
file /usr/lib/libimp.so

# Should show: ELF 32-bit LSB shared object, MIPS...

# Check dependencies
ldd /usr/lib/libimp.so

# Should show:
# libpthread.so.0
# librt.so.1
# libc.so.0
```

### 3. Test with Applications

Test that applications work with the OpenIMP library:

```bash
# On device, test streaming application
prudynt-t

# Check for any IMP-related errors in logs
logread | grep -i imp

# Test video streaming
# Open your browser to: http://device-ip/
# Verify video stream works
```

### 4. Verify Kernel Modules

Ensure kernel modules are loaded:

```bash
# On device
lsmod | grep ingenic

# Should show ingenic modules loaded

# Check device nodes
ls -l /dev/jz-*

# Should show device nodes for IMP
```

## Troubleshooting Tests

### Test 1: Verify Override Works

To confirm the override mechanism works:

```bash
# Before building, check ingenic-lib version
ls -lh output/build/ingenic-lib-*/T31/lib/*/uclibc/*/libimp.so

# After building with openimp enabled
ls -lh output/target/usr/lib/libimp.so

# The target version should be ~136KB (OpenIMP)
# The ingenic-lib version is typically much larger
```

### Test 2: Check Build Order

Verify packages build in correct order:

```bash
# Check build order
make openimp-show-build-order

# Should show ingenic-sdk and ingenic-lib before openimp
```

### Test 3: Simulate Rebuild

Test that the finalize hook works even after rebuilds:

```bash
# Rebuild ingenic-lib (simulates what prudynt-t might trigger)
make ingenic-lib-rebuild

# Rebuild openimp
make openimp-rebuild

# Check target still has OpenIMP version
ls -lh output/target/usr/lib/libimp.so
```

## Expected Results

### ✅ Successful Build

- Build completes without errors
- Finalize hook message appears in build output
- Only `libimp.so` in target (no `libsysutils.so`)
- Library size is ~136KB (stripped)

### ✅ Successful Device Test

- Library exists at `/usr/lib/libimp.so`
- Library size is ~136KB
- Applications (prudynt-t) start without errors
- Video streaming works
- No IMP-related errors in logs

### ❌ Failed Build Indicators

- Build errors during compilation
- Missing finalize hook message
- `libsysutils.so` present in target
- Library size is wrong (too large = proprietary version)

### ❌ Failed Device Test Indicators

- Library missing or wrong size
- Applications fail to start
- IMP errors in logs
- Video streaming doesn't work
- Kernel modules not loaded

## Comparison Test

To verify you're using OpenIMP vs proprietary:

```bash
# Build WITHOUT openimp
make menuconfig  # Disable BR2_PACKAGE_OPENIMP
make clean
make
ls -lh output/target/usr/lib/libimp.so
# Note the size (proprietary version)

# Build WITH openimp
make menuconfig  # Enable BR2_PACKAGE_OPENIMP
make clean
make
ls -lh output/target/usr/lib/libimp.so
# Should be ~136KB (OpenIMP version)
```

## Automated Test Script

Here's a simple test script:

```bash
#!/bin/bash
# test-openimp.sh

echo "Testing OpenIMP package..."

# Check if enabled
if ! grep -q "BR2_PACKAGE_OPENIMP=y" .config; then
    echo "❌ OpenIMP not enabled in .config"
    exit 1
fi
echo "✅ OpenIMP enabled"

# Check build directory
if [ ! -f output/build/openimp-HEAD/lib/libimp.so ]; then
    echo "❌ libimp.so not built"
    exit 1
fi
echo "✅ libimp.so built"

# Check target directory
if [ ! -f output/target/usr/lib/libimp.so ]; then
    echo "❌ libimp.so not in target"
    exit 1
fi
echo "✅ libimp.so in target"

# Check libsysutils NOT in target
if [ -f output/target/usr/lib/libsysutils.so ]; then
    echo "❌ libsysutils.so should NOT be in target"
    exit 1
fi
echo "✅ libsysutils.so not in target (correct)"

# Check size
SIZE=$(stat -c%s output/target/usr/lib/libimp.so)
if [ $SIZE -lt 100000 ] || [ $SIZE -gt 200000 ]; then
    echo "⚠️  Warning: libimp.so size is $SIZE bytes (expected ~136KB)"
else
    echo "✅ libimp.so size is correct ($SIZE bytes)"
fi

echo ""
echo "All tests passed! ✅"
```

Run it with:
```bash
chmod +x test-openimp.sh
./test-openimp.sh
```

## Reporting Issues

If you encounter problems, collect this information:

1. **Build Configuration**:
   ```bash
   grep BR2_PACKAGE_OPENIMP .config
   grep BR2_SOC .config | grep "=y"
   ```

2. **Build Log**:
   ```bash
   grep -A 20 ">>> openimp" output/build/build-time.log
   ```

3. **File Sizes**:
   ```bash
   ls -lh output/target/usr/lib/libimp.so
   ls -lh output/build/openimp-HEAD/lib/libimp.so
   ```

4. **Device Info** (if applicable):
   ```bash
   # On device
   uname -a
   cat /proc/cpuinfo | grep "cpu model"
   ls -lh /usr/lib/libimp.so
   lsmod | grep ingenic
   ```

Include this information when reporting issues on GitHub or the forum.

