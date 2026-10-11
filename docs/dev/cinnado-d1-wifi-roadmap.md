# Cinnado D1 (T31L) - WiFi driver conversion roadmap (atbm6031 on mainline)

Goal: the ATBM6031 SDIO WiFi (the camera's only radio) working on the mainline
7.x kernel tree, to production quality - i.e. buildable from the repo, no
out-of-tree overrides, stable association, sane power management, and
firmware/regdb loading through the normal paths.

This document scopes that conversion and the decision points around it.

## Where we are

- Kernel boots on mainline 7.x, rootfs mounts, userspace runs (see the handoff).
- The MSC1/SDIO bus is wired and probes (`jz4740-mmc 13460000.mmc`), but the
  card does not finish init yet (`no support for card's volts` ->
  `error -22` -> `Card stuck being busy`). That is independent of the driver
  and is workstream W0 below.
- The vendor driver (`gtxaspec/atbm-wifi`, used via the gitignored override)
  does not build on 7.x. Two mechanical blockers are already fixed locally
  (`hal_apollo/Makefile` `k-dir`, `asm/unaligned.h`); the real wall is the
  cfg80211/mac80211 API delta.

## What the vendor driver actually is

- A vendor SDK, not a mac80211 driver: it **ships its own full mac80211 fork**
  (`hal_apollo/mac80211/`, 56 files) linked into `<chip>.ko`, on top of the
  kernel's cfg80211. It defines its own `ieee80211_alloc_hw` / `ieee80211_register_hw`
  and renames the vendor bits `atbm_*`.
- The driver core is `hal_apollo/*.c` - 37 files, ~1.5 MB (`apollo_usb.c`,
  `module_fs.c`, `sta.c`, `wsm.c`, `txrx.c`, `bh_sdio.c`, ...). It includes
  `<net/atbm_mac80211.h>` (the fork header) and calls **184 distinct
  `ieee80211_*` symbols**, many vendor-only
  (`ieee80211_atbm_*`, `ieee80211_ble_*`, `ieee80211_ap_update_special_*`) plus
  old-mac80211 helpers removed upstream (`ieee80211_driver_hang_notify`,
  `ieee80211_cqm_tx_fail_notify`).
- The fork targets the ~4.4/5.x cfg80211 ABI. 7.x moved to the `wireless_dev`
  model (`netdev->ieee80211_ptr` is gone), added `link_id` to most
  `cfg80211_ops`, changed `struct station_parameters`, `cfg80211_rx_assoc_resp`
  arity, `cfg80211_assoc_timeout` removal, `cfg80211_disassoc_request`, etc.

## Prior art (searched) - none usable

- No mainline ATBM/Altobeam driver exists (`wireless.docs.kernel.org` driver
  list has none; ATBM is absent from `drivers/net/wireless`).
- `gtxaspec/atbm60xx` is **archived** (2024-07) and points at
  `gtxaspec/atbm-wifi` - the repo we already use. `atbm-wifi` is the vendor SDK,
  no newer-kernel branch (it still references 3.10/4.4/4.9 targets).
- Altobeam's own site distributes the SDK only; no public newer-kernel port.

Conclusion: there is no drop-in to borrow; this is a real port. The only way to
shorten it is to get a newer vendor SDK (see Option C).

## Options

**A. Port the vendor fork to the target kernel.**
Keeps every vendor feature (BLE, special filters, WPS, etc.). Requires
porting 56 files of mac80211 internals across ~a decade of churn - the largest
option, and the internals are the least stable API in the kernel.
_Trade-off_: high effort, high fragility, but no feature loss.

**B. Rebase the core onto in-tree mac80211/cfg80211.**
Drop the fork; compile the 37-file core against the kernel's `mac80211.h` and
replace vendor-only calls with stock equivalents or drop those features.
_Removes_ the 56-file mac80211 fork from the problem, but the core is the bulk
of the code and is coupled to the fork's extended API, and mac80211 only exports
the driver-facing API. Likely smaller than A, still large.

**C. Get a newer vendor SDK from Altobeam.**
If Altobeam ships a 5.10/6.x SDK for the 6031 (or the `6031-X` variant), the
port collapses to a backport of the few remaining deltas. Requires vendor
contact / NDA; the pay-off is large. Worth one email before committing to A/B.

**D. Change the radio / keep a vendor kernel for WiFi.**
Rebase the product on a module with upstream support, or keep WiFi on a vendor
kernel and mainline for everything else. Not a "mainline WiFi" answer, but a
legitimate production fallback.

## Recommended direction

1. Do **W0** (SDIO bus) now - it is orthogonal and needs the driver to test, but
   the failure modes are diagnosable without it.
2. Send the **Option C** inquiry to Altobeam in parallel; treat any reply as a
   bonus, not a dependency.
3. Proceed with a **staged A->B hybrid**: do the cfg80211 migration first (it is
   shared by A and B and is the gate that gets code compiling), then decide
   fork-port vs. stock-mac80211 based on how much of the fork's mac80211 turns
   out to be reachable through the stock API.
4. Pin the kernel to a released **LTS** (6.12 or 6.6) for the production branch
   rather than a `-rc`; the cfg80211/mac80211 ABI is far more stable across an
   LTS lifetime and staging fixes land there first. Keep `mainline-7x` for
   bring-up only.

## Phased plan

### W0 - SDIO bus bring-up (no driver needed)
- Decide WLAN power/clock ownership: userspace (GPIO 47 + `mmc-pwrseq`-style
  reset + rescan) vs. kernel (`mmc-pwrseq-simple` node, or teach `jz4740_mmc`
  the vendor `ingenic,sdio_clk`/LPM bit).
- Fix `no support for card's volts` (host `ocr_avail` vs. card OCR) and
  `Card stuck being busy` (bus-width/clock/timing; try 1-bit first, then 4-bit
  with `max-frequency` lowered).
- Exit: `mmc1` enumerates the SDIO card (CMD5 returns a CID and the
  function/vendor/device IDs are visible in `/sys/bus/sdio/devices`).

### W1 - Reproducible out-of-tree build
- Persist the `k-dir` + `unaligned` fixes as `package/wifi-atbm6031/0002-*.patch`
  (overrides bypass patches, so keep the override in sync).
- Pin `WIFI_ATBM6031_VERSION` to a tested commit; document the toolchain.
- Exit: `make rebuild-wifi-atbm6031` compiles to the point of the API errors
  reproducibly.

### W2 - cfg80211 API migration (shared by Options A and B)
Drive from the compiler, file by file, against a stock 7.x reference:
- `netdev->ieee80211_ptr`: switch to `wireless_dev`/`wdev->netdev` and the
  `container_of`/`wiphy_to_ieee80211_hw` idiom.
- `cfg80211_ops`: add the `int link_id` parameter and change
  `struct net_device *` -> `struct wireless_dev *` across `set_key`,
  `add_key`, `get_key`, `change_station`, `del_station`, `get_station`,
  `set_monitor_channel`, `sched_scan_stop`, `update_ap`/`cfg80211_ap_update`, ...
- `struct station_parameters`: `supported_rates[+len]`, `ht_capa` -> the
  `link_sta_params`/`sta_params` layout of the target kernel.
- `cfg80211_rx_assoc_resp` two-arg form; `cfg80211_assoc_timeout` removal;
  `cfg80211_disassoc_request` rework.
- `ieee80211_amsdu_to_8023s` extra argument.
- Exit: the cfg80211-facing translation unit set compiles.

### W3 - mac80211 layer (A) or core-vs-stock (B)
- If A: bring the 56-file fork up to the target `ieee80211_hw`/`ieee80211_ops`
  and internal APIs (RCU, TX/RX, `ieee80211_local`, chanctx, rate control).
- If B: retarget the 37-file core to `<net/mac80211.h>`; map/remove
  `atbm_*`/`ble_*`/`special_*` calls; stub unsupported features behind config.
- Decision gate after W2: count what the core needs that stock mac80211 does not
  export; if small enough, B; else A.
- Exit: `atbm6031.ko` links and loads; `iw dev` shows `wlan0`.

### W4 - SDIO data path and firmware
- Wire the driver to the now-working SDIO bus; verify firmware load via
  `request_firmware` (`atbm6031_fw.bin` under `/lib/firmware`), regdb load, and
  a stable scan/associate on 2.4 GHz.
- Exit: associates to an AP, DHCP, sustained ping; throughput number recorded.

### W5 - Userspace and productization
- Fix `/etc/init.d/S36wireless` (currently a shell syntax error on 7.x) and the
  wifi config/regdb/power handling; ensure the module autoloads and the
  interface survives reboot.
- Power management: verify SDIO autosuspend/`ingenic,sdio_clk` behaviour so the
  radio isn't dropped on idle.
- Exit: fresh flash brings WiFi up unattended to a working `wlan0`.

### W6 - Hardening / upstream (optional)
- Stress (RTSP over WiFi), suspend/resume, regulatory, and consider whether any
  portion is upstreamable. A mainline ATBM driver is unlikely (vendor NDA) - do
  not plan on it.

## Risks

- mac80211 internals (Option A) change every release; a fork port becomes a
  maintenance treadmill. This is the main argument for Option B or C.
- The vendor's extensions (BLE, special filters) may be load-bearing for the
  product; removing them (B) is a product decision, not just an engineering one.
- SDIO timing on T31 may need vendor-style clock/LPM handling that mainline
  `jz4740_mmc` does not implement - budget for a small mmc driver patch.
- `7.1-rc1` is a moving target; pin an LTS before investing.

## Immediate next actions

1. W0: retry the SDIO init with the WLAN powered (GPIO 47) and the bus forced
   1-bit, then 4-bit at reduced clock; capture CMD5/OCR.
2. W1: fold the `k-dir`/`unaligned` fixes into a package patch and pin the
   driver commit.
3. Send the Altobeam SDK inquiry (Option C).
4. Pick the target LTS for the production branch.
