BusyBox top
===========

Default `top` window
--------------------

```
Mem: 32336K used, 4576K free, 212K shrd, 3400K buff, 12256K cached
CPU:  0.0% usr 18.1% sys  0.0% nic 81.8% idle  0.0% io  0.0% irq  0.0% sirq
Load average: 4.12 1.07 0.36 1/93 6123
  PID  PPID USER     STAT   VSZ %VSZ CPU %CPU COMMAND
 1073     1 root     S    42888115.7   0  9.0 /bin/prudynt
 2256     1 root     S     3084  8.3   0  0.0 /sbin/telegrambot
 1217     1 root     S     2416  6.5   0  0.0 /sbin/wpa_supplicant ...
```

Default `top` (no flags) shows one row per **process**, sorted by CPU usage descending.
Use `top -H` to show individual **threads** instead.

### Header lines explained

`Mem: 32336K used, 4576K free, 212K shrd, 3400K buff, 12256K cached`

- **used** = RAM actively used by processes/kernel
- **free** = completely unused RAM
- **shrd** = shared memory (libs, etc.)
- **buff** = buffers for block I/O
- **cached** = page cache (file data); can be reclaimed under pressure

Effective free ≈ `free + buff + cached`.
On a camera with 64 MB total RAM, 23 MB is typically reserved as `rmem` for ISP/media hardware and never appears here at all.

`CPU: 0.0% usr 18.1% sys 0.0% nic 81.8% idle 0.0% io 0.0% irq 0.0% sirq`

- **usr** = user-space processes
- **sys** = kernel / syscall overhead
- **nic** = niced (low-priority) user processes
- **idle** = CPU has nothing to do
- **io** = waiting for I/O (high value → storage or network bottleneck)
- **irq** = hardware interrupt handlers
- **sirq** = soft-IRQ handlers (network, timers, etc.)

High **sys** with low **usr** usually means the kernel is spending more time serving syscalls and interrupts than running application code — common when video pipeline DMA is not used and the CPU copies frame buffers manually.

`Load average: 4.12 1.07 0.36 1/93 6123`

- Three numbers: average number of runnable + uninterruptible tasks over the last **1 / 5 / 15 minutes**
- On a **single-core** CPU (T20, T23, T31…) load **1.0 = 100% utilized**; load 4.0 = four tasks waiting for every one running
- `1/93` = 1 task currently running out of 93 total
- `6123` = most recently assigned PID

### Process list columns

`PID PPID USER STAT VSZ %VSZ CPU %CPU COMMAND`

- **PID** = process ID
- **PPID** = parent PID
- **USER** = owner
- **STAT** = process state (see table below)
- **VSZ** = virtual address space size (KiB); includes mmap'd media regions — usually large for prudynt and not a useful indicator of real RAM use
- **%VSZ** = VSZ as % of total RAM; misleading for media processes, ignore it
- **CPU** = last CPU core used (always `0` on single-core SoCs)
- **%CPU** = CPU usage over the last sample interval
- **COMMAND** = executable path and arguments; kernel threads appear in `[brackets]`

### STAT values

The STAT field is one base letter optionally followed by modifier flags.

**Base state:**

| Letter | Meaning |
|--------|---------|
| `R` | **Running** — on CPU or in the run queue right now |
| `S` | **Sleeping** — waiting for an event (interruptible); wakes on signal |
| `D` | **Disk sleep** — uninterruptible sleep, usually waiting for I/O or hardware; cannot be killed with signals |
| `Z` | **Zombie** — process exited but parent has not yet called `wait()`; consumes no resources except a PID slot |
| `T` | **Stopped** — paused by `SIGSTOP` or a debugger |
| `W` | **Paging** — obsolete on kernels ≥ 2.6; appears on some Ingenic 3.10 kernels for kernel threads with no backing pages |

**Modifier flags** (appended after base letter):

| Flag | Meaning |
|------|---------|
| `<` | High priority (negative nice value) |
| `N` | Low priority (positive nice value / niced) |
| `s` | Session leader |
| `l` | Multi-threaded |
| `+` | In the foreground process group |

Common combinations on Thingino cameras:

| STAT | What you're looking at |
|------|------------------------|
| `S` | Normal sleeping process |
| `R` | Active process (or the `top` process itself) |
| `SW` | Kernel thread sleeping with no page backing |
| `SW<` | High-priority kernel thread (e.g. IRQ threads) |
| `SWN` | Low-priority kernel thread (e.g. `jffs2_gcd_*` garbage collector) |
| `DW` | Kernel thread stuck in uninterruptible I/O — normal for `[isp_fw_process]` waiting on ISP hardware; prolonged `D` in a user process indicates a hardware or driver stall |
| `Sl` | Multi-threaded sleeping process (e.g. `prudynt` with its worker threads) |
| `Z` | Zombie — investigate if count grows over time |

