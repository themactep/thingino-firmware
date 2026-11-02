# MT7601U Linux 7.3 port - handoff

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

On failure, rerun serial:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make dev
```

The dummy defconfig currently selects `BR2_PACKAGE_WIFI_MT7601U`.

## State

Patches `0001`-`0004` are in this package. The driver compiles most of
the tree but the module does not link yet.

`0002`-`0004`:

- feed `EXTRA_CFLAGS` into kbuild through `subdir-ccflags-y`
- use `linux/unaligned.h`
- guard the driver's `IEEE80211_RADIOTAP_*` enum for 7.3
- provide `rtw_strncpy` because `strncpy` was removed
- use `linux/stdarg.h`
- remove `mm_segment_t` / `get_fs()` / `set_fs()`
- `kernel_read()` / `kernel_write()` for the file helpers
- first `set_fs` dump-function conversions

## Current failures

`os/linux/rt_linux.c`:

- `123`-`125`: `init_timer()` and `timer.data` / `.function` in
  `__RTMP_OS_Init_Timer()`
- `154`: `del_timer_sync()` in `__RTMP_OS_Del_Timer()`
- `2184`-`2185`: remaining `get_fs()` / `set_fs()` block
- `2232`: remaining `mm_segment_t`
- `3390`, `3438`: `struct timespec` + `get_monotonic_boottime()`
- `3719`, `3727`: `cfg80211_new_sta()` / `cfg80211_del_sta()` still
  pass the net device

`os/linux/sta_ioctl.c`:

- `2811`: `access_ok()` now takes two arguments

## Suggested order

1. Add a 4.15+ timer shim for `__RTMP_OS_Init_Timer()` and
   `__RTMP_OS_Del_Timer()`. The timer callbacks take `unsigned long`,
   so a small trampoline or a wrapper around `struct timer_list` is
   needed; see the watchdog/tcpack approach in `wifi-syn4343`.
2. Finish the remaining `set_fs` dump functions.
3. `timespec` -> `timespec64`, `get_monotonic_boottime()` ->
   `ktime_get_boottime_ts64()`.
4. Pass `pNetDev->ieee80211_ptr` (or the stored wdev) to
   `cfg80211_new_sta()` / `cfg80211_del_sta()`.
5. `access_ok(ptr, len)`.

Keep `LINUX_VERSION_CODE` guards; this package still builds for older
vendor kernels.
