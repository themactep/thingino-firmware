# RTL8733BU Linux 7.3 port - handoff

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

On failure, rerun serial:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make dev
```

The dummy defconfig currently selects `BR2_PACKAGE_WIFI_RTL8733BU`.

## State

Patches `0002`-`0005` are in this package:

- `0002` feed `EXTRA_CFLAGS` into kbuild and anchor includes at `PWD`
- `0003` include `linux/timer.h`
- `0004` use the 7.3 timer names (`timer_container_of`,
  `timer_delete_sync`, `timer_delete`)
- `0005` disable `CONFIG_BR_EXT`, which needs removed AppleTalk and
  PPPoE wire structures

The driver compiles most of the tree but the module does not link yet.

## Current failures

`os_dep/linux/ioctl_cfg80211.c`:

- `cfg80211_new_sta()` / `cfg80211_del_sta()` still pass the net
  device (`5156`, `5202`).
- The ops table (`10649` and below) still uses `net_device` and the
  old parameter lists:
  - key ops need `wireless_dev` + `int link_id`
  - `get_station` needs `wireless_dev` + `const u8 *`
  - `set_rts_threshold` needs `radio_idx`
  - `set_tx_power` / `get_tx_power` need `radio_idx`
  - `change_beacon` takes `cfg80211_ap_update`
  - `add_station` / `del_station` / `change_station` need
    `wireless_dev`
  - `remain_on_channel` / `mgmt_tx` cookie ABI

`os_dep/linux/wifi_regd.c`:

- `REGULATORY_IGNORE_STALE_KICKOFF` was removed (`409`).

`os_dep/linux/rtw_proc.c`:

- `PDE_DATA` was removed (`250`); use `pde_data()`.

## Suggested order

The RTL8188FU port in `package/wifi-rtl8188fu/0010-linux-7.3-driver-compat.patch`
is the closest reference. Apply the same changes here, then fix the
rejects:

1. cfg80211 ops signatures and `wdev_to_ndev()` shims.
2. `cfg80211_new_sta()` / `del_sta()` wdev argument.
3. `PDE_DATA`.
4. `REGULATORY_IGNORE_STALE_KICKOFF`.

Keep `LINUX_VERSION_CODE` guards for older vendor kernels.
