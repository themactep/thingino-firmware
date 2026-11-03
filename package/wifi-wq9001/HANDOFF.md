# WQ9001 Linux 7.3 port

Status: complete. `wq9001.ko` builds against the 7.3.1 kernel.

Build with the dummy test profile:

```sh
GROUP=test CAMERA=dummy_t31l_sc2336_wifi make cleanbuild
```

Patches in this package:

- `0001` use the kernel `IFF_*` flags on 7.3 and relax
  `missing-prototypes`
- `0002` guard the private `ifreq`/`ifr_*` definitions, convert the
  cfg80211 ops (wdev, `radio_idx`, link IDs, `cfg80211_ap_update`,
  ROC/mgmt-tx cookie), fix the timer/NAPI/`netif_rx`/`in_irq`/
  `access_ok`/pid helpers, `strncpy`/`strlcpy`, and make the crypto
  helper a real symbol
