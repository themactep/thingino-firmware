# AIC8800 Linux 7.3 port

Status: complete. `aic8800_fdrv.ko` and `aic_load_fw.ko` build against
the 7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

Patches in this package:

- `0001` slim down the vendor tree
- `0002` drop the VFS `MODULE_IMPORT_NS` and use the anonymous
  action union on 7.3
- `0003` cfg80211 `wireless_dev`/`radio_idx` conversions, ROC/mgmt-tx
  cookie ABI, ch-switch and station notifications, timer/NAPI helpers,
  `strncpy`, wakelock, TDLS action code

The bluetooth namespace guard is handled by a post-patch hook in the
package `.mk` because that file is CRLF.
