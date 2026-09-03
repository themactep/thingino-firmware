# QEMU firmware test suite

Boots a real thingino image under the Ingenic QEMU fork and asserts the
whole network-facing surface of the firmware: boot and services, the WiFi
provisioning portal, DHCPv4/v6, SLAAC, DNS, the web UI, ONVIF, mDNS, NTP,
remote syslog, link flap, and overlay persistence across a reboot. Browser
flows are driven with Playwright and screenshotted.

The image under test is the same `.bin` that gets flashed to a camera. No
firmware code is stubbed or recompiled for testing.

## Quick start

```sh
make GROUP=testing CAMERA=qemu_t31x_eth fast  # build a test profile
scripts/qemu-test/run.sh qemu_t31x_eth        # run its suite
```

`run.sh` hands the profile to the driver, which reads what the profile
is from its `qemu-test.json`, finds the newest matching image under
`output/`, picks up the QEMU built alongside it, and re-execs itself
under `sudo` and into a private network namespace when the run needs a
tap device.

```sh
run.sh qemu_t31x                 # wifi portal flow (slirp)
run.sh qemu_t31x_eth             # ethernet + full network lab (tap)
run.sh qemu_t31x_ethwifi         # both interfaces (tap)
run.sh qemu_t31x_eth --net slirp # override the backend
run.sh qemu_t31x_eth --only onvif,ipv6   # just these optional suites
```

Anything after the profile name is passed through to `harness.py`, which
also runs standalone if you need full control (`harness.py --help`).

Requirements: `dnsmasq` and `tcpdump` installed, `npm ci` in this
directory plus `npx playwright install chromium` for the browser tests,
and passwordless `sudo` for tap mode. A tap run lives in its own network
namespace (`qt-<pid>`), so it never touches the host's DNS, NTP or syslog
ports, nothing gets parked, and several tap runs can share one host.

## A profile describes itself

`configs/cameras-testing/<profile>/qemu-test.json`:

```json
{"soc": "t31x", "caps": ["wired", "wifi"], "net": "tap"}
```

| Field | Meaning |
| --- | --- |
| `soc` | key into `SOC_MACHINES` (machine, RAM) |
| `caps` | what the camera has: `wired` (an uplink), `wifi` (a radio) |
| `net` | default backend: `tap` runs the full lab, `slirp` bridges through host port forwards |

What runs follows from the capabilities: a wifi-only camera exercises the
portal, provisioning and the reboot into STA; a wired one the full network
lab; one with both also the wired-gateway takeover. Nothing is inferred
from the profile's name.

## Architecture

```
host                                              QEMU guest
----                                              ----------
run.sh            exec harness.py --profile <name>
  harness.py      entry point, runs qemutest/driver.py
  qemutest/
    profile       qemu-test.json -> soc, capabilities, backend;
                  newest image under output/ and the QEMU beside it
    driver        resolves the run, sudo and netns re-exec, boot, report
    serial, qmp,  console with a guest state machine    ──► ttyS0
    guest         QMP (link up/down, reset, regs)       ──► monitor
                  SSH channel (ephemeral ed25519)       ──► dropbear
    probes        until(): every wait is a condition
    netlab        netns qt-<pid>: qtap0 + dnsmasq       ──► eth0
                  DHCPv4/RA/SLAAC/DHCPv6/DNS, SNTP and
                  syslog sinks, WS-Discovery, mDNS
    onvif_client  SOAP + WS-UsernameToken               ──► onvif_simple_server
    playwright    manifest-driven chromium scenarios    ──► uhttpd
    suites/       common, wifi, net, onvif, webui
    plan          the ordered suite table
    results       the ordered check list and its contract
    report        report.html with screenshots
```

Lab addressing: `192.168.100.1/24` and `fd00:5c1::1/64` on `qtap0`, DHCP
pools `.50-.150` and `fd00:5c1::100-1ff`.

## Adding a suite

Suites live in one ordered table, `SUITES` in `qemutest/plan.py`. A suite
is a function taking the run context, in the `qemutest/suites/` module for
its domain (`common`, `wifi`, `net`, `onvif`, `webui`; a new domain gets a
new module), plus one table row. Nothing in the driver changes.

```python
def test_isp(ctx):
    guest, res = ctx.guest, ctx.res
    rc, out = guest.run("cat /proc/jz/isp/info")
    res.check("isp_registered", "sensor" in out, out[:60])
```

```python
SUITES = [
    ...
    Suite("isp", test_isp, WIRED + ("lab", "v4"), header="ISP"),
]
```

Row fields:

| Field | Meaning |
| --- | --- |
| `name` | the `--only` token and label; rows may share one |
| `fn` | callable taking `ctx` |
| `requires` | capabilities that must hold, else the row is skipped silently; start with `WIRED`, `WIFI_ONLY` or `BOTH` for what the profile is |
| `header` | section banner printed before the row |
| `optional` | `False` means it always runs and `--only` never filters it out |

Capabilities come from `Ctx.has()`. What the profile is: `wired`,
`nowired`, `wifi`. What the run has: `lab`, `nolab`, `qmp`, `v4`, `host`,
`pw`, `pw_ok`, `reboot`.

Table position is execution order. The table is the union of every
profile's plan; filtering on capabilities alone yields the wifi-only
sequence and the wired one, so put a row where it belongs relative to its
neighbours and let the filter do the rest. `--only` tokens and the
`--help` text derive from the table, so there is no second list to
update.

