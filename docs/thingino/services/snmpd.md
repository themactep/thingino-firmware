# SNMP Monitoring with thingino-snmpd

Thingino cameras can be monitored via SNMP using the `thingino-snmpd`
package, which bundles [mini-snmpd 2.0](https://github.com/troglobit/mini-snmpd)
— a minimal, read-only SNMP agent purpose-built for embedded systems.

## Overview

| | |
|---|---|
| **Package** | `thingino-snmpd` |
| **Daemon** | `mini-snmpd` 2.0 |
| **Binary size** | ~82 KB (stripped, MIPS) |
| **Runtime deps** | libc only (no libconfuse) |
| **Total on-flash** | ~50 KB (squashfs) |
| **SNMP versions** | v1 and v2c, read-only |
| **Default** | Disabled (`enabled: false`) |

### What gets exposed

mini-snmpd 2.0 serves **221 OIDs** across these MIB modules:

| MIB module | What you get |
|---|---|
| SNMPv2-MIB | sysDescr, sysUpTime, sysName, sysORTable, snmpInPkts, snmp counters |
| IF-MIB | ifTable, ifXTable (64-bit counters) for lo + wlan0 |
| IP-MIB | ipAddressTable (IPv4 + IPv6) |
| HOST-RESOURCES-MIB | hrMemorySize, hrSystemProcesses, hrStorageTable, hrProcessorTable |
| UCD-SNMP-MIB | memTotalReal, memAvailReal, memBuffer, memCached, dskTable, laTable (1/5/15 min load), ssCpuUser/System/Idle |

> **Note:** LM-SENSORS-MIB temperature sensors are supported by the daemon
> but require `/sys/class/hwmon` — not available on 3.10.14 Ingenic kernels.

## Quick start

### 1. Enable the package

Add to your `local.fragment`:

```
BR2_PACKAGE_THINGINO_SNMPD=y
```

Rebuild and flash.

### 2. Configure the agent

Open the camera's Web UI, navigate to **Services → SNMP**, and set:

| Field | Recommended |
|---|---|
| Community | Something other than `public` |
| Auth | On (require the community string) |
| Enable SNMP daemon | On |
| Location | e.g. `Front door` |
| Contact | e.g. `ops@example.com` |

Click **Save changes**. The daemon starts immediately.

### 3. Test it

```bash
# From any host on the same network:
snmpwalk -v2c -c yourcommunity 192.168.88.127
```

Or use the included test script:

```bash
scripts/test-snmpd.sh 192.168.88.127 yourcommunity
```

## Architecture

### Configuration flow

```
┌────────────────────┐    ┌──────────────┐    ┌─────────────────┐
│ /etc/thingino.json │───▶│ S60snmpd     │───▶│ mini-snmpd      │→ UDP :161
│ snmpd.*            │    │ init script  │    │ command line    │→ TCP :161
└────────────────────┘    └──────────────┘    └─────────────────┘
```

The init script (`S60snmpd`) reads the `snmpd` section from
`/etc/thingino.json`, filters out non-existent mount points from the disk
list, and assembles the entire configuration into command-line arguments.
This way:

- **No config file parsing** in the daemon — everything is passed via `argv`.
- **Spaces in values** (location, contact, description) work because the
  script uses `set --` to build the argument list, then passes it to
  `start-stop-daemon` unmangled.
- **libconfuse is not needed** — the package builds with `--without-config`,
  saving ~60–80 KB that libconfuse would otherwise cost.

### Why not Buildroot's mini-snmpd?

Buildroot ships `mini-snmpd` 1.6. Using it directly (or overriding it)
would mean:

- v1.6 lacks dual-stack IPv4/IPv6, SNMPv2c traps, netlink-based interface
  tracking, hwmon temperature sensors, SIGHUP reload, and the extended
  HOST-RESOURCES-MIB tables.
- The 1.6 package depends on libconfuse, adding a new library to the image.
- No Thingino integration layer (thingino.json, WebUI plugin, init script,
  bundle support).

The `thingino-snmpd` wrapper follows the same pattern as other Thingino
service packages (`thingino-mosquitto-20x`, `thingino-vpn`, etc.) — a thin
integration layer around an upstream daemon.

## Configuration reference

All settings live in `/etc/thingino.json` under the `snmpd` key.

### Default values

```json
{
  "snmpd": {
    "enabled": false,
    "auth": true,
    "community": "public",
    "port": 161,
    "listen": "",
    "location": "",
    "contact": "",
    "description": "",
    "disks": "/,/overlay",
    "interfaces": "",
    "timeout": 1,
    "loglevel": "notice",
    "traps": ""
  }
}
```

### Fields

| Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Master switch. When `false`, the init script refuses to start. |
| `auth` | bool | `true` | When `true`, requests must carry a matching community string. When `false`, any community is accepted (including empty). |
| `community` | string | `"public"` | Community string for read-only access. Sent in clear text; do not reuse a password. |
| `port` | integer | `161` | UDP and TCP port the agent listens on. |
| `listen` | string | `""` | Bind to a single interface, e.g. `eth0`. Empty means all interfaces. |
| `location` | string | `""` | sysLocation value (SNMPv2-MIB). May contain spaces. |
| `contact` | string | `""` | sysContact value. May contain spaces. |
| `description` | string | `""` | sysDescr value. When empty, falls back to `PRETTY_NAME` from `/etc/os-release`. |
| `disks` | string | `"/,/overlay"` | Comma-separated mount points for the dskTable and hrStorageTable. Missing directories are silently skipped at start-up. |
| `interfaces` | string | `""` | Comma-separated interface names (max 8). Empty means all interfaces. Supports wildcards: `eth+` matches eth0, eth1, etc.; `+` matches everything. |
| `timeout` | integer | `1` | Seconds between MIB counter cache refreshes. |
| `loglevel` | string | `"notice"` | One of: `none`, `err`, `notice`, `info`, `debug`. Messages go to syslog. |
| `traps` | string | `""` | Comma-separated trap sinks in `addr[:port]` format, e.g. `192.168.1.10, 192.168.1.11:1620`. Default port is 162. |

### Manual configuration via command line

You can also configure the daemon directly via `jct`:

```bash
# Enable and set the community string
jct /etc/thingino.json set snmpd.enabled true
jct /etc/thingino.json set snmpd.community '"mysecret"'

# Set location and contact
jct /etc/thingino.json set snmpd.location '"Server Room, Rack 3"'
jct /etc/thingino.json set snmpd.contact '"noc@example.com"'

# Apply: restart the daemon from the new settings
/etc/init.d/S60snmpd restart
```

> **Note:** String values must be JSON-quoted when set via `jct` — use
> single quotes around double quotes: `'"value"'`.

## Usage examples

All examples assume the camera is at `192.168.88.127` with community
`public`. Replace with your actual values.

### System identity

```bash
$ snmpget -v2c -c public 192.168.88.127 SNMPv2-MIB::sysDescr.0
SNMPv2-MIB::sysDescr.0 = STRING: "Thingino 1 (Ciao)"

$ snmpget -v2c -c public 192.168.88.127 SNMPv2-MIB::sysUpTime.0
SNMPv2-MIB::sysUpTime.0 = Timeticks: (123456) 0:20:34.56

$ snmpget -v2c -c public 192.168.88.127 SNMPv2-MIB::sysName.0
SNMPv2-MIB::sysName.0 = STRING: "ing-wyze-cam3-2937"
```

### Interface statistics

```bash
# List all interfaces
$ snmpwalk -v2c -c public 192.168.88.127 IF-MIB::ifDescr
IF-MIB::ifDescr.1 = STRING: "lo"
IF-MIB::ifDescr.2 = STRING: "wlan0"

# 64-bit octet counters (IF-MIB::ifHCInOctets)
$ snmpget -v2c -c public 192.168.88.127 \
    IF-MIB::ifHCInOctets.2 IF-MIB::ifHCOutOctets.2
IF-MIB::ifHCInOctets.2 = Counter64: 117607953
IF-MIB::ifHCOutOctets.2 = Counter64: 565613569

# Human-readable: wlan0 has received ~112 MB, sent ~539 MB
```

### Memory

```bash
$ snmpwalk -v2c -c public 192.168.88.127 UCD-SNMP-MIB::memory
UCD-SNMP-MIB::memTotalReal.0 = INTEGER: 95296    # ~93 MB total
UCD-SNMP-MIB::memAvailReal.0 = INTEGER: 52176    # ~51 MB available
UCD-SNMP-MIB::memBuffer.0 = INTEGER: 5420        # ~5 MB buffers
UCD-SNMP-MIB::memCached.0 = INTEGER: 17548       # ~17 MB cache
```

### Disk usage

```bash
$ snmpwalk -v2c -c public 192.168.88.127 UCD-SNMP-MIB::dskTable
UCD-SNMP-MIB::dskPath.1 = STRING: "/"
UCD-SNMP-MIB::dskPath.2 = STRING: "/overlay"
UCD-SNMP-MIB::dskTotal.1 = INTEGER: 8768     # 8.5 MB
UCD-SNMP-MIB::dskTotal.2 = INTEGER: 8768
UCD-SNMP-MIB::dskUsed.1 = INTEGER: 324       # 324 KB used
UCD-SNMP-MIB::dskUsed.2 = INTEGER: 324
UCD-SNMP-MIB::dskPercent.1 = INTEGER: 4      # 4%
UCD-SNMP-MIB::dskPercent.2 = INTEGER: 4
```

### CPU load

```bash
$ snmpwalk -v2c -c public 192.168.88.127 UCD-SNMP-MIB::laTable
UCD-SNMP-MIB::laLoad.1 = STRING: "2.54"   # 1-minute
UCD-SNMP-MIB::laLoad.2 = STRING: "2.69"   # 5-minute
UCD-SNMP-MIB::laLoad.3 = STRING: "2.50"   # 15-minute
```

### Full walk

```bash
# Dump every OID the camera supports
$ snmpwalk -v2c -c public 192.168.88.127 .1 | wc -l
221

# Save for offline analysis
$ snmpwalk -v2c -c public 192.168.88.127 .1 > camera-snmp-dump.txt
```

## Integration with monitoring systems

### LibreNMS

Add the camera as a generic SNMP device in LibreNMS:

```bash
# From your LibreNMS server:
./addhost.php 192.168.88.127 public v2c
./discovery.php -h 192.168.88.127
./poller.php -h 192.168.88.127
```

The camera will appear with system info, interface graphs (wlan0 traffic),
memory/CPU graphs, and disk usage. No custom MIB files are needed — the
agent uses standard IETF and UCD MIBs that LibreNMS already understands.

### Zabbix

Create a host in Zabbix with an SNMP interface. Use the default
`Template Module Generic SNMPv2` template, or create a custom template
targeting the key OIDs:

| Item | OID |
|---|---|
| System description | `.1.3.6.1.2.1.1.1.0` |
| Uptime | `.1.3.6.1.2.1.1.3.0` |
| Total memory | `.1.3.6.1.4.1.2021.4.5.0` |
| Available memory | `.1.3.6.1.4.1.2021.4.6.0` |
| CPU load (1 min) | `.1.3.6.1.4.1.2021.10.1.5.1` |
| wlan0 inbound octets | `.1.3.6.1.2.1.31.1.1.1.6.2` |
| wlan0 outbound octets | `.1.3.6.1.2.1.31.1.1.1.10.2` |

### Prometheus (via snmp_exporter)

Generate an `snmp.yml` for snmp_exporter:

```yaml
modules:
  thingino_camera:
    walk:
      - 1.3.6.1.2.1.1          # system
      - 1.3.6.1.2.1.2          # interfaces
      - 1.3.6.1.2.1.4.34       # ipAddressTable
      - 1.3.6.1.2.1.25.2       # hrStorage
      - 1.3.6.1.4.1.2021.4     # memory
      - 1.3.6.1.4.1.2021.9     # disks
      - 1.3.6.1.4.1.2021.10    # load
      - 1.3.6.1.4.1.2021.11    # CPU stats
```

### check_mk / Nagios

```bash
# Simple uptime check
/usr/lib/nagios/plugins/check_snmp \
    -H 192.168.88.127 -C public -o .1.3.6.1.2.1.1.3.0 \
    -w 600 -c 300

# Memory usage check
/usr/lib/nagios/plugins/check_snmp \
    -H 192.168.88.127 -C public \
    -o .1.3.6.1.4.1.2021.4.6.0,.1.3.6.1.4.1.2021.4.5.0 \
    -l "Available memory" -u "KB" \
    -w 10000: -c 5000:
```

## Bundle distribution

The package can be distributed as a `.tgz` bundle for installation on
existing cameras without a full rebuild:

```bash
# On the build host, create the bundle
make thingino-snmpd-bundle

# Copy to the camera
scp -O output/*/bundle/thingino-snmpd-*.tgz root@192.168.88.127:/tmp/

# On the camera, install
thingino-pkg install /tmp/thingino-snmpd-*.tgz
```

The bundle includes the binary, init script, default configuration, and
WebUI plugin files.

## Paranoid mode (offline assets)

When `BR2_PACKAGE_THINGINO_WEBUI_PARANOID=y` is set, the SNMP configuration
page works fully offline — Bootstrap CSS/JS and Bootstrap Icons are served
from local `/a/vendor/` files instead of jsDelivr CDN. The conversion
happens automatically at build time; no changes are needed in the SNMP
package.

## Troubleshooting

### Daemon won't start

Check the config:

```bash
jct /etc/thingino.json get snmpd
```

The `enabled` field must be `true`. If it's `false`, the init script
exits with "SNMP daemon is disabled."

### SNMP queries time out

```bash
# Is the daemon running?
pidof mini-snmpd

# Is it listening?
netstat -tulnp | grep 161

# Check syslog for errors
logread | grep snmpd

# Test locally on the camera
snmpwalk -v2c -c public 127.0.0.1
```

### Disks not showing up

The init script filters out mount points that don't exist on the camera's
filesystem. If you add `/mnt/nfs` to the disk list but the NFS share isn't
mounted at boot, it's silently skipped. Check with:

```bash
grep disks /etc/thingino.json
# Verify each path exists:
ls -d / /overlay /mnt/nfs
```

### Temperature sensors missing

LM-SENSORS-MIB requires `/sys/class/hwmon`. On Ingenic T31/T23/T21
cameras running kernel 3.10.14, this directory doesn't exist — no
temperature OIDs will be served. This is a kernel limitation, not a
mini-snmpd bug.

### Wrong interface counters

The default configuration monitors all interfaces. If you see unexpected
interfaces in the table, restrict them:

```bash
jct /etc/thingino.json set snmpd.interfaces '"eth0,wlan0"'
/etc/init.d/S60snmpd restart
```

## Testing

The repo includes a comprehensive test script at `scripts/test-snmpd.sh`:

```bash
# Default: test 192.168.88.127 with community "public"
./scripts/test-snmpd.sh

# Custom host and community
./scripts/test-snmpd.sh 10.0.0.5 mycommunity
```

It validates every MIB group the agent should expose and reports
pass/fail for each. A successful run shows "ALL GOOD" with 24/24
checks passing.

## Security considerations

- **SNMP v1/v2c sends the community string in clear text.** Anyone on the
  same network segment can capture it. Treat the community string like a
  password unique to the camera.
- **Read-only access only.** mini-snmpd does not support SNMP SET
  operations; the agent cannot be used to modify the camera's
  configuration.
- **No SNMPv3.** Encryption and authentication are out of scope for
  mini-snmpd upstream. If you need SNMPv3, consider a full net-snmp
  deployment (at a significantly larger footprint).
- **Bind to a specific interface** with `listen: "eth0"` if the camera
  has multiple network paths and you want to restrict SNMP exposure.

## See also

- [mini-snmpd homepage](https://troglobit.com/projects/mini-snmpd/)
- [mini-snmpd v2.0 release notes](https://github.com/troglobit/mini-snmpd/releases/tag/v2.0)
- [MIBS.md](https://github.com/troglobit/mini-snmpd/blob/v2.0/MIBS.md) —
  full list of supported OIDs
- [Plugin System](plugin-system.md) — how the WebUI plugin infrastructure works
- `scripts/test-snmpd.sh` — automated test script
