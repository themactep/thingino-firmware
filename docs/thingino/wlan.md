wlan
====

`wlan` is a command-line utility for managing the Wi-Fi interface on Thingino
devices. It provides commands for configuring credentials, querying connection
status, reading signal strength and temperature, and accessing the low-level
driver CLI on supported modules.

Usage
-----

```
wlan <command> [arguments]
```

Commands
--------

### setup

Launches an interactive wizard to configure Wi-Fi credentials.

```
wlan setup
```

Prompts for an SSID, a password (8–64 characters), and optionally enables
access point (AP) mode. On completion it writes `/etc/wpa_supplicant.conf`
and asks you to reboot for changes to take effect.

### configure

Creates a WPA supplicant configuration file non-interactively.

```
wlan configure <ssid> <password> [ap]
```

- `<ssid>` – Wi-Fi network name.
- `<password>` – Wi-Fi password (8–64 characters).
- `ap` – Optional. When provided, the device is configured as a soft access
  point on channel 1 (2412 MHz) using WPA2-PSK/CCMP.

The configuration is written to `/etc/wpa_supplicant.conf`.

### info

Displays connection details for the `wlan0` interface.

```
wlan info
```

Support varies by driver family:

| Driver family | Output                            |
|---------------|-----------------------------------|
| ATBM          | `iwpriv wlan0 common get_ap_info` |
| MediaTek      | `iwconfig wlan0`                  |
| Realtek       | `iwconfig wlan0`                  |
| Others        | Not supported                     |

### rssi

Displays the current received signal strength indicator (RSSI) in dBm.

```
wlan rssi
```

Support varies by driver family:

| Driver family | Notes                              |
|---------------|------------------------------------|
| ATBM          | Reads via `iwpriv`                 |
| MediaTek      | Reads via `iwconfig`               |
| Realtek       | Reads via `iwconfig`               |
| SSV           | Reads via `/proc/ssv/phy0/ssv_cmd` |
| AICSemi       | Not supported yet                  |
| Broadcom      | Not supported yet                  |
| HiSilicon     | Not supported yet                  |

### temp

Displays the wireless module junction temperature in °C.

```
wlan temp
```

Currently only supported on **ATBM** modules (via `iwpriv wlan0 common get_tjroom`).
All other driver families report "not supported".

### cli

Sends a raw command to the wireless driver CLI interface.

```
wlan cli <command>
```

Supported driver families:

| Driver family | Command file                        |
|---------------|-------------------------------------|
| ATBM          | `/sys/module/atbm*/atbmfs/atbm_cmd` |
| SSV           | `/proc/ssv/phy0/ssv_cmd`            |

Running `wlan cli` without arguments prints usage information.

### reset

Removes all stored Wi-Fi credentials.

```
wlan reset
```

Deletes `/overlay/etc/wpa_supplicant.conf`.

Shortcut commands
-----------------

The following symlinks to `wlan` are available as convenience aliases:

| Alias       | Equivalent to   |
|-------------|-----------------|
| `wlancli`   | `wlan cli`      |
| `wlaninfo`  | `wlan info`     |
| `wlanreset` | `wlan reset`    |
| `wlanrssi`  | `wlan rssi`     |
| `wlansetup` | `wlan setup`    |
| `wlantemp`  | `wlan temp`     |

Supported Wi-Fi driver families
--------------------------------

The script is compiled with one of the following driver families selected at
build time via Buildroot `@if WIFI_FAMILY_*@` preprocessor directives:

| Token           | Vendor / Family |
|-----------------|-----------------|
| `WIFI_FAMILY_AIC`  | AICSemi      |
| `WIFI_FAMILY_ATBM` | AltoBeam     |
| `WIFI_FAMILY_BCM`  | Broadcom     |
| `WIFI_FAMILY_HI`   | HiSilicon    |
| `WIFI_FAMILY_MTK`  | MediaTek     |
| `WIFI_FAMILY_RTL`  | Realtek      |
| `WIFI_FAMILY_SSV`  | SSV          |

Notes
-----

- All commands that operate on the interface first verify that `wlan0` exists.
  If the interface is absent the command exits with an error.
- `wlan setup` and `wlan configure` write directly to `/etc/wpa_supplicant.conf`.
  Use `wlan reset` to remove the configuration and revert to a blank state.
- A device reboot is required after changing Wi-Fi credentials.
