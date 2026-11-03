# HI3881 Linux 7.3 port

Status: complete. `hi3881.ko` builds against the 7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

Patches in this package:

- `0001-linux-7.3-build-flags` feed the driver flags into kbuild
- `0001_wifi_cfg_path` keep the installed Wi-Fi config path
- `0002-linux-7.3-oal` use the real kernel version, port the OAL/WAL
  timer/time/type interfaces, cfg80211 station/AP/bitrate/key ops,
  SDIO card-detect stub, securec/stdarg, WEXT private-handler guards,
  the scheduler helper and the removed `sched_setscheduler` usage
