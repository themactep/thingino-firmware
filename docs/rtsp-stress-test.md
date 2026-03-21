RTSP Stress Test Script
=======================

The `scripts/rtsp-stress-test.sh` script automates repeated RTSP playback tests
from a host machine against a Thingino camera. It is meant for users who need
to answer questions like:

- does RTSP/UDP fail in this network?
- does RTSP/TCP stay clean?
- does lowering bitrate help?
- does changing GOP or FPS help?
- can I capture logs I can share back with developers?

The script was written around real-world prudynt RTSP debugging and is intended
to produce repeatable test runs with per-session logs and a machine-readable
summary.


What the script does
--------------------

Depending on the options you pass, the script can:

- run repeated `ffplay` sessions over RTSP/UDP or RTSP/TCP
- optionally change camera settings using `jct import`
- reboot the camera between modified scenarios
- wait for SSH and RTSP to come back
- optionally slice a remote prudynt log file per client session
- write separate client and server logs for every session
- summarize:
  - RTP packet loss
  - `max delay reached`
  - decoder errors
  - concealment events
- restore the original camera settings when finished


Requirements
------------

### On the host machine

The script requires:

- `bash`
- `ssh`
- `ffplay`
- `ffmpeg`
- `python3`
- `timeout`

The host machine is where you run `scripts/rtsp-stress-test.sh`.

### On the camera

The camera needs:

- SSH access
- `jct`
- a working RTSP stream

Optional but recommended:

- a writable prudynt log path such as `/mnt/nfs/prudynt.log`


Basic usage
-----------

Run the current camera configuration without changing anything:

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160
```

This runs one scenario named `current` and records repeated playback sessions
using the current camera settings.


Recommended one-command test matrix
-----------------------------------

The easiest way to collect useful diagnostics is the built-in recommended
matrix:

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --server-log /mnt/nfs/prudynt.log \
  --recommended-matrix
```

This appends the following scenarios:

- `current:-:-:-:-`
- `lowbit1500:1500:0:30:1800`
- `bitrate1600:1600:0:30:1920`
- `gop60-1700:1700:0:60:2040`
- `fps20-1700:1700:20:30:2040`

Those scenarios are useful because they compare:

- the current camera state
- a known low-bitrate configuration
- a slightly higher bitrate
- a higher bitrate with longer GOP
- a higher bitrate with lower FPS

This helps distinguish average bitrate problems from burst-structure problems.


RTSP transport comparison
-------------------------

To compare UDP and TCP behavior, run the matrix twice.

UDP:

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --server-log /mnt/nfs/prudynt.log \
  --transport udp \
  --recommended-matrix
```

TCP:

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --transport tcp \
  --recommended-matrix
```

If TCP is clean while UDP is not, that strongly suggests transport loss rather
than timestamp corruption or deterministic encoder corruption.


Scenario format
---------------

Each custom scenario uses:

```text
label:bitrate:fps:gop:est_bitrate
```

Use `-` for fields you want to leave unchanged.

Examples:

```text
current:-:-:-:-
lowbit:1500:0:30:1800
gop60:1700:0:60:2040
fps20:1700:20:30:2040
```

Meaning of fields:

- `label`
  - directory-friendly scenario name used in result paths
- `bitrate`
  - `stream0.bitrate`
- `fps`
  - `stream0.fps`
  - `0` means auto if that is how the camera config interprets it
- `gop`
  - `stream0.gop`
- `est_bitrate`
  - `rtsp.est_bitrate`


Useful options
--------------

### Session count

Increase the number of repeated sessions:

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --sessions 12 \
  --recommended-matrix
```

### Session duration

Make each playback session longer:

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --duration 25 \
  --recommended-matrix
```

### Pause between sessions

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --pause 5 \
  --recommended-matrix
```

### Output directory

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --output-dir ./my-rtsp-test
```

### Remote log slicing

If prudynt logs are being redirected to a file on the camera, pass that path:

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --server-log /mnt/nfs/prudynt.log \
  --recommended-matrix
```

Then the script will capture a matching `server-N.log` slice for every client
session.


Running against a custom prudynt binary
---------------------------------------

If you are testing a prudynt binary launched from a writable mount such as
`/mnt/nfs/prudynt`, use `--start-cmd` so the script can restart it after each
reboot.

Example:

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --server-log /mnt/nfs/prudynt.log \
  --start-cmd "killall prudynt >/dev/null 2>&1 || true; nohup /mnt/nfs/prudynt >/mnt/nfs/prudynt.log 2>&1 </dev/null &" \
  --recommended-matrix
```

