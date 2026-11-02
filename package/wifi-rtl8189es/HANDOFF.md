# RTL8189ES Linux 7.3 port - handoff

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

On failure, rerun serial:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make dev
```

The dummy defconfig currently selects `BR2_PACKAGE_WIFI_RTL8189ES`.

## State

Patches `0002`-`0005` are in this package:

- `0002` feed `EXTRA_CFLAGS` into kbuild and anchor includes at `PWD`
- `0003` include `linux/timer.h`
- `0004` 7.3 timer names (`timer_container_of`, `timer_delete_sync`)
- `0005` disable `CONFIG_BR_EXT`

The driver compiles most of the tree but the module does not link yet.

## Current failures

- `strncpy` is gone; it is used in `os_dep/linux/ioctl_linux.c`,
  `os_dep/linux/ioctl_cfg80211.c`, `hal/hal_com.c` and
  `hal/hal_com_phycfg.c`. Add the local helper/macro used in the
  other Realtek drivers.
- `os_dep/linux/ioctl_cfg80211.c`:
  - `cfg80211_new_sta()` / `cfg80211_del_sta()` still pass the net
    device (`4419`, `4465`).
  - ops table (`9966` and below): key ops, `get_station`,
    `set_rts_threshold`, `set_tx_power`/`get_tx_power`,
    `add_station`/`del_station`/`change_station`,
    `remain_on_channel`/`mgmt_tx` cookie ABI.

## Suggested order

Use `package/wifi-rtl8188fu/0010-linux-7.3-driver-compat.patch` as
the reference:

1. Add the `strncpy` helper.
2. Convert the cfg80211 ops to `wireless_dev` / `radio_idx`.
3. Convert the ROC/mgmt-tx cookie ABI.
4. Fix `cfg80211_new_sta()` / `del_sta()`.
5. Rebuild with `make dev` after each group.

Keep `LINUX_VERSION_CODE` guards for older vendor kernels.
