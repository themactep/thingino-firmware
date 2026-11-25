Send to Training Pool
=====================

Thingino is building its own open object-recognition engine. `send2train` is
the opt-in way to contribute frames to the corpus those models are trained on.
It is a normal send2 target like Telegram or a webhook, with one difference:
it does nothing at all until you explicitly turn it on.

What it sends, once enabled: one JPEG frame from an accepted motion event, and
a random contributor ID generated on the camera. Nothing else. No hostname, no
MAC address, no serial number, no audio, no video clip, no account, no location.

## Turning it on

1. Open the camera web UI, go to **Services → Training Pool**.
2. Read the notice and flip **Contribute motion-detection frames**.
3. Set the per-day limit and the minimum spacing (or keep the defaults).
4. Save, then go back to **Services** and switch **Training Pool** on under
   **On Motion**.

The first switch is the consent. The second only decides whether frames go out
automatically on motion. Turning either one off stops uploads. Switching off
the consent also stops any pending backoff, so nothing is retried later.

The **Test** button on the Services page sends one frame right away and shows
the collector's answer. Like any other upload it counts against the daily
limit.

## Per-device limits

The camera limits itself, and the collector enforces the same limits again.
A camera cannot talk its way past them.

| Limit | Default | Set by |
|-------|---------|--------|
| Frames per UTC day | 12 (max 48 in the UI) | `train.daily_limit` |
| Minimum gap between frames | 300 s, plus up to 25% random jitter | `train.min_interval` |
| Frame size | 1 MiB | built in |
| Backoff after a failure | 300 s, doubling to 6 h | built in |
| Backoff after HTTP 429 | the collector's `Retry-After` | collector |

The daily count, the last upload time and the backoff window live in
`/etc/send2-train.state`, so a reboot does not reset the quota.

## Privacy

The contributor ID in `/etc/send2-train.token` is 128 random bits, generated
on the camera the first time it uploads. It is a pseudonym, not an account: the
collector stores only a hash of it, next to the frame, so it can count frames
per device without knowing which device that is. Delete the file to give the
camera a new pseudonym and a clean quota.

The collector strips every metadata segment from the frame before storing it:
EXIF (including GPS and camera model), XMP, vendor APPn blocks and JPEG
comments. Frames are de-duplicated by content hash, so the same frame cannot
be counted twice, and the client's filename is discarded.

Uploads use HTTPS with certificate verification and no redirects to plain
HTTP. The endpoint defaults to the pool run by the Thingino project; point
`train.endpoint` at your own collector to keep frames in-house
(see [the collector guide](services/train-collector.md)).

The firmware ships the client and a deployable reference collector
(`contrib/train-collector`); the public pool host itself has to be provisioned
separately. Until it is, an opted-in camera fails its uploads and backs off —
motion detection and every other send2 target keep working.

## Command line

```
send2train                  # upload a frame if the limits allow it
send2train -v               # same, with what/why on stderr
send2train -n               # dry run: report, do not upload
send2train -f frame.jpg     # upload a specific file
send2train -e https://...   # override the endpoint for this run
```

Exit status is `0` when the frame was accepted *or* skipped by a limit, and
`1` when the configuration is unusable or the collector rejected the upload.
Skipping is not an error: the motion path should not care.

Run it by hand from a console to see the current state:

```sh
send2train -v
# - POST https://train.thingino.com/v1/samples (98421 bytes)
# - Frame accepted (3/12 today)
```

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `Training pool contribution is not enabled` | Flip the consent switch on the Training Pool page, or set `train.enabled` to `true`. |
| `Training pool endpoint must use HTTPS` | The endpoint is not an `https://` URL. Use TLS, or a self-hosted collector behind a TLS proxy. |
| `No frame to upload` | No motion frame was available and `prudyntctl snapshot` returned nothing. Check that the streamer is running. |
| `Frame is not a JPEG image` | The motion frame was empty or truncated, often because the clip path was still being written. |
| Backoff active, nothing uploaded | A previous upload failed. The state file records the window; `send2train -v` prints what is left. Fix the collector or wait. |
| Uploads stop at the daily limit | That is the limit. Raise `train.daily_limit` deliberately, not routinely. |
| `HTTP 429` from the collector | The collector's per-device quota for the day is used up or frames are too close together. The camera backs off by `Retry-After`. |

State files:

| Path | Contents |
|------|----------|
| `/etc/send2.json` (`train` object) | Endpoint, consent, limits. |
| `/etc/send2-train.token` | Pseudonymous contributor ID, mode 0600. |
| `/etc/send2-train.state` | Daily counter, last upload, backoff, failure count. |
