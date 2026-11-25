Training pool collector
=======================

`contrib/train-collector/collector.py` is the reference collector for the
[`send2train`](../send2train.md) target. It is what has to run behind the
default `https://train.thingino.com/v1/samples` endpoint, or behind whatever
host a self-hosting user puts in `train.endpoint`. It accepts opt-in motion frames from
cameras, enforces the submission limits on the server side, strips metadata,
de-duplicates by content, and spools the frames for training. A bucket sync
script ships the spool to S3-compatible storage, so the collector itself stays
small and stateless apart from its spool directory.

The camera-side contract is versioned and deliberately narrow:

```
POST /v1/samples
  Authorization: Bearer <32 lowercase hex contributor token>
    (send2train itself sends the same value as X-Thingino-Token)
  X-Thingino-Train: 1
  Content-Type: multipart/form-data; boundary=...
  part "frame" = image/jpeg

201 {"status":"accepted","id":"<16 hex>","remaining":<int>}
200 {"status":"duplicate","id":"<16 hex>"}
401 missing or malformed token
411 Content-Length required
413 request or frame too large
415 wrong content type, not a JPEG, bad dimensions
429 rate limited, with Retry-After
503 pool at capacity
```

## Run it

```bash
cd contrib/train-collector
docker compose up --build
```

The service listens on `127.0.0.1:8080` behind the container's port mapping and
writes to `./data`. For a real deployment put it behind a TLS terminator, or
give it a certificate directly with `TRAIN_TLS_CERT` / `TRAIN_TLS_KEY` — the
camera refuses non-HTTPS endpoints, so one of the two is mandatory in
production.

Without Docker:

```bash
TRAIN_DATA_DIR=/srv/train TRAIN_TLS_CERT=/etc/ssl/train.crt \
TRAIN_TLS_KEY=/etc/ssl/train.key TRAIN_IP_PEPPER="$(openssl rand -hex 32)" \
python3 collector.py
```

`deploy/` has a systemd unit and an nginx TLS front end to copy from.

## Configuration

Everything is environment variables; there is no config file to parse.

| Variable | Default | Meaning |
|----------|---------|---------|
| `TRAIN_BIND` | `127.0.0.1:8080` | `host:port` to listen on. Use port `0` to pick an ephemeral port (tests do). |
| `TRAIN_DATA_DIR` | `data` | Spool root. Holds `frames/`, `index/` and `_state/`. |
| `TRAIN_MAX_BYTES` | `1048576` | Largest accepted JPEG, in bytes. |
| `TRAIN_PER_UNIT_DAY` | `24` | Frames per contributor token per UTC day. |
| `TRAIN_PER_UNIT_INTERVAL` | `30` | Minimum seconds between frames from one token. |
| `TRAIN_PER_IP_DAY` | `96` | Frames per client address per UTC day (see the proxy note). |
| `TRAIN_GLOBAL_DAY` | `200000` | Hard daily ceiling for the whole pool. |
| `TRAIN_MIN_DIMENSION` | `64` | Reject frames smaller than this, in pixels. |
| `TRAIN_MAX_DIMENSION` | `8192` | Reject frames larger than this. |
| `TRAIN_INFLIGHT_LIMIT` | `32` | Concurrent upload handlers; beyond this the answer is `503`. |
| `TRAIN_ADMIN_TOKEN` | unset | Required for `GET /v1/stats`; unset disables the endpoint. |
| `TRAIN_IP_PEPPER` | random per process | Key for the pseudonymous client-address hash. Set it, or addresses change on every restart. |
| `TRAIN_TRUST_PROXY` | unset | Set to `1` to read the client address from `X-Forwarded-For`. Only behind a proxy you control. |
| `TRAIN_TLS_CERT`, `TRAIN_TLS_KEY` | unset | Serve HTTPS directly instead of behind a proxy. |
| `TRAIN_PORT_FILE` | unset | Write the bound port here (used by tests and supervisors). |
| `TRAIN_LOG_SILENT` | unset | Set to `1` to drop the JSON access log (development only). |

