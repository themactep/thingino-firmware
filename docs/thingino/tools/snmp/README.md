# Thingino SNMP Monitor

A lightweight bash script for monitoring multiple Thingino cameras from a
single Linux host. Works with the SNMP agent provided by `thingino-snmpd`
(see [docs/thingino/services/snmpd.md](../../services/snmpd.md)).

## Requirements

- **Host**: Any Linux machine with `snmpget` and `snmpwalk`
  (`apt install snmp` / `apk add net-snmp-tools`)
- **Cameras**: Thingino firmware with `thingino-snmpd` enabled

Optional for discovery mode: `arp-scan` or `nmap`.

## Quick start

```bash
# 1. Install dependencies
sudo apt install snmp

# 2. Add a camera
./thingino-snmp-monitor.sh add front-door 192.168.1.100 mycommunity

# 3. See status
./thingino-snmp-monitor.sh status

# 4. Live dashboard (Ctrl+C to exit)
./thingino-snmp-monitor.sh watch
```

## Commands

| Command | Description |
|---|---|
| `add <name> <ip> <community>` | Add a camera to the monitor config |
| `remove <name>` | Remove a camera |
| `list` | List all configured cameras |
| `discover [subnet]` | Scan the network for SNMP agents |
| `status` | One-shot status table for all cameras |
| `watch [interval]` | Live-refreshing terminal dashboard (default: 10s) |
| `detail <name>` | Full breakdown for a single camera |
| `html [file]` | Generate a self-contained HTML dashboard |
| `alerts` | Check all cameras; report problems (exit ≠ 0 if issues) |

## Configuration

Cameras are stored in `~/.config/thingino/monitor.conf`:

```
# Thingino camera monitor config
front-door|192.168.88.127|mysecret
backyard|192.168.88.128|mysecret
garage|192.168.88.129|anothersecret
```

Format: `NAME|IP|COMMUNITY` (pipe-delimited, one per line, `#` for comments).

You can also copy `monitor.conf.example` to `~/.config/thingino/monitor.conf`
and edit in place.

## Discovery

```bash
# Auto-detect subnet from default route
./thingino-snmp-monitor.sh discover

# Specify subnet
./thingino-snmp-monitor.sh discover 192.168.1.0/24
```

Probes every live host on the subnet for an SNMP agent listening on the
standard port (161) with common community strings (`public`, `private`).
Found cameras are printed with their sysName and sysDescr.

## HTML dashboard

```bash
# Print to stdout
./thingino-snmp-monitor.sh html

# Save to file
./thingino-snmp-monitor.sh html /var/www/cameras.html
```

The HTML is completely self-contained (inline CSS, no JavaScript, no CDN
dependencies). Dark theme, responsive card layout with color-coded
memory/CPU bars. Works on any browser.

## Periodic monitoring

Drop into crontab for periodic HTML generation:

```cron
# Every 5 minutes
*/5 * * * * /path/to/thingino-snmp-monitor.sh html /var/www/cameras.html
```

Or run `alerts` for health checks:

```cron
# Every minute, email if something is wrong
* * * * * /path/to/thingino-snmp-monitor.sh alerts 2>&1 | mail -s "Camera Alert" ops@example.com
```

## Metrics collected

From each camera's SNMP agent (see [snmpd.md](../../services/snmpd.md) for
the full OID reference):

| Metric | OID source |
|---|---|
| System description, name, uptime, location, contact | SNMPv2-MIB |
| Memory: total, available, buffers, cache (KB) | UCD-SNMP-MIB |
| CPU: user%, system%, idle% | UCD-SNMP-MIB |
| Load: 1min, 5min, 15min | UCD-SNMP-MIB laTable |
| Disks: path, total, used, percent | UCD-SNMP-MIB dskTable |
| Network: interface names, RX/TX octets (64-bit) | IF-MIB |
| SNMP packet counters | SNMPv2-MIB |

## Files

| File | Purpose |
|---|---|
| `thingino-snmp-monitor.sh` | The monitor script |
| `monitor.conf.example` | Example configuration file |
| `README.md` | This file |
