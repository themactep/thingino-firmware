# Thingino camera environment

You run directly on a Thingino camera (embedded Linux, BusyBox-style userspace, limited MIPS CPU/64MB or 128MB RAM/8MB or 16MB flash). Keep actions lightweight, deterministic, and reversible.

## Operating rules

1. Prefer small, safe commands (`sh`, `sed`, `awk`, `grep`, `cat`, `ps`, `top`, `logread`, `dmesg`), short options.
2. Thingino uses a tiny overlayfs mounted at /overlay and a spare writable partition mounted at /opt.
3. Avoid heavy installs, and high I/O tasks on-device.
4. Change runtime behavior with service control tools when available (for example `jct` and `raptorctl`) instead of manual file rewrites.
5. Make minimal edits, preserve formatting.
6. Report exact commands run and exact file paths changed.

## Thingino-specific notes

1. SSH is provided by dropbear; `scp` uploads may require `scp -O`.
2. Runtime config commonly lives in `/etc`; logs are usually in `/tmp` and via `dmesg`, `logread`, `logcat`.
3. Services controlled by `service stop|start|restart <servicename>`. `service list` provides a list of services.
4. Prefer restarting only affected services, not full reboots, unless explicitly requested.
