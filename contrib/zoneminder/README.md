# ZoneMinder test rig for Thingino cameras

A self-contained ZoneMinder container for exercising Thingino cameras over
RTSP: live view, motion analysis, and native-bitstream recording. State lives
in named volumes, so the rig survives restarts and can be wiped on demand.

The published ZoneMinder images are from 2021 (ZoneMinder 1.32 on Ubuntu
18.04). This instead builds from Ubuntu 24.04 packages, which carry ZoneMinder
1.36.33 and current FFmpeg libraries.

## Requirements

- Linux x86_64 host with podman + podman-compose, or docker + compose.
- A Thingino camera reachable from the host on TCP port 554.
- The host must be able to reach the camera directly; the container reaches it
  through the normal bridge network.

## Quick start

```bash
cd contrib/zoneminder
cp .env.example .env          # optional, for timezone/port/shm
podman compose up -d --build  # or: docker compose up -d --build
```

The first build installs the ZoneMinder stack and takes a few minutes. The
first start initializes MariaDB and loads the ZoneMinder schema.

- Web UI: `http://<server-ip>:8080/zm` (binds `0.0.0.0` by default)
- Authentication is off by default, so no credentials are required.

Set `ZM_BIND=127.0.0.1` in `.env` to keep the UI on the host only. Because the
default bind is `0.0.0.0` with authentication off, anyone who can reach port
8080 gets the full console: firewall the port or enable ZoneMinder auth before
exposing the host to an untrusted network.

Stop and start:

```bash
podman compose stop
podman compose start
```

Destroy the containers and all recorded data:

```bash
podman compose down -v
```

## Adding a camera

Thingino exposes two RTSP streams with the default credentials
`thingino` / `thingino`:

| Stream | URL | Typical |
|--------|-----|---------|
| Main | `rtsp://thingino:thingino@<ip>:554/ch0` | 1920x1080 |
| Sub  | `rtsp://thingino:thingino@<ip>:554/ch1` | 640x360 |

### Helper script

`add-monitor.sh` registers a camera through the ZoneMinder API and creates a
full-frame detection zone (the API does not create one, which otherwise leaves
Modect with nothing to analyse).

```bash
# Run on the ZoneMinder host, or pass --zm-url when running it remotely.
./add-monitor.sh 192.168.88.31

# Sub stream, continuous recording, explicit size
./add-monitor.sh --name Porch --function Record --width 640 --height 360 192.168.88.31 ch1

# Non-default credentials
./add-monitor.sh --user admin --pass secret 192.168.88.31

# Helper on another machine, ZoneMinder on the server
./add-monitor.sh --zm-url http://<server-ip>:8080/zm 192.168.88.31
```

Useful options: `--function` (`Monitor`/`Modect`/`Record`/`Mocord`/`Nodect`),
`--url` (full source path override), `--no-zone`, `--zm-url`. Run
`./add-monitor.sh --help` for the full list.

The helper is idempotent by monitor name: re-running the same name reports the
existing monitor instead of duplicating it.

Default monitor settings:

| Field | Value | Why |
|-------|-------|-----|
| Source type | FFmpeg | RTSP decode through FFmpeg |
| Source path | full `rtsp://...` URL | ZM 1.36 FFmpeg monitors take one URL, not host/port parts |
| Method | TCP | `rtpRtsp`; UDP causes tearing on busy WiFi |
| Video writer | passthrough (2) | stores the camera's native H.264/H.265, no re-encode |
| Container | mp4 | |

### Pan/Tilt (PTZ)

Thingino cameras expose ONVIF PTZ at `http://<ip>/onvif/ptz_service` with
media profile tokens `Profile_0` (main) and `Profile_1` (sub). ZoneMinder
drives it through its built-in `onvif` control protocol.

```bash
./add-monitor.sh --ptz 192.168.88.34
```

That sets `Controllable`, Control type `ONVIF Camera`, `ControlDevice` =
`Profile_0`, `ControlAddress` =
`http://thingino:thingino@<ip>/onvif/ptz_service`, and a 1 s
`AutoStopTimeout` so a held move stops when released. The PTZ arrows then
appear in the monitor's live view and the console. Use `--ptz-profile` for the
sub stream's token, or `--ptz-address` if ONVIF is not on port 80 or uses other
credentials.

To add PTZ to an existing monitor, PUT the same fields:

```bash
curl -X PUT http://localhost:8080/zm/api/monitors/<id>.json \
  --data-urlencode 'Monitor[Controllable]=1' \
  --data-urlencode 'Monitor[ControlId]=18' \
  --data-urlencode 'Monitor[ControlDevice]=Profile_0' \
  --data-urlencode 'Monitor[ControlAddress]=http://thingino:thingino@<ip>/onvif/ptz_service' \
  --data-urlencode 'Monitor[AutoStopTimeout]=1.00'
```

