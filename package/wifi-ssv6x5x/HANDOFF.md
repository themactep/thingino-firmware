# SSV6X5X Linux 7.3 port - handoff

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

On failure, rerun serial:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make dev
```

The dummy defconfig currently selects `BR2_PACKAGE_WIFI_SSV6X5X`
(`pid_6000` branch, version `9c56144`).

## State

Patches `0001`-`0002` are in this package. The driver compiles most of
the tree but the module does not link yet.

`0001`:

- anchor `KBUILD_TOP` at `M` when kbuild drives the build
- feed `EXTRA_CFLAGS` through `ccflags-y` / `subdir-ccflags-y`
- relax `missing-prototypes` and `old-style-declaration`

`0002`:

- `bss_info_changed` changed argument is `u64`
- `conf_tx` takes `link_id`
- `set_rts_threshold` takes `radio_idx`
- association state via `vif->cfg.assoc`
- `static void inline` -> `static inline void`

## Current failures

- `MODULE_IMPORT_NS(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver)`
  is still present in `hci/ssv_hci.c`, `hwif/hal/hwif_hal.c`,
  `smac/hal/ssv6006c/ssv6006_common.c` and `smac/hw_scan.c`.
- `hwif/sdio/sdio.c`: `strncpy` was removed; needs the local helper
  used in the other drivers.
- `smac/ap.c`: `ieee80211_beacon_get_tim()` now takes five arguments.
- `smac/dev.c:125`: `cpu_clock()` was removed.
- `smac/dev.c:2072`: unused `changed_flags`.
- `smac/dev.c` and `smac/hw_scan.c`: remaining
  `bss_conf.assoc` and `bss_conf.aid` uses.
- `smac/dev.c`: `ieee80211_sta.supp_rates` / `.ht_cap` moved to the
  link station; `vif->chanctx_conf` moved.
- `smac/dev.c:893`: `ieee80211_tx_status()` is gone.
- `smac/efuse.c`: `mm_segment_t` / `set_fs`.
- `smac/dev.c:3191`, `3195`: remaining ops table mismatch
  (`sw_scan_start` and `set_rts_threshold`).

## Suggested order

1. Remove the `MODULE_IMPORT_NS` lines.
2. Add the `strncpy` helper and fix `mm_segment_t`.
3. Fix the station/link station field moves and `vif->cfg` fields.
4. Fix `ieee80211_tx_status`, `ieee80211_beacon_get_tim` and
   `cpu_clock`.
5. Finish the ops table (scan callbacks and thresholds).
6. Rebuild with `make dev` after each group.

Keep `LINUX_VERSION_CODE` guards for the older vendor kernels.
