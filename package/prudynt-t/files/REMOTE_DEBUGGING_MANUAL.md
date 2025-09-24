# Thingino Camera Remote Debugging Manual

## Overview

This manual covers remote debugging of Prudynt on thingino camera hardware using GDBserver and a development machine with GDB.

## Prerequisites

### Camera Side
- Thingino firmware with debug build enabled
- NFS mount configured and accessible
- Network connectivity to development machine
- GDBserver available (included in thingino)

### Development Machine
- Thingino firmware toolkit with MIPS cross-GDB (`~/output/camera_name/host/bin/mipsel-linux-gdb`)
- Network access to camera
- Debug symbols and unstripped binary from NFS

## Quick Start

### 1. On Camera
```bash
/mnt/nfs/camera_name/usr/bin/prudynt-debug-helper gdb [args]
```

### 2. On Development Machine
```bash
~/output/camera_name/host/bin/mipsel-linux-gdb /nfs/camera_name/usr/bin/prudynt-debug
(gdb) target remote CAMERA_IP:2345
(gdb) continue
```

## Detailed Setup

### Step 1: Prepare Development Environment

**Use Thingino Firmware Toolkit:**
The thingino firmware toolkit includes the correct cross-GDB for MIPS debugging:
```bash
# The cross-GDB is located in the output directory:
# ~/output/camera_name/host/bin/mipsel-linux-gdb

# Add toolkit to PATH if needed:
export PATH="~/output/camera_name/host/bin:$PATH"

# Or use the full path directly:
~/output/camera_name/host/bin/mipsel-linux-gdb

# Verify cross-GDB is available:
which mipsel-linux-gdb
```

**Mount NFS share (if not already mounted):**
```bash
mount -t nfs -o nolock,tcp,nfsvers=3 CAMERA_IP:/nfs /mnt/nfs
```

### Step 2: Start GDBserver on Camera

**Basic debugging:**
```bash
/mnt/nfs/camera_name/usr/bin/prudynt-debug-helper gdb
```

**Debug with arguments:**
```bash
/mnt/nfs/camera_name/usr/bin/prudynt-debug-helper gdb --config /etc/prudynt.cfg --verbose
```

**Custom port:**
```bash
GDB_PORT=3000 /mnt/nfs/camera_name/usr/bin/prudynt-debug-helper gdb
```

### Step 3: Connect from Development Machine

**Start GDB with debug binary:**
```bash
~/output/camera_name/host/bin/mipsel-linux-gdb /nfs/camera_name/usr/bin/prudynt-debug
```

**Connect to camera:**
```bash
(gdb) target remote CAMERA_IP:2345
```

**Set up environment (automatic with continue):**
```bash
(gdb) set environment ASAN_OPTIONS=abort_on_error=1:halt_on_error=1
(gdb) set environment UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1
```

**Start execution:**
```bash
(gdb) continue
```

## Debugging Techniques

### Basic Commands
```bash
(gdb) break main                     # Set breakpoint at main
(gdb) break src/VideoWorker.cpp:123  # Break at specific line
(gdb) break IMPEncoder::encode       # Break at method
(gdb) continue                       # Continue execution
(gdb) step                           # Step into function
(gdb) next                           # Step over function
(gdb) finish                         # Step out of function
(gdb) bt                             # Show backtrace
(gdb) info registers                 # Show CPU registers
(gdb) print variable_name            # Print variable value
(gdb) watch variable_name            # Watch variable changes
```

### Memory Debugging
```bash
(gdb) info proc mappings             # Show memory mappings
(gdb) x/16x 0x12345678               # Examine memory (hex)
(gdb) x/16i $pc                      # Disassemble at PC
(gdb) info threads                   # Show all threads
(gdb) thread 2                       # Switch to thread 2
```

### Camera-Specific Debugging
```bash
(gdb) break IMPSystem::init          # Debug camera initialization
(gdb) break VideoWorker::run         # Debug video processing
(gdb) break OSD::update              # Debug overlay issues
(gdb) info sharedlibrary             # Show loaded libraries
```

## Troubleshooting

### Connection Issues
- Check network connectivity: `ping CAMERA_IP`
- Verify port is open: `telnet CAMERA_IP 2345`
- Check firewall settings on both sides
- Ensure gdbserver is running on camera

### Symbol Issues
- Verify debug symbols are available: `file /nfs/camera_name/usr/bin/prudynt-debug`
- Check symbol file: `(gdb) symbol-file /nfs/camera_name/usr/lib/debug/usr/bin/prudynt.debug`
- Reload symbols if needed: `(gdb) file /nfs/camera_name/usr/bin/prudynt-debug`

### Performance Issues
- Use conditional breakpoints: `(gdb) break VideoWorker.cpp:123 if frame_count > 100`
- Disable ASAN for performance: `(gdb) unset environment ASAN_OPTIONS`
- Use hardware breakpoints when available: `(gdb) hbreak function_name`

## Advanced Techniques

### Multi-Process Debugging
```bash
# Follow child processes:
(gdb) set follow-fork-mode child

# Debug specific PID:
gdbserver --attach :2345 PID
```

### Core Dump Analysis
```bash
# Generate core dump on camera:
echo 'core' > /proc/sys/kernel/core_pattern
ulimit -c unlimited

# Analyze core dump:
~/output/camera_name/host/bin/mipsel-linux-gdb /nfs/camera_name/usr/bin/prudynt-debug core.PID
```

### Scripting and Automation
```bash
# Create GDB script file:
echo 'target remote CAMERA_IP:2345' > debug.gdb
echo 'break main' >> debug.gdb
echo 'continue' >> debug.gdb
~/output/camera_name/host/bin/mipsel-linux-gdb -x debug.gdb /nfs/camera_name/usr/bin/prudynt-debug
```

## Camera-Specific Tips

- Monitor camera resources during debugging:
  ```bash
  /mnt/nfs/camera_name/usr/bin/prudynt-debug-helper memory
  ```

- Debug camera initialization sequence:
  ```bash
  (gdb) break IMPSystem::init
  (gdb) break IMPEncoder::create
  ```

- Debug video pipeline issues:
  ```bash
  (gdb) break IMPFramesource::getFrame
  (gdb) break VideoWorker::processFrame
  ```

- Debug RTSP streaming:
  ```bash
  (gdb) break RTSP::handleRequest
  (gdb) break IMPServerMediaSubsession::createNewStreamSource
  ```

- Debug audio processing:
  ```bash
  (gdb) break AudioWorker::run
  (gdb) break IMPAudio::capture
  ```

## Safety Considerations

- Debugging may affect camera performance
- Use breakpoints sparingly in production
- Monitor camera temperature during extended debugging
- Be aware that debugging may interrupt video streams
- Always test fixes in development environment first

## Useful Resources

- [GDB Manual](https://sourceware.org/gdb/documentation/)
- [Thingino Documentation](https://github.com/themactep/thingino-firmware)
- MIPS Architecture Reference
- Ingenic T31 SDK Documentation
