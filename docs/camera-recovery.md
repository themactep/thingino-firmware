Recovery of a bricked camera
============================

with a programmer
-----------------

The camera can be recovered by flashing the firmware using a programmer and a
programming clip. Connect the programmer to the camera's SPI flash chip and
flash the firmware using the [programmer's software][snander].

with an SD card
---------------

If the camera already has Thingino bootloader, you can recover it by flashing
new firmware from a FAT32 SD card. The firmware should be in a file named
`autoupdate-full.bin`. Insert the SD card into the camera and power it on. The
camera will automatically flash the firmware.

If camera bootloader is not working, you can try to recover it by booting the
camera from an SD card. Prepare such a card by flashing a bootloader image
from the [Thingino bootloader repository][uboot-msc0] to it. Insert the card
into the camera, short `BOOT_SEL` pin to `GND` and power the camera on.

with Ingenic Cloner
-------------------

If the camera has a USB port with data lines connected to the Ingenic SoC, it
can be recovered using the [Ingenic Cloner tool][cloner]. Connect the camera to
a computer using a USB cable with data lines (the cable included with the camera
usually is power-only) and run the cloner tool. Short pins 5 and 6 on the flash
chip to initiate cloner mode.

If you still have access to the camera, you can trigger cloner mode by
invalidating bootloader partition and rebooting the camera. This can be done
from linux
```
flash_erase /dev/mtd0
reboot -f
```
or from bootloader shell
```
sf erase 0 0x10000
reset
```


[cloner]: https://thingino.com/cloner
[snander]: https://github.com/themactep/snander
[uboot-msc0]: https://github.com/gtxaspec/ingenic-u-boot-xburst1/releases
