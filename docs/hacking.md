Hacking
=======

### How to get a copy of live BootROM

From U-Boot shell, dump the content of BootROM in memory to an SD card.

```
mmc dev 0
mmc erase 0x0 0x4000
mmc write 0x1FC00000 0x0 0x4000
```

Then on your desktop, transfer the saved data to a file:

```
sudo dd if=/dev/sdc bs=16384 count=1 of=bootrom.bin
```

### How to extract FIT-image

```
dumpimage -l image.ub
```

### .hex files

These are `ar` archives. List the content of the file with
`ar -t <filename>` and unpack it with `ar -x <filename>`.