### Rules for suite functions

- Read what you need off `ctx` in one line at the top; leave the body
  plain. Never add positional parameters.
- Report through `res`: `check(name, cond, detail)`, `ok`, `fail`,
  `xfail` for a known gap, `skip`. **Check names are the API** - reports,
  CI logs and regression diffs key on them, so renaming one is a breaking
  change.
- Assert positively. `res.check("x", "No such file" not in out)` passes
  against a U-Boot prompt, a timeout, or an empty read; a sentinel like
  `[ -f /path ] && echo OK` cannot.
- Publish discoveries onto `ctx` (`ctx.guest_v4 = ...`) rather than
  returning them, so later rows can `require` them.
- Wait with `probes.until()` or `guest.run_until()`, never `time.sleep()`.
  Under TCG the guest is slow and load-sensitive; every fixed wait in here
  has flaked at least once.
- Reboot through `guest.reboot()`, or `guest.expect_reboot()` when the
  guest reboots itself, then `login()`. The serial channel tracks boot,
  shell and rebooting; `guest.run()` returns `(-1, "(guest not at shell:
  ...)")` rather than typing into a dying shell or U-Boot.

### Adding a browser scenario

The plan hands Playwright a manifest (`pw-manifest.json` in the report
dir) naming the scenarios to run and their URLs; `playwright-portal.js`
skips any describe block whose key is absent. A new scenario is a describe
block keyed on a new manifest field plus that field in the suite that
wants it. There are no environment flags to keep in step.

### Adding a SoC or profile

A SoC is one line in `SOC_MACHINES` in `qemutest/config.py` (machine name,
RAM in MB). A profile needs no harness change at all: a directory under
`configs/cameras-testing/` with its defconfig and a `qemu-test.json`.

## The expected check list

Each profile carries `configs/cameras-testing/<profile>/expected-checks.txt`:
the check names a run must emit, in order. The driver compares every full
run against it and fails on any deviation, so a check cannot vanish
quietly (a suite that bailed early, a row skipped because something it
required was never discovered) and a reorder is visible. `--only` runs
are partial by design and are not compared.

After adding, renaming or reordering checks on purpose, record the new
contract from a green run:

```sh
run.sh qemu_t31x_eth --update-expected
```

and commit the file with the change that caused it.

## Reports

Everything lands in `output/<branch>/qemu-test-reports/<profile>/`:
`report.html` (self-contained, screenshots inlined), `serial-results.json`
(the ordered check list; this is what regression diffs compare),
`meta.json` (profile, machine, image, qemu path, commit, boot seconds),
`serial.log`, `qemu-stderr.log`, `dmesg.txt`, `logread.txt`, `ps.txt`,
`netstat.txt`, `ipaddr.txt`, the dnsmasq config/log/leases, ONVIF SOAP
dumps, `pw-manifest.json` (the browser scenarios the plan requested),
Playwright screenshots, and on a boot failure two QMP register
snapshots five seconds apart plus a timestamped copy of the serial log
(identical PCs across the two mean a hard CPU freeze rather than a slow
guest).

## CI

`.github/workflows/qemu-test.yaml`, manual dispatch only. It builds the
requested profiles in parallel on arm64 runners, then fans out one test
job per profile on x86_64 against the **released** QEMU pinned by
`package/qemu-ingenic/qemu-ingenic.mk` and verified against
`qemu-ingenic.hash`. Reports upload as run artifacts. Steady state is
about 15 minutes.

## Gotchas

These all cost real debugging time; check them before going deeper.

- **ONVIF credentials do not live in `onvif.json`.** The server reads
  RTSP auth from the streamer's own config, first of `/etc/prudynt.json`,
  `/etc/streamer.d/rtsp.json`, `/etc/timps.conf`, `raptorctl`. Use
  `streamer_auth()` in `qemutest/suites/onvif.py`, which mirrors that
  order; a stale copy means 401 `NotAuthorized`.
- **After `reboot`, the shell echoes one more prompt before it dies.**
  Matching it reports "logged in" while the machine is still going down,
  and the next command lands in the *next* boot's U-Boot autoboot prompt.
  `guest.reboot()` marks the channel as rebooting, and `login()` then
  refuses any prompt until a reset banner (`qemutest/serial.py`).
- **The console shell answers a cursor-position probe** (`ESC[6n`) after
  login. Unanswered, it eats the next command; the serial reader replies
  automatically.
- **Test images boot with `debug=1`** (`configs/cameras-testing/<profile>/uenv.txt`),
  so the console getty drops straight to a root shell with no login
  prompt. `login()` handles both.
- **A wifi-only profile has an eth0 that real WiFi-only cameras lack.** An instant
  slirp lease makes the wired-gateway logic kill WiFi, so the STA test
  drops the link over QMP first.
- **Slirp host forwards target `10.0.2.15`.** The guest re-randomises its
  MAC each boot, so after a reboot re-add the address statically and ping
  the gateway once to refresh the stale ARP entry.
- **Build load causes timing flakes.** Do not compile while a suite runs.
- **A killed tap run leaves qemu and dnsmasq alive in its namespace.**
  They cannot block the next run, and the next run reaps them, but if
  you are hunting stray CPU, `ip netns list` shows them as `qt-<pid>`;
  never `pkill -x qemu-system-mipsel`, the name is truncated to 15
  chars and matches nothing.
