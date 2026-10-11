NFS share
=========

An NFS export can be mounted at `/mnt/nfs` so recordings, logs, and build
artifacts land on a host instead of the camera's flash. Mounting is
event-driven (it happens when the interface that carries the route to the
server comes up) and it is **off by default**: the share address can be kept
in the configuration without mounting anything at boot.

Configuration
-------------

The settings live in the `nfs` object of `/etc/thingino.json`:

| Key       | Type    | Default | Description                                          |
|-----------|---------|---------|------------------------------------------------------|
| `enabled` | boolean | `false` | Mount the share when the network comes up.           |
| `share`   | string  | `""`    | NFS export as `host:/path`, e.g. `192.168.88.20:/nfs`. |

```
{
  "nfs": {
    "enabled": false,
    "share": "192.168.88.20:/nfs"
  }
}
```

Changing them from a shell:

```
jct /etc/thingino.json set nfs.share "192.168.88.20:/nfs"
jct /etc/thingino.json set nfs.enabled true
/etc/init.d/S43mounts restart
```

Older firmware stored the export in a top-level `nfs_share` string. That key is
no longer read; move the address to `nfs.share` and set `nfs.enabled`.

Enabling, disabling, and mounting now
-------------------------------------

`S43mounts` controls the mount at runtime:

| Command   | Action                                                                 |
|-----------|------------------------------------------------------------------------|
| `start`   | Mount the share if `nfs.enabled` is true; warn and do nothing if disabled. |
| `force`   | Set `nfs.enabled` to true and mount the share now.                     |
| `stop`    | Lazily unmount `/mnt/nfs`.                                             |
| `restart` | `stop`, then `start`.                                                  |

The script runs at boot (`rcS`), so `start` honours `nfs.enabled` and a
disabled share is not mounted. `force` is the shortcut for mounting a disabled
share without editing the file by hand; it persists `enabled: true`, so the
share also mounts on the next boot.

```
/etc/init.d/S43mounts force
```

How mounting works
------------------

- `if-up.d/mount_nfs` runs from `ifup`'s `run-parts` hook after the link is up
  and the address is configured. It mounts only when `nfs.enabled` is true and
  `nfs.share` is set, and only on the interface that carries the route to the
  server (checked with `ip route get <host>`), so a secondary link coming up
  first does not preempt it.
- `if-post-down.d/umount_nfs` lazily unmounts when the interface goes down. A
  lazy umount detaches immediately and lets in-flight writers drain instead of
  blocking the interface teardown.
- The mount uses `nolock,hard,timeo=30,retrans=2`. It is hard, not soft: a soft
  mount aborts a stalled write after about 9 seconds and returns `EIO`, which
  can corrupt recordings (1 MiB holes where the MP4 init segment lives). A hard
  mount blocks instead of losing data.

Diagnosis
---------

`S43mounts` logs through the shared `lib-log` helper, so boot-time mount
decisions are visible in syslog with the `S43mounts` tag:

```
logread | grep S43mounts
```

The `if-up.d/mount_nfs` hook writes console-only messages, which are not
forwarded to syslog:

```
- Mounted 192.168.88.20:/nfs on /mnt/nfs
```

A disabled share at boot logs a warning:

```
NFS mount is disabled (run '/etc/init.d/S43mounts force' to enable and mount)
```

See also
--------

- [Overlay filesystem](../firmware/overlayfs.md)
