# WQ9001 Linux 7.3 port - handoff

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

On failure, rerun serial:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make dev
```

The dummy defconfig currently selects `BR2_PACKAGE_WIFI_WQ9001`.

## State

Patch `0001` is in this package. It removes the driver's private
definitions of the standard `IFF_*` flags on 7.3 (the kernel's
`linux/if.h` provides them) and relaxes `missing-prototypes`.

The module does not build yet.

## Current failures

`oss/_if.h`:

- `IFF_RUNNING` alias still collides with the kernel.
- the driver's `struct ifreq` / `ifr_flags` / `ifr_metric` collide
  with the uapi `linux/if.h`; the private `struct ifreq` block needs
  to be skipped on 7.3.

`oss/net_if.c`:

- `strncpy` was removed; add the local helper used in the other
  drivers.

`wdrv/wuqi_cfg80211_port.h`:

- `mm_segment_t` is gone; remove the file-I/O `set_fs` state.

`wproto/net80211/ieee80211_input.c`:

- `in_irq()` is gone; use `in_interrupt()`.

`wifi_drv.c`:

- `cfg80211_new_sta()` / `cfg80211_del_sta()` still pass the net
  device instead of the wireless device.
- `cfg80211_inform_bss.scan_width` was removed; build the
  `cfg80211_inform_bss_data`/`cfg80211_inform_bss_frame_data`
  arguments for the current API.
- `netif_rx_ni()` -> `netif_rx()`.

## Suggested order

1. Finish the `oss/_if.h` 7.3 guards (`IFF_RUNNING`, private
   `struct ifreq` and `ifr_*` fields).
2. Add `strncpy` and remove the `mm_segment_t` file-I/O state.
3. Replace `in_irq()` and `netif_rx_ni()`.
4. Move the cfg80211 station notifications to the wireless device and
   update the BSS inform call.
5. Rebuild with `make dev` after each group.

Keep `LINUX_VERSION_CODE` guards for older vendor kernels.
