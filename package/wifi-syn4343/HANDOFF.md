# SYN4343 / bcmdhd Linux 7.3 port

Status: complete. `bcmdhd.ko` builds against the 7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

Patches in this package:

- `0001` feed `DHDCFLAGS` into kbuild and anchor includes at `PWD`
- `0002` drop `net/lib80211.h`
- `0003` use `linux/unaligned.h` / `linux/pci.h` and `ioremap`
- `0004` timer, random, `kernel_read`/`kernel_write`, DMA, PCI,
  `strlcpy` and first notification call sites
- `0005` cfg80211 7.3 wrappers for virtual interfaces, tx power,
  station/key/AP/beacon/mgmt-tx/TDLS/ROC ops, plus time, scan-done,
  station-info, new/del-sta, disconnected, band, p2p/btcoex timer,
  SDIO reset and scheduler fixes
