Thingino training pool: contribution and retention policy
=========================================================

This is the policy behind the **Services -> Training Pool** switch on a
Thingino camera. It explains what happens to a frame after you opt in, how long
it is kept, and what you grant the project by contributing.

Version 1.0, 2026-11-25.

## What the pool is for

Frames from opted-in cameras are used to train and evaluate Thingino's own open
object-recognition models. The models are developed in the open and released
publicly.

## What is collected

- one JPEG frame from an accepted motion event, at most once per minimum
  interval and up to the configured daily limit;
- a random 128-bit contributor ID generated on the camera, stored by the
  collector only as a SHA-256 prefix.

The collector strips EXIF, XMP, vendor metadata blocks and JPEG comments on
ingest. The camera's hostname, MAC address, serial number, model, location,
account and other service credentials are never sent. See
[send2train](send2train.md) for the wire format and limits.

## Who may opt in

Opt in only if you are 18 or older, or are authorized to act for the camera
owner, and only where capturing and sharing the frames is lawful. Motion frames
can contain people and are not blurred. Do not enable the pool on a camera that
covers a place where people have a reasonable expectation of privacy, such as a
bathroom or a changing room.

## License

By enabling the Training Pool switch you grant the Thingino project a
non-exclusive, worldwide, royalty-free, irrevocable license to store, process,
and use the contributed frames to train, evaluate, and improve object
recognition models, including models released publicly. The project will not
publish or redistribute the raw frames. Published models and aggregate
statistics may be derived from them.

There is no payment or attribution for contributions, and no expectation of
confidentiality in a frame that was captured and sent by the camera.

## Retention

Contributed frames are kept indefinitely as part of the training corpus, so
that models can be retrained and audited. There is no scheduled expiry.

Quota counters are not part of the corpus; they are discarded after the UTC day
they describe. Access logs record the pseudonymous unit hash, the content hash
and the outcome, without the token or the raw address, and are kept for 30
days.

If this policy changes, the new version is published here with its date.
Frames contributed under an earlier version remain available under the terms
that applied when they were contributed.

## Opting out and removal

Turning the consent switch off stops uploads immediately and cancels any
pending backoff. Turning off the On Motion switch stops automatic uploads.
Deleting `/etc/send2-train.token` gives the camera a new pseudonym and a clean
daily quota.

Frames already contributed stay in the corpus: without the token the collector
cannot tell which frames came from which camera. If you need frames removed,
email <train@thingino.com> and include the token from
`/etc/send2-train.token`. The project can match the stored pseudonym and delete
the corresponding raw frames, normally within 30 days. Removal cannot retract
models that were already trained on the data.

## Abuse and limits

The camera limits itself and the collector enforces the same limits again:
per-contributor daily and interval caps, a per-address cap, a pool-wide daily
ceiling, a 1 MiB frame cap and dimension checks. Requests that exceed a limit
are rejected or queued with `Retry-After`; repeated abuse is handled by the
per-address and pool-wide caps. The reference collector documents the exact
values in [the collector guide](services/train-collector.md).

## Contact

<train@thingino.com>