Two packaged-package gaps affect PTZ, both closed in the image: ZM's ONVIF
module needs Perl's `DateTime` (not a ZoneMinder dependency), and its SOAP
envelope has no XML declaration. Thingino's ONVIF parser rejects a body that
begins with whitespace and no XML declaration, so the image patches
`onvif.pm` to emit one.

The same strictness is fixed on the firmware side by
`package/thingino-onvif/0001-mxml-skip-leading-whitespace-before-root.patch`,
which makes `init_xml()` skip leading whitespace before calling
`mxmlLoadString()`. A camera running that firmware accepts ZM's body as-is,
so the image-side patch becomes redundant for it, though it stays valid for
every ONVIF server.

After reflashing a camera, restart ZoneMinder:

```bash
podman exec zoneminder zmpkg.pl restart
```

The per-monitor `zmcontrol` daemon keeps a session opened before the flash
and will otherwise accept a PTZ command without ever moving the camera.

### Manual setup in the UI

1. Console -> Add Monitor.
2. Source Type `FFmpeg`, Source Path the full `rtsp://...` URL, Method `TCP`.
3. Save, then open the monitor's Zones and add one covering the frame, or
   Modect will log `No zones to check!` and never alarm.

## Test checklist

- Console shows the monitor `Connected` with a non-zero capture FPS.
- Single frame: `http://<server-ip>:8080/zm/cgi-bin/nph-zms?mode=single&monitor=<id>`
- A `Record` monitor writes `*-video.mp4` under the events volume.
- Walk in front of a `Modect` camera and confirm an event appears.

Verified on this rig with a Thingino camera at 192.168.88.31: 15 fps capture
and analysis on both `ch0` and `ch1`, 1920x1080 and 640x360, H.264 with AAC,
and passthrough MP4 recording.

## Troubleshooting

**Shared memory errors / dropped frames.** Raise the shared memory:

```bash
ZM_SHM_SIZE=2g podman compose up -d
```

**Camera unreachable.** Test from the host before blaming the container:

```bash
ffprobe -rtsp_transport tcp -i 'rtsp://thingino:thingino@<ip>:554/ch0'
```

**`No zones to check!`.** Modect has no zone; add one (the helper does this).

**Reading logs.** ZoneMinder logs to its database by default:

```bash
podman exec zoneminder mariadb -u root \
  -e "SELECT Level,Component,Message FROM zm.Logs ORDER BY TimeKey DESC LIMIT 20;"
podman logs zoneminder
```

**Stale `NotRunning` rows.** Deleting a monitor can leave a row in
`zm.Monitor_Status`; it is cosmetic.

**API `404` on `/zm/api/...`.** The rebuild restores the API rewrite rules.
If you run an older image, use `/zm/api/index.php/...` instead.

## ONVIF discovery

Bridge networking pulls RTSP fine but cannot see ONVIF WS-Discovery multicast.
For ONVIF probing, uncomment `network_mode: host` in `docker-compose.yaml`.
The UI then binds port 80 of the host and `ZM_PORT` is ignored.

## Layout

| File | Purpose |
|------|---------|
| `Dockerfile` | Ubuntu 24.04 + ZoneMinder 1.36 + Apache + MariaDB |
| `entrypoint.sh` | initializes MariaDB/ZM and supervises the services |
| `docker-compose.yaml` | one service, named volumes, health check |
| `.env.example` | port, shared memory, timezone |
| `add-monitor.sh` | API helper to register a camera + zone |
| `onvif-declare-xml.pl` | build-time patch: add XML declaration to ZM's ONVIF SOAP |

## Notes on the image

The packaged config has five gaps this image closes:

- `zm.conf` ships `root:root 0640`, but the worker processes run as
  `www-data` and cannot read it.
- `ZM_PATH_FFMPEG` is a build-time "not found" placeholder; the real path is
  pinned in `/etc/zm/conf.d/99-thingino.conf`, and the `ffmpeg` binary is
  installed explicitly.
- The CakePHP API ships without its `.htaccess`, so `/zm/api/<route>` 404s
  until the rewrite rules are restored.
- The ONVIF control module needs Perl `DateTime`, which is not pulled in by
  the ZoneMinder package.
- The ONVIF module omits the XML declaration from its SOAP envelope; see
  [Pan/Tilt (PTZ)](#pan-tilt-ptz).

See `docs/media/streamer.md` for RTSP details and
`docs/dev/rtsp-stress-test.md` for load testing.