A rising count of `D`-state processes combined with high **sys** CPU and load spikes usually points to ISP or flash driver contention.

Using `top -H` for threads view
----------------------------------

```
Mem: 14140K used, 908K free, 132K shrd, 368K buff, 1880K cached
CPU:  1.2% usr  6.4% sys  0.0% nic 92.3% idle  0.0% io  0.0% irq  0.0% sirq
Load average: 2.30 1.81 1.73 1/63 4583
  PID  PPID USER     STAT   VSZ %VSZ CPU %CPU COMMAND
 2215     2 root     DW       0  0.0   0  1.8 [isp_fw_process]
 1356     1 root     S     2448 16.2   0  1.7 /sbin/wpa_supplicant -i wlan0 -c /etc/wpa_supplicant.conf -P /run/wpa_supplicant.wlan0.pid -B
```
### Header lines explained:

`Mem: 14128K used, 920K free, 132K shrd, 392K buff, 1604K cached`

- **used** = RAM actively used by processes/kernel
- **free** = completely unused RAM
- **shrd** = shared memory (libs, etc.)
- **buff** = buffers for block I/O
- **cached** = page cache (file data)

`CPU: 0.0% usr 18.1% sys 0.0% nic 81.8% idle 0.0% io 0.0% irq 0.0% sirq`

- **usr** = user processes
- **sys** = kernel/system
- **nic** = niced (low-priority) user processes
- **idle** = CPU waiting
- **io** = I/O wait
- **irq** = hardware interrupts
- **sirq** = softirqs

`Load average: 1.68 1.67 1.68 1/63 4552`

- 1/5/15 min averages of runnable + uninterruptible tasks
- 1/63 = running/total tasks
- 4552 = last PID

### Process list columns:

`PID PPID USER STAT VSZ %VSZ CPU %CPU COMMAND`

- **PID** = process ID
- **PPID** = parent PID
- **USER** = owner
- **STAT** = state (S=sleep, R=run, D=uninterruptible, etc.)
- **VSZ** = virtual memory size (KiB)
- **%VSZ** = VSZ / total RAM (misleading in BusyBox)
- **CPU** = last used CPU (here single-core → mostly 0)
- **%CPU** = CPU usage %
- **COMMAND** = process name/args


Using `top -m` for memory analysis
----------------------------------

```
Mem total:15048 anon:2596 map:1112 free:964
 slab:4640 buf:412 cache:1576 dirty:0 write:0
Swap total:0 free:0
  PID^^^VSZ^VSZRW   RSS (SHR) DIRTY (SHR) STACK COMMAND
 2134 56552 52560  2156   128  1644     0   132 /bin/streamer
 1356  2444   268   308   124   156     0   132 /sbin/wpa_supplicant -i wlan0 -c /etc/wpa_supplicant.conf -P /run/wpa_supplicant.wlan0.pid -B
  658  1804   248   248   120   128     0   132 /sbin/syslogd -n -C64 -S -t -D
 2211  1756   200   396   204    84     0   132 -sh
 4544  1748   192   448   220    76     0   132 top -m
    1  1748   192   184   112    72     0   132 init
 1782  1748   192   260   168    72     0   132 /sbin/ntpd -n -S /etc/ntpd_callback
 1687  1744   188   268   196    68     0   132 udhcpc -x hostname:ing-okam-qc3-921e -S -T1 -t15 -R -b -O search -O 100 -O 101 -O 160 -p /var/run/udhcpc.wlan0.pid -i wlan0
  941  1292   188   184   116    68     0   132 /sbin/dropbear -k -K 300 -R
 1846  1172   280   400   140   220     0   132 /sbin/mdnsd -i wlan0 -s
 1709  1056   188   236   120    76     0   132 /sbin/odhcp6c -d -v -p /run/odhcp6c.pid -t120 wlan0
```

- **Mem total** → total RAM, in KB
- **anon** → anonymous memory (mostly process heap/stack), in KB
- **map** → memory-mapped files, in KB
- **free** → completely free RAM, in KB
- **slab** → kernel slab allocator, in KB
- **buf** → buffer cache
- **cache** → page cache
- **dirty/write** → dirty data waiting to be written

### Process list columns:

- **VSZ**   = virtual size (reserved address space)
- **VSZRW** = writable part of virtual memory
- **RSS**   = resident set size – real RAM used right now
- **(SHR)** = shared part of RSS (libraries, etc.)
- **DIRTY** = private dirty pages (will be written if process exits)
- **STACK** = main thread stack size

Most memory is usually eaten by kernel slab caches, not user processes.
Typical for small embedded Linux system with very little RAM.