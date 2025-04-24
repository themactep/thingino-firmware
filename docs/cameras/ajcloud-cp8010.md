AJ Cloud CP8010
===============

Manufactured by WESECUU, sold under brand names AJ Cloud, GBIUT, ILWUT etc.

- https://www.amazon.ca/Security-360°Home-Monitor-Surveillance-Interieur/dp/B0D929RPZS?th=1
- https://www.amazon.ae/GBIUT-Security-Cameras-Wireless-Storage/dp/B0DL5JVR56

### Hardware

- SoC: Ingenic T23N (64MB)
- Image Sensor: SmartSense SC2336 (2MP)
- Wi-Fi Module: AltoBeam ATBM6132BU (USB, 2.4GHz+5GHz)
- Flash Chip: NOR 8MB (25Q64)
- Power: 5V DC (USB-C connector)

### Installation

#### Programmer method

1. Undo three screws on the back of the camera ball.
2. Remove the back cover.
3. Remove the PCB from the camera ball.
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
-------------+
             |--------
             |        \
   SD CARD   | ()TX    \
             |    ()GND \
             | ()RX     |
             |          |
-------------+          |
                        |
----------              |
          |             |
    SoC   |             |
    T23   |             |
          |             |
```

### Motors

```
  Tilting motor       Panning motor
[ +  *  *  *  * ]   [ +  *  *  *  * ]
  C  59 52 53 64      C  61 62 63 49
```
