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
