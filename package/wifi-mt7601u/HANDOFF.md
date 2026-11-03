# MT7601U Linux 7.3 port

Status: complete. `mt7601sta.ko` builds against the 7.3.1 kernel,
including AP mode.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

Patches in this package:

- `0001` disable roaming
- `0002` feed `EXTRA_CFLAGS` into kbuild
- `0003` `linux/unaligned.h`
- `0004` radiotap enum, `strncpy`, `linux/stdarg.h`, file helpers,
  first `set_fs` blocks
- `0005` map-based timer trampoline, `timer_delete_sync`, remaining
  `set_fs`, `timespec64`, wireless-device station notifications,
  `access_ok`
- `0006` cfg80211 7.3 wrapper ops for virtual interfaces, tx power,
  station/key management, ROC/mgmt-tx, beacon/AP, monitor channel;
  time/destructor/pid/`access_ok` fixes

The package now also enables `CONFIG_CFG80211_WEXT`, which the driver
needs for `iwe_stream_*` and `wireless_send_event`.
