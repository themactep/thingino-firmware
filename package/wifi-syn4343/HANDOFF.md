# SYN4343 / bcmdhd Linux 7.3 port - handoff

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

On failure, rerun serial to get the exact site:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make dev
```

The dummy defconfig currently selects `BR2_PACKAGE_WIFI_SYN4343`.

## State

Patches `0001`-`0004` are in this package. The driver gets through
compilation of the build plumbing and the first batch of legacy APIs,
but the module does not build yet.

`0001`-`0003`:

- feed `DHDCFLAGS` into kbuild through `subdir-ccflags-y`
- anchor `-I` paths at `PWD`
- drop `net/lib80211.h`
- use `linux/unaligned.h` and `linux/pci.h`
- replace `ioremap_nocache()` with `ioremap()`

`0004`:

- `getnstimeofday()` -> `ktime_get_real_ts64()`
- `init_timer()` + `.data` -> `timer_setup()` for the watchdog and
  tcpack timers
- `del_timer_sync()` -> `timer_delete_sync()`
- `netif_rx_ni()` -> `netif_rx()`
- `smp_read_barrier_depends()` -> `smp_rmb()`
- `complete_and_exit()` -> `kthread_complete_and_exit()`
- `prandom_u32()` -> `get_random_u32()` (some uses remain)
- new `kernel_read()` / `kernel_write()` signatures, no `set_fs()`
- `pci_map_*()` -> `dma_map_*()`, `PCI_DMA_*` -> `DMA_*`
- `cfg80211_roamed()` / `scan_done()` / `disconnected()` at the
  call sites already reached
- `strlcpy()` -> `strscpy()`, `strnicmp()` -> `strncasecmp()`

## Current failures

Start from `wl_cfg80211.c`:

1. `cfg80211_ops` table (`wl_cfg80211.c:8650` and below) still uses
   `struct net_device *` and pre-7.3 parameter lists:
   - `add_virtual_intf` / `del_virtual_intf` (`u32 *` -> `int`,
     `wireless_dev`)
   - `get_station` (`wireless_dev`, `const u8 *`)
   - `set_tx_power` / `get_tx_power` (`radio_idx`)
   - key ops (`add_key`, `get_key`, `del_key`, `set_default_key`,
     `set_default_mgmt_key`)
   - `set_power_mgmt`, `change_beacon`, `stop_ap`
   - `remain_on_channel` / `mgmt_tx` cookie ABI
   - `mgmt_frame_register` was replaced by
     `update_mgmt_frame_registrations`
2. `IEEE80211_BAND_2GHZ` / `IEEE80211_BAND_5GHZ` are gone; use
   `NL80211_BAND_*`. `IEEE80211_NUM_BANDS` -> `NUM_NL80211_BANDS`.
3. `STATION_INFO_*` flags are gone; use `NL80211_STA_INFO_*` and the
   `station_info.filled` bitmap.
4. `wireless_dev.preset_chandef` is gone; use `links[0].chandef`.
5. Remaining notification call sites:
   - `cfg80211_scan_done()` at `wl_cfg80211.c:12992`, `15367`
   - `cfg80211_disconnected()` at `wl_cfg80211.c:13107`, `5286`
6. Remaining timer/legacy calls:
   - `wl_cfg80211.c:2800` `del_timer_sync()`
   - `wl_cfg80211.c:11856` `timer.data` / `.function`
   - `wl_cfg80211.c:12329` `complete_and_exit()`
   - `include/linuxver.h:720` `prandom_u32()`

## Suggested order

1. Rewrite the `cfg80211_ops` signatures and add `wdev_to_ndev()`
   shims where the old body only uses the net device.
2. Convert the band enums and station-info flags.
3. Replace `preset_chandef` and finish the notification call sites.
4. Fix the remaining timers and randomness calls.
5. Rebuild with `make dev` after each group; do not batch fixes without
   a compile.

Keep `LINUX_VERSION_CODE` guards: the package is still used on the
older vendor kernels for other cameras. Useful references are the
mainline/Infineon bcmdhd tree and the `wifi-rtl8189fs` 7.3 patches for
the cfg80211 op shapes.
