exfat driver performance testing
=============================

Here are several ways to benchmark the performance improvements on your embedded device:

### 1. Basic Sequential Read Test with `dd`

```
# Create a large test file first (if you have space)
dd if=/dev/urandom of=/path/to/exfat/testfile bs=1M count=100

# Test sequential read performance
dd if=/path/to/exfat/testfile of=/dev/null bs=4k
dd if=/path/to/exfat/testfile of=/dev/null bs=64k
dd if=/path/to/exfat/testfile of=/dev/null bs=1M

# Time the operations
time dd if=/path/to/exfat/testfile of=/dev/null bs=64k
```

### 2. Compare Small vs Large Block Sizes

The optimization is most effective with small cluster sizes:

```
# Small blocks (where optimization helps most)
time dd if=/path/to/exfat/testfile of=/dev/null bs=512 count=204800

# Larger blocks
time dd if=/path/to/exfat/testfile of=/dev/null bs=64k count=1600
```

### 3. Monitor I/O Statistics

```
# Before test
cat /proc/diskstats | grep mmcblk0

# Run your test
dd if=/path/to/exfat/largefile of=/dev/null bs=4k

# After test - compare read operations
cat /proc/diskstats | grep mmcblk0
```

### 4. Use `hdparm` if available

```
# Test raw read speed
hdparm -tT /dev/mmcblk0p1

# Buffered disk reads
hdparm -t /dev/mmcblk0p1
```

### 5. Kernel Timing with dmesg

Add timing info to see get_block call frequency:

```
# Watch kernel messages during large file copy
dmesg -w &
cp /path/to/exfat/largefile /tmp/
```

### 6. Create Test Files of Different Patterns

```
# Sequential file (best case for our optimization)
dd if=/dev/zero of=/path/to/exfat/sequential bs=1M count=50

# Test with real-world files
cp /some/large/media/file.mp4 /path/to/exfat/
time cp /path/to/exfat/file.mp4 /dev/null
```

### 7. Compare Before/After

If you have the old driver version:

```
# Load old driver, test, record results
# Load new driver (1.2.10-multicluster), test again
# Compare throughput numbers
```

### Expected Results

* Most improvement: Small cluster sizes (512-4KB) with sequential reads
* Typical gain: 10-15% better throughput
* Best test case: Large files read sequentially with small block sizes

The improvement will be most noticeable in scenarios like media playback,
large file transfers, or any sequential file operations on filesystems with
small cluster sizes.
