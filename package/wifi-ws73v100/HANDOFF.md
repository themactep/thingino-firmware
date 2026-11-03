# WS73V100 Linux 7.3 port - handoff

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

The dummy defconfig selects `BR2_PACKAGE_WIFI_WS73V100` with the USB
bus.

## State

Partial. The platform layer now gets through the first kernel API
pass; the Wi-Fi WAL cfg80211 ops table is the current blocker.

`0002-linux-7.3-platform.patch`:

- feed the driver includes/defines into kbuild
- `linux/stdarg.h` / `linux/stddef.h`
- replace `force_uaccess_begin/end`, `netif_rx_ni`, `random_ether_addr`
- `kern_path` instead of `user_path_at_empty`

`0003-linux-7.3-wifi.patch`:

- timer deletes, `inode_get_ctime`
- platform uaccess/remove and Wi-Fi OAL file access
- Wi-Fi OAL `oal_random_ether_addr` and `oal_netif_rx_ni` call sites
- diag socket/local-log transports disabled in the package `.mk`

## Current failures

`wal/release/linux/wal_linux_cfg80211.c` ops table:

- `set_wiphy_params` needs `radio_idx`
- `change_beacon` takes `cfg80211_ap_update`
- `stop_ap` takes `link_id`
- `add_station`/`del_station`/`change_station`/`get_station`/
  `dump_station` need `wireless_dev`
- `remain_on_channel` / `mgmt_tx` need the scalar cookie ABI
- `set_bitrate_mask` needs `link_id`

## Suggested order

Add a `#if >= 7.3` wrapper block for those ops (the same pattern as
the mt7601u/aic8800/syn4343 ports), then rebuild with `make dev` and
continue through the remaining WAL/mac80211 helpers.
