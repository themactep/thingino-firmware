# Wi-Fi FAQ

## Why does wpa_supplicant log "nl80211 driver interface is not designed to be used with ap_scan=2" when the portal starts?

The line appears right after `Successfully initialized wpa_supplicant` on
every portal or AP-mode boot. It is expected and harmless for an access point.

### What ap_scan does

`ap_scan` decides who drives scanning and network selection:

- `ap_scan=1` — wpa_supplicant scans, picks a BSS and drives association.
  This is the correct mode for station connections on nl80211.
- `ap_scan=2` — the driver handles scanning and connection, and for AP/IBSS
  mode the network is created immediately without a scan. From the
  wpa_supplicant.conf documentation:

  > When using IBSS or AP mode, ap_scan=2 mode can force the new network to
  > be created immediately regardless of scan results. ap_scan=1 mode will
  > first try to scan for existing networks and only if no matches with the
  > enabled networks are found, a new IBSS or AP mode network is created.

### Why the note is printed

`wpa_supplicant_set_ap_scan()` prints the note whenever `ap_scan=2` is used
with the nl80211 driver, with no regard for the interface mode. The concern is
station mode: with ap_scan=2 and nl80211 the driver's scan/connect path is
incomplete and connections can fail. For AP mode the warning is noise, because
`ap_scan` only governs the station path — AP bring-up (SET_AP/beacon) does not
use it.

### Why thingino uses ap_scan=2 for the portal

The portal and AP-mode configs (`prepare_portal()` in S38wpa_supplicant, the
installed default wpa_supplicant.conf, and `wlan configure -a`) set
`ap_scan=2` on purpose: the AP comes up immediately at boot instead of
wasting a scan round-trip (which a flaky-scan radio could stall on).

Client mode is unaffected: `wlan configure` writes `ap_scan=1` for station
connections, which is the setting the nl80211 driver expects.

So: leave the note alone. It only matters if someone puts `ap_scan=2` into a
station-mode config.

## How does the portal fall back to a preset network?

A camera normally enters portal mode when `/etc/wpa_supplicant.conf` has no
`psk=`. If the image (or the writable overlay) also ships a preset client
config at `/etc/wpa_supplicant.preset.conf`, the portal is still attempted
first. When the portal AP fails to come up, or the 600 s idle timeout expires
with nobody having configured the camera, `S38wpa_supplicant`:

1. Tears the portal AP down.
2. Copies the preset over `/etc/wpa_supplicant.conf` and marks it.
3. Re-enters the normal boot path, bringing the station up on the preset
   network.

The fallback is a one-boot rescue, not a new configuration: `S38wpa_supplicant`
removes the copy (and its marker) on shutdown, and again at the top of the next
boot in case the camera was power-cycled, so the portal is retried on every
boot. `wlan configure` clears the marker, so a network configured deliberately
survives reboots; `wlan reset` removes `/overlay/etc/wpa_supplicant.conf` and
returns the camera to portal mode.

The preset must contain both `ssid=` and `psk=`, and (as with any station
config) `ap_scan=1`. The file carries the network key: keep it in the
gitignored user overlay or drop it onto the writable overlay at runtime, never
in the repository. Without a preset file the behavior is unchanged: the portal
stays up, and the timeout stops it as before.
