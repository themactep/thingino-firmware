# RTL8733BU Linux 7.3 port

Status: complete. `8733bu.ko` builds against the 7.3.1 kernel.

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
- `0006` cfg80211 ops (`wireless_dev`, `radio_idx`, ROC/mgmt-tx
  cookie ABI), `PDE_DATA`, regulatory flag, `strncpy`/`strlcpy`,
  NAPI, USB driver embedding, kthread completion and randomness
