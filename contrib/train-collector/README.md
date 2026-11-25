# Training pool collector

Reference collector for the [`send2train`](../../docs/thingino/send2train.md)
firmware target: cameras that opt in upload one motion frame per accepted event,
the collector enforces per-device and global limits, strips metadata, removes
duplicates, and spools the frames for training.

Full documentation, configuration reference and operating notes:
[`docs/thingino/services/train-collector.md`](../../docs/thingino/services/train-collector.md).

## Quick start

```bash
export TRAIN_IP_PEPPER="$(openssl rand -hex 32)"
docker compose up --build
curl -fsS http://127.0.0.1:8080/healthz
# {"status": "ok"}
```

Point a camera at it (HTTPS required in production — see `deploy/nginx.conf`):

```sh
send2train -e https://train.example.com/v1/samples -v
```

## What it does with a frame

1. Rejects the request unless it carries a well-formed contributor token, the
   `X-Thingino-Train: 1` schema header, a bounded `Content-Length`, and a
   `multipart/form-data` body with a single `frame` part.
2. Parses the JPEG and drops every APPn block (except a plain JFIF APP0) and
   every COM segment — EXIF, GPS, XMP and vendor metadata never reach disk.
3. Checks dimensions and de-duplicates by the SHA-256 of the stripped frame.
4. Applies the per-token daily/spacing quotas, the per-address daily quota and
   the global daily ceiling, then writes the frame and its sidecar atomically.

The sidecar holds the content hash, size, dimensions, a hash of the contributor
token and a keyed hash of the client address. Neither the token nor the raw
address is stored.

## Limits

| Variable | Default | Scope |
|----------|---------|-------|
| `TRAIN_PER_UNIT_DAY` | 24 | per contributor token per UTC day |
| `TRAIN_PER_UNIT_INTERVAL` | 30 s | per contributor token |
| `TRAIN_PER_IP_DAY` | 96 | per client address per UTC day |
| `TRAIN_GLOBAL_DAY` | 200000 | whole pool per UTC day |
| `TRAIN_MAX_BYTES` | 1 MiB | request frame |

## Tests

```bash
python3 -m unittest -v test_collector.py     # collector contract
sh ../send2train-test/run-tests.sh           # the camera side end to end
```
