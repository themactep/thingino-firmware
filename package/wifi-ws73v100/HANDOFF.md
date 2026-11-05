# WS73V100 Linux 7.3 port

Status: complete. `ws73v100.ko` and `ws73v100_plat.ko` build against the
7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

The dummy defconfig selects `BR2_PACKAGE_WIFI_WS73V100` with the USB
bus.

Patches in this package:

- `0002-linux-7.3-platform.patch` feed the driver includes/defines into
  kbuild, use `linux/stdarg.h`/`linux/stddef.h`, replace the removed
  uaccess helpers, `netif_rx_ni` and `random_ether_addr`, and switch
  the firmware stat path to `kern_path`
- `0003-linux-7.3-wifi.patch` timer deletes, `inode_get_ctime`,
  platform uaccess/remove and Wi-Fi OAL file access, the Wi-Fi OAL
  `oal_random_ether_addr`/`oal_netif_rx_ni` call sites, and the
  disabled diag socket/local-log transports
- `0004-linux-7.3-cfg80211-ops.patch` 7.3 wrappers for the
  `wireless_dev`, `link_id`, `radio_idx` and scalar ROC/mgmt-tx cookie
  ABI, roam/station notification updates, and the removed VFS namespace
  and proc PDE helpers
