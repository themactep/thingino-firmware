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

Patches `0002`-`0005` are in this package. The timer shim and the
first legacy-API batch are done; the module does not link yet.

`0005` adds:

- a map-based trampoline for the removed `timer.data`/`function` ABI
- `timer_delete_sync` for the cancel path
- the remaining `set_fs` guards
- `timespec64` + `ktime_get_boottime_ts64`
- wireless-device arguments for `cfg80211_new_sta` / `del_sta`
- two-argument `access_ok`

## Current failures

`os/linux/cfg80211.c`:

- `add_virtual_intf` / `change_virtual_intf` still carry the old
  `u32 *flags` argument.
- `set_tx_power` / `get_tx_power` / `set_wiphy_params` need
  `radio_idx` (and `link_id` for get_tx_power).
- `get_station` / `dump_station` need `wireless_dev`.
- key ops need `wireless_dev` + `link_id`; the default-key op stays on
  the net device.
- `remain_on_channel` / `mgmt_tx` need the scalar cookie ABI.
- `mgmt_frame_register` was removed from `cfg80211_ops`.
- `change_beacon` takes `cfg80211_ap_update`; `stop_ap` takes
  `link_id`.
- `set_monitor_channel` needs the net device argument.
- station add/del/change need `wireless_dev`.

`os/linux/cfg80211drv.c`:

- `struct timeval` / `do_gettimeofday()` at two sites.

`ap/ap_mlme.c`:

- `stdarg.h` -> `linux/stdarg.h`.

## Suggested order

1. `stdarg.h` and the `cfg80211drv.c` time conversion.
2. `cfg80211.c` virtual-interface and tx-power signatures.
3. Station and key ops, then ROC/mgmt-tx cookies.
4. `change_beacon`, `stop_ap`, monitor channel and the removed
   `mgmt_frame_register`.
5. Rebuild with `make dev` after each group.

Use the RTL8188FU and AIC8800 7.3 patches as references.
