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

**user/overlay/**

Files from this directory will go into a writable overlay parition of the final image. These files can be
edited or deleted on the camera, and these changes are permanent. Think of these files as of the first
round of editing done on the camera itself.

Please note, files from upper overlay are not part of the rootfs partition, and they are not packed into
the .tar bundle or rootfs.squahsfs files in the output images/ directory! Instead, these files end up in
the config.jffs2 partition image.

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

