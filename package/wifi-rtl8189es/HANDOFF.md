# RTL8189ES Linux 7.3 port

Status: complete. `8189es.ko` builds against the 7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

Patches in this package:

- `0001` disable roaming
- `0002` feed `EXTRA_CFLAGS` into kbuild / `PWD` includes
- `0003` include `linux/timer.h`
- `0004` 7.3 timer names
- `0005` disable `CONFIG_BR_EXT`
- `0006` cfg80211 key/station ops (`wireless_dev`, `radio_idx`,
  ROC/mgmt-tx cookie ABI) and the removed `strncpy`
