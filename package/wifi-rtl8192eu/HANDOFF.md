# RTL8192EU Linux 7.3 port

Status: complete. `8192eu.ko` builds against the 7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

The driver was bumped to the upstream `realtek-4.4.x` head, which already
carries the Linux 7.x cfg80211, strncpy and notification fixes. No local
compatibility patch is needed.
