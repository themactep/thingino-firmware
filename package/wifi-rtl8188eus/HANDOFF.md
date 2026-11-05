# RTL8188EUS Linux 7.3 port

Status: complete. `8188eu.ko` builds against the 7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

The driver was bumped to the upstream `v5.3.9` head.

Patches in this package:

- `0001-apmode.patch` enable AP mode
- `0004-linux-7.3-build-flags.patch` feed `EXTRA_CFLAGS` into kbuild
- `0005-linux-7.3-driver-compat.patch` disable the bridge extension and
  use the 7.3 timer helpers
- `0006-linux-7.3-cfg80211.patch` 7.3 wrappers for the
  `wireless_dev`/`link_id`/`radio_idx` and scalar ROC/mgmt-tx cookie
  ABI, station notifications and `strncpy`
