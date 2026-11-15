Time
====

Timezone
--------

Timezone data is based on files from OpenWrt project:
[zoneinfo.uc](https://github.com/openwrt/luci/blob/master/modules/luci-base/ucode/zoneinfo.uc) and
[tzdata.lua](https://github.com/openwrt/luci/blob/master/modules/luci-lua-runtime/luasrc/sys/zoneinfo/tzdata.lua).

`/usr/share/tz.json` is read-only. `/etc/tz.user.json` is a partial
`{"Name": "POSIX TZ"}` map layered over it; an entry wins over the shipped
table. The WebUI "Custom time zones" form writes it through
`json-config-time.cgi`, and `tz-validate` checks values against uClibc-ng's
parser. The file is included in `cfg-backup.list`, so it survives upgrades
while the base table can be replaced by firmware.

### IANA Time Zone Database

- [GitHub Repository](https://github.com/eggert/tz)
- [Complete Distribution](https://data.iana.org/time-zones/releases/tzdb-2025b.tar.lz)
- [Data Only Distribution](https://data.iana.org/time-zones/releases/tzdata2025b.tar.gz)
- [Code Only Distribution](https://data.iana.org/time-zones/releases/tzcode2025b.tar.gz)

- [NODA Time Zone Database](https://nodatime.org/TimeZones)
- [NODA TZDB in JSON](https://nodatime.org/TimeZones?version=2025b&format=json)
