# Time, Timezone, and NTP

Clock, timezone, and NTP configuration all funnel through a single gate,
`timectl` (`/usr/sbin/timectl`). The WebUI, DHCP hooks, `tzselect`, ONVIF, and
the wifi portal are thin clients over it; everything else reads the resolved
state with `timectl status`.

## The model

- **Clock (UTC)** — `ntpd` is the sole authority once the network is up. A
  manual time set is a *hint*: it is applied, then reconciled with NTP, so a
  client that sends a wrong value is corrected instead of persisting.
- **Timezone** — a tzdb name (`/etc/timezone`, e.g. `America/Toronto`) resolved
  to a POSIX TZ string (`/etc/TZ`, e.g. `EST5EDT,M3.2.0,M11.1.0`) through the
  `/usr/share/tz.json` table.
- **NTP server** — the resolved server list in `/tmp/ntp.conf` (tmpfs), with the
  user's persistent choice in `/etc/default/ntp.conf`.

## State files

| File | Purpose |
|------|---------|
| `/etc/timezone` | tzdb name, e.g. `America/Toronto` |
| `/etc/TZ` | POSIX TZ string, e.g. `EST5EDT,M3.2.0,M11.1.0` |
| `/etc/timezone.source` | who set the timezone: `default` / `dhcp` / `user` |
| `/etc/default/ntp.conf` | user-pinned NTP servers (persistent) |
| `/tmp/ntp.conf` | resolved NTP servers read by `ntpd` (tmpfs) |
| `/etc/ntp.source` | who set the NTP servers: `default` / `dhcp` / `user` |
| `/usr/share/tz.json` | tzdb name to POSIX TZ mapping table |

## timectl

```
timectl status                      # key=value dump for observers
timectl refresh                     # boot: re-resolve /etc/timezone -> /etc/TZ
timectl set-timezone <name> [--source user|dhcp]
timectl set-ntp <srv>...   [--source user|dhcp]
timectl set-time <date>             # hint + NTP reconcile
timectl pin-timezone                # keep current timezone, ignore DHCP
timectl unpin-timezone              # allow DHCP to change it again
timectl sync                        # one-shot NTP sync
```

## Source precedence

Writes are gated by a source with the order `default < dhcp < user`. A writer
may only set a value when its source ranks at least as high as the currently
recorded source.

- `user` — WebUI, `tzselect`, wifi portal, ONVIF manual set. Always wins.
- `dhcp` — DHCP tzdb timezone (option 101) and NTP servers (option 42). Fills a
  value only when nothing user-pinned it.
- `default` — `Etc/GMT`. The fallback.

`pin-timezone` promotes the *current* timezone to `user` without changing its
value; this is what the WebUI's "Ignore time zone sent by DHCP" toggle does.
`unpin-timezone` demotes it back to `default`.

## Boot sequence

1. `F01datetime` sets a fail-safe clock from the build timestamp.
2. `S01timezone` runs `timectl refresh`: ensure `/etc/timezone` exists, resolve
   it, write `/etc/TZ` when changed, and migrate a legacy `dhcp.ignore_timezone`
   flag to a pinned timezone (then delete it).
3. `S49ntpd` starts `ntpd` and does a one-shot `ntpd -q -N` sync.

## Writers

| Writer | Calls |
|--------|-------|
| WebUI time config | `timectl set-timezone / set-ntp / set-time / pin-timezone / unpin-timezone` |
| DHCP `tz` hook | `timectl set-timezone --source dhcp "$tzdbstr"` |
| DHCP `ntp` hook | `timectl set-ntp --source dhcp "$ntpsrv"`, `timectl sync` |
| `tzselect` (interactive) | `timectl set-timezone --source user` |
| wifi portal | `timectl set-timezone --source user` |
| ONVIF `SetSystemDateAndTime` | `timectl set-time` |

## Live propagation (no reboot)

uClibc-ng is built with `__UCLIBC_HAS_TZ_FILE_READ_MANY__`, so `tzset()` —
called by `localtime()` and `strftime()` — re-reads `/etc/TZ` on every call
when `TZ` is not present in the environment. A timezone change therefore takes
effect immediately in every running daemon, with no reboot or restart.

The invariant that makes this work: **daemons must never have `TZ` in their
environment.** `rcS` deliberately does not export it. A daemon restarted from
an interactive shell or a CGI that exported `TZ` would instead cache the old
timezone forever, so the service scripts must not inherit it.

## Reading the state

Observers use `timectl status`, which prints one `key=value` per line:

```
timezone_name=America/Toronto
timezone_posix=EST5EDT,M3.2.0,M11.1.0
timezone_source=user
ntp_servers=192.168.88.1
ntp_source=dhcp
clock_utc=1786704403
clock_local=2026-08-14 06:46:43 EDT
```
