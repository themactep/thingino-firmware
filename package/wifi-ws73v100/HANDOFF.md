# WS73V100 Linux 7.3 port - handoff

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

The dummy defconfig selects `BR2_PACKAGE_WIFI_WS73V100` with the USB
bus.

## State

Partial. The platform build now resolves its includes and the first
layer of kernel API changes; the module does not build yet.

`0002-linux-7.3-platform.patch`:

- feed the driver's include/defines into kbuild
- use `linux/stdarg.h` / `linux/stddef.h`
- replace the removed `force_uaccess_begin/end`, `netif_rx_ni`,
  `random_ether_addr`
- use `kern_path` instead of `user_path_at_empty`

## Current failures

Platform layer:

- `diag/zdiag_adapt/zdiag_local_log.c`: `vfs_mkdir`/`vfs_unlink`/
  `done_path_create` signatures and the removed VFS namespace import.
- `diag/zdiag_adapt/zdiag_linux_socket.c`: `kernel_bind` sockaddr
  length type.

Wi-Fi layer:

- `inc/oal/linux/oal_kernel_file.h`: `mm_segment_t` and
  `force_uaccess_begin/end` (same fix as the platform copy).
- `hmac/hmac_config.c`: `oal_random_ether_addr` is not declared.
- `hmac/hmac_main.c`: `oal_netif_rx_ni` was removed.

## Suggested order

1. Mirror the platform uaccess/random/netif fixes in the Wi-Fi OAL
   copy.
2. Port or disable the zdiag VFS log/socket helpers for 7.3.
3. Rebuild with `make dev` after each group.

The tree is 263k lines; expect further VFS/mac80211 helpers after these
sites.
