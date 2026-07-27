Bootloader
==========

U-Boot
------

- https://github.com/u-boot/u-boot

### Booting from SD card

Insert a micro SD card into a reader, create a new partition and format it to vfat.

```
card=/dev/sdf

sudo umount $card
echo -e "o\nn\np\n\n\n\nw\nq\n" | sudo fdisk $card
sync
```

reinsert the card

```
sudo umount ${card}1
sudo mkfs.fat ${card}1
sudo dd if=u-boot-with-spl.bin of=$card bs=1024 seek=17
sync
```

Note, that you use the card device pe se as the target, not a partition on it.

```
fatload mmc 0 0x82000000 u-boot-with-spl.bin
bootm 0x82000000
```