This is useful when:

- the bundled service is disabled
- you are testing a patched prudynt binary
- you want logs written to `/mnt/nfs/prudynt.log`


Output layout
-------------

The script creates a timestamped directory by default:

```text
./rtsp-stress-YYYYmmdd-HHMMSS/
```

Inside it you will find:

- `metadata.txt`
  - host-side parameters and the original camera config
- `overall-summary.txt`
  - one-line result summary per scenario
- `restore-original.json`
  - generated only when the script changed settings and restore is enabled
- `<scenario>/scenario.txt`
  - scenario values
- `<scenario>/update.json`
  - generated settings update for modified scenarios
- `<scenario>/summary.txt`
  - per-session numeric results
- `<scenario>/client-N.log`
  - `ffplay` output for session `N`
- `<scenario>/server-N.log`
  - remote log slice for session `N`, if `--server-log` was provided


How to read the results
-----------------------

The script summarizes four useful indicators:

- `missed`
  - sum of `RTP: missed N packets`
- `decode`
  - number of `error while decoding` lines
- `conceal`
  - number of concealment events
- `maxdelay`
  - number of `max delay reached` lines

Typical interpretation:

- UDP bad, TCP clean
  - transport loss is likely
- `missed > 0` before decode errors
  - packet loss is likely causing truncated H.264 slices
- lowering bitrate helps
  - bandwidth or burst size is likely part of the problem
- increasing GOP helps
  - keyframe cadence / burst structure may matter
- lowering FPS makes things worse
  - do not assume lower FPS is always safer; larger per-frame bursts can hurt


Automatic restore behavior
--------------------------

By default, if the script changes camera settings, it stores the original:

- `stream0.bitrate`
- `stream0.fps`
- `stream0.gop`
- `rtsp.est_bitrate`

At the end, it writes the original values back and reboots the camera again.

If you do not want restore behavior:

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --recommended-matrix \
  --no-restore
```

Use `--no-restore` carefully.


Examples
--------

### Test the current config only

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --server-log /mnt/nfs/prudynt.log
```

### Compare current config and one safer config

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --server-log /mnt/nfs/prudynt.log \
  --scenario current:-:-:-:- \
  --scenario lowbit:1500:0:30:1800
```

### Test whether GOP helps at 1700 kbps

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --server-log /mnt/nfs/prudynt.log \
  --scenario base1700:1700:0:30:2040 \
  --scenario gop60:1700:0:60:2040
```

### Test UDP vs TCP separately

```bash
./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --transport udp \
  --recommended-matrix

./scripts/rtsp-stress-test.sh \
  --camera 192.168.88.160 \
  --transport tcp \
  --recommended-matrix
```


Sharing results
---------------

When reporting a problem, share:

- the full `overall-summary.txt`
- the relevant scenario `summary.txt`
- one or two failing `client-N.log` files
- matching `server-N.log` files if available
- the exact command you ran

That usually gives enough information to tell whether the issue looks like:

- network/UDP loss
- bitrate pressure
- keyframe burst pressure
- a stream bootstrap problem
- or a local prudynt-side warning visible in server logs


Troubleshooting
---------------

### The script says the camera did not return after reboot

- verify the camera really rebooted
- wait a little longer and try again with a larger `--boot-timeout`
- check whether the camera changed IP
- if testing a custom prudynt binary, make sure `--start-cmd` is correct

### The script says the stream did not become ready

- verify the RTSP URL manually with `ffplay` or `ffmpeg`
- confirm the channel path, usually `ch0`
- if prudynt is not launched automatically, provide `--start-cmd`

### `server-N.log` files are empty

- confirm the remote path passed to `--server-log`
- make sure prudynt is actually writing there
- if you omit `--server-log`, empty or absent server logs are expected

### A scenario fails before playback starts

- check `<scenario>/update.json`
- confirm the remote config accepts those keys
- verify `jct` works on the target camera


See also
--------

- `docs/diagnostics.md`
- `docs/streamer.md`
- `scripts/rtsp-stress-test.sh --help`
