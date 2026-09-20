# Frigate test rig for Thingino cameras

A self-contained Frigate container for exercising Thingino cameras over RTSP
and ONVIF: live view, recording, object detection, PTZ presets, and
autotracking. Config and media live on the host; recording segments stage in
a tmpfs before moving to disk.

This rig is CPU-only by default, so no Coral or GPU is needed to bring a
camera up and test PTZ presets. Object detection on CPU is slow and is not
enough for autotracking; see [Autotracking](#autotracking).

## Requirements

- Linux x86_64 host with podman + podman-compose, or docker + compose.
- A Thingino camera reachable from the host on TCP 554 (RTSP) and TCP 80
  (ONVIF).
- About 1 GB of RAM and disk. The first start downloads the detection model,
  so the host needs internet access.

## Quick start

```bash
cd contrib/frigate
cp .env.example .env            # optional: timezone, ports, credentials
./add-camera.sh 192.168.88.31   # writes config/config.yml
podman compose up -d            # or: docker compose up -d
```

- Web UI: `https://<server-ip>:8971/`. Port 8971 is HTTPS-only, so a plain
  `http://` URL is rejected with `400 Bad Request`. Frigate uses a
  self-signed certificate, so the browser shows a warning on first visit;
  accept it to continue. On first start Frigate generates the
  admin user and password and prints them in the container log:
  `podman logs frigate | grep -i password`. Change the password after logging
  in.
- Restream: `rtsp://<server-ip>:8554/<camera-name>`.
- Frigate keys the PTZ preset menu by ONVIF `Name`, so the camera's preset
  descriptions show up as labels. See
  [PTZ presets and friendly names](#ptz-presets-and-friendly-names).

`add-camera.sh` writes the config before the container starts. Run it again to
change the camera set: it rewrites `config/config.yml` and restarts Frigate if
it is running.

Stop and start, or destroy everything:

```bash
podman compose stop
podman compose start
podman compose down -v
```

## Camera streams

Thingino exposes two RTSP streams with the default credentials
`thingino` / `thingino`:

| Stream | URL | Role |
|--------|-----|------|
| Main | `rtsp://thingino:thingino@<ip>:554/ch0` | record |
| Sub  | `rtsp://thingino:thingino@<ip>:554/ch1` | detect |

The generated config does not embed credentials. It references
`{FRIGATE_RTSP_USER}` and `{FRIGATE_RTSP_PASSWORD}`, which Frigate substitutes
from the container environment set in `.env`.

## Adding a camera

```bash
# One camera, default name cam-<ip>
./add-camera.sh 192.168.88.31

# Several cameras in one config
./add-camera.sh 192.168.88.31 192.168.88.34

# Explicit name and a 720p detect stream
./add-camera.sh --name porch --detect-width 1280 --detect-height 720 192.168.88.31

# Non-default ONVIF port
./add-camera.sh --onvif-port 8080 192.168.88.31
```

Run `./add-camera.sh --help` for the full option list. `--name` applies to a
single camera only.

The config is generated, so edits made in the Frigate Settings UI are written
to `config/config.yml` and are overwritten the next time `add-camera.sh` runs.
Edit the script for lasting changes, or commit the generated file.

## PTZ presets and friendly names

Thingino stores each preset as an id, a user description, and coordinates. It
reports the description as the ONVIF preset `Name` (`tt:Name`) and keeps a
stable token (`PresetToken_<id>`). Frigate reads `GetPresets` and keys its
preset menu by the lowercased name, so the labels set on the camera appear in
the UI instead of `preset_0`. The token is unchanged, so `GotoPreset` and
`RemovePreset` keep working.

Set presets on the camera in **Configuration -> Motors -> Presets**, giving
each one a description. Then restart Frigate so it re-reads the ONVIF presets:

```bash
podman restart frigate
```

The raw list the ONVIF server consumes can be checked on the camera itself:

```sh
ptz_presets -g
# 0,1234,567,Front door
# 1,-200,900,Garden
```

Format is `id,pan,tilt,description`; the description is last so it may contain
spaces and commas.

### Autotracking

Autotracking needs a fast detector (Coral, OpenVINO, Hailo) and an ONVIF
camera that supports relative movement in the field of view. The CPU detector
in this rig is not enough.

```bash
./add-camera.sh --autotracking --return-preset home 192.168.88.34
```

`return_preset` must match a preset name on the camera (`home` is the built-in
home position). Frigate returns the camera there after tracking ends. Autotrack
a person by configuring a `required_zones` zone, `all` by default, and enabling
autotracking. See the [Frigate autotracking docs](https://docs.frigate.video/configuration/autotracking)
for calibration and zooming.

## Test checklist

- The camera appears in the UI and shows live video.
- Detect FPS is non-zero in **System -> Camera** (roughly the configured
  `--detect-fps`).
- A `Record`-role stream writes `*.mp4` under `media/frigate/recordings/`.
- The PTZ control shows the camera's preset descriptions, not `preset_N`.
- Selecting a preset moves the camera.
- With a fast detector and `--autotracking`, the camera follows a person and
  returns to `return_preset`.

## Troubleshooting

**Camera unreachable.** Test from the host before blaming the container:

```bash
ffprobe -rtsp_transport tcp -i 'rtsp://thingino:thingino@<ip>:554/ch0'
```

**Bus errors or dropped frames.** Raise the shared memory:

```bash
FRIGATE_SHM_SIZE=1g podman compose up -d
```

**Invalid config.** Frigate logs config validation errors on start. Check:

```bash
podman logs frigate
```

**PTZ preset list is empty.** Confirm ONVIF is enabled on the camera and that
port 80 and the `.env` credentials are correct. Frigate logs the ONVIF
connection result at startup.

**Preset names are stale.** Frigate reads presets when the ONVIF connection is
initialized. Rename presets on the camera, then restart Frigate.

**Autotracking does nothing.** It requires a fast detector and FOV relative
move support; a CPU detector is not sufficient. Check the Frigate log for
`RelativeMove` or motion-estimator errors.

**Reading logs.** Frigate logs to the container's stdout and to the log viewer
in the UI:

```bash
podman logs -f frigate
```

**Lost the admin password.** Set `auth.reset_admin_password: true` in
`config/config.yml`, restart Frigate, and read the new password from the logs,
then remove the setting.

## Layout

| File | Purpose |
|------|---------|
| `docker-compose.yaml` | Frigate 0.18.0, shm, tmpfs cache, volumes, ports |
| `.env.example` | bind address, ports, shared memory, credentials, timezone |
| `add-camera.sh` | renders `config/config.yml` for one or more cameras |
| `config/config.yml` | generated Frigate config (gitignored) |
| `media/` | recordings and snapshots (gitignored) |

## Notes

- The image is pinned to `0.18.0`. Change the tag in `docker-compose.yaml` to
  follow another release, and re-check the config against the
  [reference](https://docs.frigate.video/configuration/advanced/reference).
- The detector is CPU-only. The model is downloaded on first start and cached
  in `config/model_cache/`.
- Port 8971 is authenticated. To script against the unauthenticated API on
  5000, uncomment the localhost-only mapping in `docker-compose.yaml`.
- Bridge networking reaches RTSP and ONVIF by address, so no multicast
  discovery is needed.
