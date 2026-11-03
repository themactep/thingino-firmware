# SSV6158 Linux 7.3 port

Status: complete. `ssv6158.ko` builds against the 7.3.1 kernel, including
the proc/CLI interface.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

Patches in this package:

- `0001` anchor `KBUILD_TOP` at `M` and feed `EXTRA_CFLAGS` into kbuild
- `0002` disable the Android wakelock path, add the 7.3 common helper
  header (`ssv_strncpy`, `MODULE_SUPPORTED_DEVICE`) and relax vendor
  warnings
- `0003` mac80211 callbacks (`bss_info_changed`, `conf_tx`, `stop`,
  `config`, `set_rts_threshold`), station/link-station fields,
  `vif->cfg`, `tx_status_ni`, timers, platform remove, `beacon_get_tim`,
  efuse `set_fs`, `proc_ops`, `pde_data`, hw-scan association and local
  export cleanup

The package `POST_PATCH_HOOKS` include the compatibility header in the
module sources.
