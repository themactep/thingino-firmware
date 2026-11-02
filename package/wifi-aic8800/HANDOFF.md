# AIC8800 Linux 7.3 port - handoff

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

On failure, rerun serial:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make dev
```

The dummy defconfig currently selects `BR2_PACKAGE_WIFI_AIC8800`
(USB source, `a870f7f`).

## State

Patch `0002` is in this package. It removes the VFS
`MODULE_IMPORT_NS` and uses the anonymous `ieee80211_mgmt` action
union on 7.3.

The driver compiles most of the tree; the module does not link yet.

## Current failures

`aic8800_fdrv/rwnx_main.c`:

- cfg80211 ops still need the 7.3 `wireless_dev` conversions:
  `add_key`, `get_key`, `del_key`, key defaults, station add/del/
  change, `get_station`, `dump_station`, `set_monitor_channel`
  (`netdev` argument), `set_wiphy_params` / `set_tx_power`
  (`radio_idx`), `remain_on_channel`/`mgmt_tx` cookie ABI.
- `probe_client` was removed from `cfg80211_ops`.
- `cfg80211_ch_switch_notify` / `cfg80211_ch_switch_started_notify`
  argument counts changed.
- `cfg80211_new_sta` / `cfg80211_del_sta` still take the net device.
- `cfg80211_probe_status` gained an argument.
- `from_timer`, `del_timer_sync`, `del_timer` and `in_irq` are gone.
- `strncpy` is gone.

`aic8800_fdrv/rwnx_rx.c`:

- same timer/`in_irq` replacements.
- `cfg80211_rx_spurious_frame` / `cfg80211_rx_unexpected_4addr_frame`
  gained a wireless-device argument.

`aic8800_fdrv/rwnx_tdls.c`:

- `tdls_discover_resp` no longer carries `action_code`; the outer
  `action_code` is the right field on 7.3.

`aic8800_fdrv/rwnx_wakelock.c`:

- `wakeup_source_create` / `_add` / `_remove` were replaced by
  `wakeup_source_register` / `wakeup_source_unregister`.

## Suggested order

1. `strncpy` helper and timer/`in_irq` renames.
2. cfg80211 ops conversions, watching which callbacks still take a
   net device (key defaults do).
3. Station/BSS notification calls and the ch-switch notify
   signatures.
4. TDLS `action_code` and wakelock.
5. Rebuild with `make dev` after each group.

Keep `LINUX_VERSION_CODE` guards for older vendor kernels.
