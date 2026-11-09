OVERLAYFS
---------

Overlayfs consists of a lower permanent layer of files on a read-only partition and an uppper writable
layer where newer files are added or newer versions of existing files shadows older underlaying versions
giving you an illusion of a writable userland.

### Layers

It is very crucial to understand the firmware layers and carefully plan for any additions and changes.
E.g. your compile a package and you want to make changes to its installable configuration file.
You could create a patch file that would change the config file _before+ compilation, you could use a
hook in the package's makefile to make changes _after_ the compilation using sed or other useful utils,
or you could use the overlay with replace the entire file with your own version.

### Why subdirectories?

**overlay/**

Files from this directory will go into the final image overriding those created during compilation time.
E.g. Dropbear package installs /etc/init.d/S50dropbear file into target directory of the fimrware, but
that is not the versions what we need in Thingino, so we place our own version of the file into overlay
as overlay/etc/init.d/S50dropbear and it replaces the one installed by the package in the final
image assembly, on the permanent read-only partition. These files can be restored when deleted edited
on the camera.

**user/common/overlay/**

Files from this directory will go into a writable overlay parition of the final image. These files can be
edited or deleted on the camera, and these changes are permanent. Think of these files as of the first
round of editing done on the camera itself.

Camera-scoped and device-scoped user overlays follow the same pattern:

- `user/<camera>/overlay/`
- `user/<camera>/<ip>/overlay/`

Please note, files from user overlay are not part of the rootfs partition, and they are not packed into
the .tar bundle or rootfs.squahsfs files in the output images/ directory! Instead, these files end up in
the data.jffs2 partition image, as the overlayfs upperdir covering the full filesystem.

### On-device layout

Both overlay drivers use the same upperdir, and the workdir (mainline kernels only)
is its sibling:

```
DATA/root/   overlayfs upperdir
DATA/work/   overlayfs workdir (mainline kernels only, created at boot)
```

During early boot the partition is mounted at `/overlay`, so both layers are visible
there. After the pivot the partition root is moved to `/overlay` and the upperdir is
bind-mounted over it, so on a running camera `/overlay` shows the upper layer only:
`/overlay/etc/foo` is the upper of `/etc/foo`, `/overlay/root` is the upper of
`/root`. The workdir is no longer reachable by path once the bind is in place; the
kernel holds it from mount time.

This is the contract every writer relies on. `jct /etc/foo restore` unlinks
`/overlay/etc/foo` to expose the ROM copy, `wlan.in` removes
`/overlay/etc/wpa_supplicant.conf`, `S44devmounts` removes `/overlay/var/www`, and
overlay backup/restore tars `/overlay`. The contract is identical on the 3.10 legacy
driver and the mainline driver; the two differ only in the mount line.

A partition written by an older build may hold a flat upperdir at the partition root
instead. On first boot it is folded under `root/` exactly once, marked with
`DATA/.overlay-migrated`. A `root/` or `work/` entry on the legacy driver is the
upper of `/root` or `/work`, so it is shuffled inside the container rather than
consumed as it.

### Size limits

Our overlay partition is not large but should be enough for basic changes to the camera configuration.
For storing large files use an SD card or mount an NFS share.


### How to use

```
mount -t overlayfs overlay -o lowerdir=/lower2:/lower1,upperdir=/upper,workdir=/work /mnt
```

**lowerdir**:
	A colon-separated list of directories that serve as read-only layers, the last one listed
	will be the bottom-most layer (/lower2 will overlay /lower1).

**upperdir**:
	The writable layer where changes are made.

**workdir**:
	A directory used by OverlayFS for internal operations;
	must be on the same filesystem as upperdir.

**/mnt**:
	The mount point where the combined filesystem will be accessible.

