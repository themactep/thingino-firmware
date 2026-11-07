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
- `0004` size the RX reorder array for all 16 TIDs
- `0005` default `aicwf_dbg_level` to LOGERROR unless `CONFIG_RWNX_DBG`
  is built in (USB, SDIO, PCIE fdrv)
- `0006` route the USB aic_load_fw lifecycle and command-queue traces
  through `AICWFDBG(LOGINFO, ...)`
- `0007` route the tcp-ack init/deinit traces through `AICWFDBG(LOGINFO, ...)`

The bluetooth namespace guard and the aic_load_fw/BSP default log levels
are handled by post-patch hooks in the package `.mk` because
`aic_bluetooth_main.c` is CRLF and the BSP has no `CONFIG_RWNX_DBG`.
