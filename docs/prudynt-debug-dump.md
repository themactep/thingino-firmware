Prudynt debug dump
==================

When a client sends malformed or oversized data to the RTSP port, prudynt
silently resets its read buffer and carries on.  The ``rtsp.debug_dump_path``
config key writes those payloads to **persistent storage** so you can
diagnose which client is misbehaving.

Configuration
-------------

Set ``general.debug_dump_path`` in ``prudynt.json`` to a directory on an
external mount (NFS share or SD card)::

    {
      "general": {
        "debug_dump_path": "/mnt/nfs/prudynt-debug"
      }
    }

- Leave the key unset or empty to disable dumps (the default).
- The directory must exist and be writable — prudynt creates per-camera
  subdirectories automatically, but the base path must already be mounted.
- ``/tmp`` works for short-term debugging but is lost on reboot.

Dump layout
-----------

Each camera gets its own subdirectory named by its local IP::

    /mnt/nfs/prudynt-debug/
      192.168.88.33/
        overflow-20260802-024610-192.168.88.100-45678.bin
        overflow-20260802-030900-10.0.0.5-52341.bin
      192.168.88.42/
        ...

Filename pattern::

    overflow-YYYYmmdd-HHMMSS-<remote-ip>-<remote-port>.bin

This makes it easy to see **which camera** received garbage from **which
client** at **what time**.

Inspecting dumps
----------------

Use ``file`` to guess the protocol, then ``xxd`` or ``hexdump`` for the raw
bytes::

    file prudynt-debug/192.168.88.33/overflow-*.bin
    xxd prudynt-debug/192.168.88.33/overflow-*.bin | head -20

Common scenarios
----------------

- **``Request too large`` every ~22 minutes** — typically an external
  service (Home Assistant, Frigate, network scanner) probing port 554 with
  non-RTSP data.  The dump reveals what protocol it sent.
- **Frequent small overflows** — may indicate a keepalive mechanism sending
  raw data instead of ``OPTIONS`` or ``GET_PARAMETER``.

When ``debug_dump_path`` is not configured (the default), prudynt logs a
warning with the caller's IP, port, and total bytes without touching the
filesystem.

Related
-------

- :doc:`streamer` — RTSP stream recording and metadata
- :doc:`diagnostics` — general camera diagnostics
