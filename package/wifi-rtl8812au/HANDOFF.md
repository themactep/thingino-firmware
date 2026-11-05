# RTL8812AU Linux 7.3 port

Status: complete. `8812au.ko` builds against the 7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

The driver was bumped to the upstream `v5.2.20` head.

Patches in this package:

- `0001-disable_8814_8821.patch` build the 8812AU-only configuration and
  anchor the phydm include at the module source directory
- `0003-linux-7.3-strncpy.patch` replace the removed `strncpy`
