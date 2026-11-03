# TXW901U Linux 7.3 port

Status: complete. `txw901u.ko` builds and installs against the 7.3.1
kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

Patch `0001-linux-7.3-compat.patch`:

- `IEEE80211_NUM_BANDS` -> `NUM_NL80211_BANDS` and band enum updates
- `linux/unaligned.h`
- 7.3 beacon/timer APIs (`ieee80211_beacon_get`, `timer_container_of`,
  `timer_delete`, `timer_delete_sync`)
- `start_ap`/`stop_ap`/`config`/`set_rts_threshold`/`bss_info_changed`/
  `conf_tx` 7.3 argument wrappers
- drop the removed VFS namespace import
- disable the date-time warnings