## What it stores

```
data/
  frames/YYYY/MM/DD/<sha256>.jpg     metadata-stripped frames
  frames/YYYY/MM/DD/<sha256>.json    sidecar: hash, size, dimensions, unit, source
  index/ab/<sha256>                  dedupe markers (empty files)
  _state/quota.json                  daily counters, flushed at most once a second
  _tmp/                              in-flight writes; safe to prune when stopped
```

The sidecar contains no token and no raw address: `unit` is a SHA-256 prefix of
the token and `source` is an HMAC of the client address under `TRAIN_IP_PEPPER`.
Both are stable per contributor, which is what abuse handling needs, and neither
can be reversed into an identity from the spool alone. Keep the pepper out of
the bucket.

A frame's `sha256` is computed after metadata stripping, so a client that
re-uploads the same image with different EXIF still produces one row.

## Shipping to a bucket

`sync-to-s3.sh` moves finished days out of the spool and into an S3-compatible
bucket, then removes the local copies. Run it from cron, or as a systemd timer:

```bash
S3_URI=s3://thingino-training/frames ./sync-to-s3.sh
```

| Variable | Meaning |
|----------|---------|
| `S3_URI` | Destination prefix, required. |
| `TRAIN_DATA_DIR` | Spool root, default `data`. |
| `TRAIN_KEEP_DAYS` | Days left on local disk, default `2`. The current day is never moved. |
| `AWS_PROFILE`, `AWS_ENDPOINT_URL`, ... | Passed through to `aws s3 sync`. |

Uploads are checksum-verified by `aws s3 sync`; a frame is only deleted locally
after the sync exits zero. Keep bucket versioning and a lifecycle rule that
moves frames to cheaper storage — the corpus is append-only and re-downloading
it is expensive.

## Abuse and privacy controls

- **Per-token, per-address and global caps.** The client's own limits are the
  courtesy; these are the enforcement. A token is self-generated, so treat the
  per-address and global caps as the real defence against a determined
  contributor, and the per-token cap as the one that stops an honest camera
  from flooding the pool.
- **Size and shape limits.** `Content-Length` is required and capped before a
  byte is read; the body is capped again; only a single `frame` part is used;
  the JPEG is parsed and its dimensions checked before anything is stored.
- **Metadata stripping.** Every APPn block (except a plain JFIF APP0) and every
  COM segment is dropped, so a camera that does add EXIF cannot leak GPS,
  model or serial number into the corpus. Strip on ingest, not in a later
  job — the bucket must never hold the metadata copy.
- **Content de-duplication.** Replays and repeated frames cost a request but no
  storage and no quota.
- **No unbounded buffering.** One request holds at most `TRAIN_MAX_BYTES` plus
  multipart overhead, connections time out after 30 s, and the handler count is
  bounded.
- **No identity in the data.** Only pseudonymous hashes are written. The access
  log records the unit hash, the content hash and the outcome, not headers.

Scaling notes: the counters are process-local (flushed to `_state/quota.json`),
so run one collector process per spool, or a shared spool with a single writer.
If you need several instances, put the quota check in front of them (an API
gateway or a small shared store) rather than running the same spool from two
processes.

## Operating it

```bash
curl -fsS https://train.example/healthz          # {"status": "ok"}
curl -fsS -H "Authorization: Bearer $ADMIN" \
  https://train.example/v1/stats                 # {"accepted_today": N, ...}
```

Watch the JSON access log for `pool_full`, `unit_quota` and `ip_quota` rates:
a sudden jump in `ip_quota` is a compromised or misconfigured camera network,
not normal use. The daily counters roll at 00:00 UTC.

Retention is a policy decision, not a code one. Frames are only useful as
training data, so the recommended posture is: keep the corpus, publish the
collection policy, and delete the `_state` quota counters after the day they
describe.

## Testing

```bash
cd contrib/train-collector
python3 -m unittest -v test_collector.py
```

The client side has its own suite that runs `send2train` against this
collector, including the request-inspection case:

```bash
sh contrib/send2train-test/run-tests.sh
```
