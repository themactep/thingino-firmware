# wifi-swt6621s

Seekwave SWT6621S (a.k.a. SV6621S / SV6160LITE, USB ID 3607:6621) WiFi driver
for Thingino. Vendor drop, version H25.34.7.1_F25.34.6.1, GPL-2.0.

Driver source: https://github.com/WLTB-Gino/swt6621s (pinned by commit in
`wifi-swt6621s.mk` — the firmware tree carries no driver source). Integrated
for the Jooan W3-U 2026 hardware revision
(`jooan_w3u_t23n_sc2336p_eth+sv6621`).

## Architecture

The driver repo builds TWO kernel modules from one kbuild tree:

| Module | Kconfig | Role |
|---|---|---|
| `skw_usb_lite` | `SKW_USB` (BSP) | USB glue: claims the device, reads chipid, bootstraps the chip boot ROM, downloads firmware (IRAM/DRAM/NV) via request_firmware, power/wake GPIO handling, crash dump |
| `swt6621s_wifi` | `WLAN_VENDOR_SWT6621S` | cfg80211 full-MAC core (`sv6621s_wireless1` platform driver) |

Data flow: USB probe (BSP) -> boot ROM handshake -> firmware download ->
BSP registers `sv6621s_wireless1` platform device -> wifi core binds ->
wlan0.

Load-order note: the two modules share no symbols, so depmod cannot order
them. The driver repo integrates a one-line fix (BSP calls
`request_module("swt6621s_wifi")` right before adding the wifi platform
device, commit `cf2ecc7`), so whichever module is probed first, the pdev
binds. `SWT6621S_MODULE_NAME = skw_usb_lite` — S36wireless probes the BSP.

## Build wiring

- Sources build at the git checkout root: the repo root Makefile defines
  and exports `skw_extra_flags` (BSP config, include path) and
  `skw_extra_symbols` (Module.symvers consumed by the core via
  `KBUILD_EXTRA_SYMBOLS`), then fans out via `obj-m += drivers/`.
  `MODULE_SUBDIRS` is left at the default (`.`).
- Kernel requirements (enforced by the package's `LINUX_CONFIG_FIXUPS`):
  `CONFIG_WLAN`, `CONFIG_WIRELESS`, `CONFIG_CFG80211` =y. This is a
  softmac cfg80211 driver — without the wireless core built in, the
  module fails modpost with ~48 undefined wiphy/cfg80211 symbols and
  cannot insmod. `MAC80211` stays off (no ieee80211_alloc_hw-class
  symbols needed) and WEXT stays off (wpa_supplicant uses nl80211).
  `CONFIG_SWT6621S_DFS_MASTER` must stay off on 3.10 — see the comment
  in `wifi-swt6621s.mk`.
- No package patches: the load-order fix is integrated in the driver repo.
- USB-only integration (`SKW_USB=m`, `SKW_SDIOHAL` off) — the driver's
  initial-SDIO-enumeration gap does not apply.
- firmware: `SWT6621S_IRAM_USB.bin` + `SWT6621S_DRAM_USB.bin` ship in the
  driver repo's `firmware/USB-Firmware/`; the NV image ships as
  `NVBIN/NV_Related_to_customer_HW/SWT6621S_NV_USB_SHARE.bin` and is
  installed renamed to `SWT6621S_NV_USB.bin` (the name skw_boot.c
  requests). RFBIN factory-calibration files are not requested at runtime.

## Files

- `Config.in` / `wifi-swt6621s.mk` - Buildroot package (git site)
- Registered in `package/wifi/Config.in` (sourced) and `package/wifi/wifi.mk`
  (`WIFI_ADD_DRIVER ... skw_usb_lite usb`)

## Known limitations

- Compile-verified: a full `CAMERA=jooan_w3u_t23n_sc2336p_eth+sv6621 make`
  firmware build succeeds against 3.10.14; `swt6621s_wifi.ko` + firmware
  blobs land in the rootfs. On-hardware validation still pending.
- 3.10.14 compatibility is carried by version guards in the driver repo
  (targets 3.1-6.4 with compat shims; vendor's lowest supported kernel
  was 3.11, so 3.10 support is ours, not the vendor's).
- BT side (swtbt4l, `CONFIG_BT_SEEKWAVE`) not built - cameras do not need
  it; the BSP Makefile adds `-DCONFIG_BT_SEEKWAVE` ccflags only when
  Android binder is detected, which does not happen here.
- genver.pl (perl, host) generates version.h with a hardcoded version -
  no git dependency.
