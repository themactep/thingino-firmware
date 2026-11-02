# HI3881 Linux 7.3 port - handoff

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

On failure, rerun serial:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make dev
```

The dummy defconfig currently selects `BR2_PACKAGE_WIFI_HI3881`.

## State

Patch `0001` feeds the driver's `EXTRA_CFLAGS` into
`ccflags-y`/`subdir-ccflags-y`, which gets the driver past its own
header includes.

The module does not build yet.

## Current failures

`driver/oal/oal_net.h`:

- `alloc_netdev` now takes four arguments.
- `netif_rx_ni()` is gone; use `netif_rx()`.
- `struct netlink_kernel_cfg.cb_mutex` was removed.

`driver/oal/oal_file.h`:

- `KERNEL_DS` / `set_fs` are gone.
- `kernel_read()` argument order changed.

`driver/oal/oal_wait.h`:

- `wait_queue_t` -> `wait_queue_entry_t`.

`driver/oal/oal_net.c`:

- `IEEE80211_BAND_2GHZ/5GHZ` -> `NL80211_BAND_*`.
- `IEEE80211_NUM_BANDS` -> `NUM_NL80211_BANDS`.
- `struct ieee80211_supported_band` / band storage changed.

`driver/mac/hmac/dmac_ext_if.h`:

- `timestamp_us` has an incomplete type; use `struct timespec64` or
  the equivalent 64-bit time type.

## Suggested order

1. `wait_queue_t`, `netif_rx_ni`, `netlink_kernel_cfg.cb_mutex`.
2. `set_fs`/`kernel_read`.
3. `alloc_netdev` and the band enums.
4. `timestamp_us` time type.
5. Rebuild with `make dev` after each group.

Keep `LINUX_VERSION_CODE` guards for older vendor kernels.
