#!/usr/bin/env python3
"""Recover prudynt-t NFS recordings that lost their MP4 init segment.

When a camera mounts its NFS share with ``soft``, a stalled write is
aborted after a few seconds and the data is lost. The recorder writes
the MP4 init segment (ftyp+moov) first, so those lost writes leave a
run of zero bytes at the start of the file: the moof+mdat fragments
survive, but without ftyp/moov the file will not play.

Because the init segment is identical across every segment recorded by
the same camera with the same stream settings, it can be copied from a
healthy segment and spliced in front of the surviving fragments.

For each directory argument this script:
  - scans ``*.mp4`` (skipping ``*.recovered.mp4``),
  - picks the first healthy segment as the init-segment donor,
  - writes each recovered file next to its original as
    ``<name>.recovered.mp4``, or into ``--out DIR`` with the original
    name.

Originals are never modified, so the script is safe to re-run. Run it
after stopping the recording, otherwise the segment currently being
written will be recovered in a half-finished state.

Usage:
    recover-nfs-recordings.py DIR [DIR ...] [--donor FILE] [--out DIR]
"""

import argparse
import os
import sys

FTYP = b"ftyp"
MOOF = b"moof"

# A moof box can never plausibly exceed this; the real ones are a few
# hundred bytes. This keeps a stray b"moof" inside an mdat payload from
# being mistaken for the first fragment.
MAX_MOOF_SIZE = 1 << 20


def find_first_moof(data: bytes) -> int:
    """Return the offset of the first moof box, or -1 if there is none.

    The returned offset points at the box size field, i.e. four bytes
    before the b"moof" fourcc, so the caller can split cleanly.
    """
    i = 0
    while True:
        i = data.find(MOOF, i)
        if i < 0:
            return -1
        if i >= 4:
            size = int.from_bytes(data[i - 4:i], "big")
            if 8 <= size <= MAX_MOOF_SIZE:
                return i - 4
        i += 4


def has_init_segment(data: bytes) -> bool:
    return len(data) >= 8 and data[4:8] == FTYP


def scan_directory(path: str):
    files = sorted(
        f for f in os.listdir(path)
        if f.endswith(".mp4") and not f.endswith(".recovered.mp4")
    )
    return [os.path.join(path, f) for f in files]


def load(path: str) -> bytes:
    with open(path, "rb") as fh:
        return fh.read()


def recover(directory: str, donor_path: str | None, out_dir: str | None):
    files = scan_directory(directory)
    if not files:
        print(f"{directory}: no .mp4 files")
        return

    donor = None
    if donor_path:
        donor = load(donor_path)
        if not has_init_segment(donor):
            print(f"error: {donor_path} is not a healthy MP4 (no ftyp)", file=sys.stderr)
            return
    else:
        for f in files:
            data = load(f)
            if has_init_segment(data):
                donor, donor_path = data, f
                break

    if donor is None:
        print(f"{directory}: no healthy segment found to use as a donor; "
              "pass one with --donor", file=sys.stderr)
        return

    donor_moof = find_first_moof(donor)
    if donor_moof < 0:
        print(f"{directory}: donor {donor_path} has no fragments", file=sys.stderr)
        return
    init = donor[:donor_moof]

    recovered = skipped = 0
    for f in files:
        if f == donor_path:
            continue
        if out_dir:
            out = os.path.join(out_dir, os.path.basename(f))
        else:
            out = f + ".recovered.mp4"
        if os.path.exists(out):
            skipped += 1
            continue
        data = load(f)
        if has_init_segment(data):
            continue
        first = find_first_moof(data)
        if first < 0:
            continue  # empty or in-progress segment, nothing to salvage

        fixed = init + data[first:]
        if fixed[4:8] != FTYP:
            print(f"{f}: splice produced no ftyp, skipping", file=sys.stderr)
            continue
        with open(out, "wb") as fh:
            fh.write(fixed)
        recovered += 1
        print(f"{os.path.basename(f)} -> {os.path.basename(out)} "
              f"({len(fixed)} bytes)")

    print(f"{directory}: donor={os.path.basename(donor_path)} "
          f"recovered={recovered} skipped_existing={skipped}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dirs", nargs="+", help="recording directories to scan")
    parser.add_argument("--donor", help="use this file's init segment instead of auto-detect")
    parser.add_argument("--out", help="write recovered files into this directory")
    args = parser.parse_args()

    if args.out:
        os.makedirs(args.out, exist_ok=True)

    for d in args.dirs:
        if not os.path.isdir(d):
            print(f"error: not a directory: {d}", file=sys.stderr)
            sys.exit(1)
        recover(d, args.donor, args.out)


if __name__ == "__main__":
    main()
