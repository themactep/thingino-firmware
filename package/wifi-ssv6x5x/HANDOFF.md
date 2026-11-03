# SSV6X5X Linux 7.3 port

Status: complete. `ssv6x5x.ko` builds against the 7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

Patches in this package:

- `0001` anchor `KBUILD_TOP` at `M` and feed `EXTRA_CFLAGS` into kbuild
- `0002` first mac80211 7.3 signatures and association state
- `0003` station/link-station fields, bss config, tx status, platform
  remove, NAPI, USB embedding, module params, PDE_DATA,
  `beacon_get_tim`, efuse and NS imports
- `0004` common 7.3 compatibility header (`ssv_strncpy`,
  `MODULE_SUPPORTED_DEVICE`)

The package `POST_PATCH_HOOKS` include the compatibility header in the
files that need it.
