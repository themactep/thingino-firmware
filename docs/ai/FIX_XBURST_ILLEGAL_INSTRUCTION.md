# Fix for "Illegal instruction" Crash on XBurst CPUs (T31/T21/T20)

## Problem

Prudynt crashes with "Illegal instruction" error on Ingenic XBurst MIPS processors (T31X, T31N, T31A, T21, T20, etc.), particularly when switching to night mode:

```
[INFO:DayNightWorker.cpp]: DayNight: switched to NIGHT (total_gain=6198)
- IRCUT -> night (pin1 idle, pin2 assert)
Illegal instruction
```

## Root Cause

The Ingenic XBurst CPUs have a known FPU bug that generates incorrect results with fused multiply-add instructions. When the compiler optimizes code (especially with `-Os` or `-O2`), it may generate these problematic instructions, causing an "Illegal instruction" crash.

Buildroot's toolchain wrapper is supposed to add `-mno-fused-madd` (GCC < 4.6) or `-ffp-contract=off` (GCC >= 4.6) for XBurst CPUs, but prudynt-t's build was not properly including `$(TARGET_CFLAGS)` which contains these critical architecture-specific flags.

## Solution

The fix ensures that prudynt-t's CFLAGS properly inherit the architecture-specific compiler flags from buildroot's TARGET_CFLAGS.

### Changed File

`package/prudynt-t/prudynt-t.mk` - Line 58-65

**Before:**
```makefile
# Base compiler flags
PRUDYNT_CFLAGS += \
	-I$(STAGING_DIR)/usr/include \
	...
```

**After:**
```makefile
# Base compiler flags - MUST include TARGET_CFLAGS for architecture-specific flags
# This is critical for XBurst CPUs which need -mno-fused-madd or -ffp-contract=off
PRUDYNT_CFLAGS = $(TARGET_CFLAGS) \
	-I$(STAGING_DIR)/usr/include \
	...
```

## How to Apply the Fix

### For Users Experiencing the Crash

1. The fix is already applied to this repository
2. Clean the prudynt-t package build:
   ```bash
   make prudynt-t-dirclean
   ```

3. Rebuild prudynt-t:
   ```bash
   make prudynt-t-rebuild
   ```

4. Rebuild the firmware image:
   ```bash
   make
   ```

5. Flash the new firmware to your camera

### Verification

After flashing, the night mode switching should work without crashes. You can verify by:

1. Checking that prudynt runs without crashing during day/night transitions
2. Looking at the compiler flags used during build (you should see `-mno-fused-madd` or `-ffp-contract=off` in the build log)

## Affected Devices

This fix applies to all cameras using Ingenic XBurst MIPS processors:
- Wyze Cam v3 (T31X)
- Wyze Cam v2 (T20)
- Xiaomi cameras (various T31/T21 models)
- And all other cameras with T10, T20, T21, T23, T30, T31 SoCs

## Technical Details

### XBurst FPU Bug

From the Buildroot MIPS configuration (`buildroot/arch/Config.in.mips`):

> The Ingenic XBurst is a MIPS32R2 microprocessor. It has a bug in the FPU that can generate incorrect results in certain cases. The problem shows up when you have several fused madd instructions in sequence with dependant operands. This requires the -mno-fused-madd compiler option to be used in order to prevent emitting these instructions.

### GCC Version Dependency

- **GCC < 4.6**: Uses `-mno-fused-madd`
- **GCC >= 4.6**: Uses `-ffp-contract=off`

The thingino toolchain uses GCC 15, so the flag applied is `-ffp-contract=off`.

## References

- Ingenic XBurst information: http://www.ingenic.com/en/?xburst.html
- Buildroot toolchain wrapper: `buildroot/toolchain/toolchain-wrapper.mk`
- XBurst configuration: `configs/fragments/soc-xburst1.fragment`
