OverlayFS
=========

```
mount -t overlayfs overlay -o lowerdir=/lower2:/lower1,upperdir=/upper,workdir=/work /mnt
```

**lowerdir**:
	A colon-separated list of directories that serve
 	as read-only layers, the last one listed will be
 	the bottom-most layer (/lower2 will overlay /lower1).

**upperdir**:
	The writable layer where changes are made.

**workdir**:
	A directory used by OverlayFS for internal operations;
	must be on the same filesystem as upperdir.

**/mnt**:
	The mount point where the combined filesystem will be accessible.
