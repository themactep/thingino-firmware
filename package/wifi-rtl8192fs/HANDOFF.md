# RTL8192FS Linux 7.3 port

Status: complete. `8192fs.ko` builds against the 7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

Patches in this package:

- `0002-linux-7.3-build-flags.patch` feed `EXTRA_CFLAGS` into kbuild
- `0003-linux-7.3-timer.patch` use the 7.3 timer helpers
- `0004-linux-7.3-disable-br-ext.patch` and
  `0005-linux-7.3-br-ext-includes.patch` drop the removed IPX/AppleTalk
  headers and the bridge extension
- `0006-linux-7.3-driver-compat.patch` replace the removed string, NAPI,
  kthread, random, crypto and regulatory helpers, and add the 7.3
  cfg80211 wrappers
- `0007-linux-7.3-misc.patch` use `pde_data()` and replace the last
  SDIO debug-path `strncpy` calls
