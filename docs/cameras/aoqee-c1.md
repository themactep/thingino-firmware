AOQEE C1
========

https://aoqee.com/C11pack

### Hardware

- SoC: Ingenic T23N (64MB)
- Image Sensor: SmartSense SC2336 (2MP)
- Wi-Fi Module: AltoBeam ATBM6062 (USB)
- Flash Chip: NOR 8MB (25Q64)
- Power: 5V DC (cable with USB-A connector)

### Installation

#### Programmer method

1. Open the rubber cover at the side of the camera and undo the screw.
2. Squash the camera body from sides and insert a guitar picker at the bottom
   part of the front cover, gentry pry the picker to remove the cover.
3. Undo the screws holding the PCB to get access to the flash chip on the back
   side of the PCB.
4. Clip the flash chip and use a CH341A programmer to install the firmware.

#### UART + SD card method

1. Download a firmware image from the [Thingino website](https://thingino.com/).
2. Copy the image to a FAT32 formatted SD card as `thingino.bin`.
3. Connect the UART contacts to a USB to TTL adapter.
4. Power the device and interrupt the boot process to get to the U-Boot prompt.
5. Run the following commands line by line to flash the firmware.
   ```
   setenv baseaddr 0x82000000;
   setenv partsize 0x800000;
   mw.b ${baseaddr} 0xff ${partsize};
   fatload mmc 0:1 ${baseaddr} thingino.bin;
   sf probe 0;
   sf erase 0x0 ${partsize};
   sf write ${baseaddr} 0x0 ${filesize};
   reset
   ```

### UART

```
---------------------
 TX RX         GND    \
 () () [==] [] ()      \
--------------         |
             |         |
   SoC       |         |
   T23       |         |
             |         |
```
