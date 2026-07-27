Jooan A12
=========

### Hardware

- SoC: Ingenic T23N
- Image Sensor: 2 x SmartSense SC2336 (2MP)
- Wi-Fi Module: AltoBeam ATBM6132BU (USB)
- Flash Chip: NOR 8MB (25QH64DHIQ)
- Ethernet Port
- SD Card
- Power: 5V DC (USB-C, no data)

### Installation

Installation of thingino can be done without opening the device using [jooan-updater](https://github.com/peak3d/jooan-updater) script or by opening the device and burning the flash chip.
The usb-c port cannot be used because of missing data wires.

### UART

UART connection pads are tiny copper dots on the front side of the PCB, near the SoC.
Take GND from any of the outer coppered screw holes.
The pads are not marked, but here's the mapping:

```
       ----------    GND ()
      |          |
      |    SD    |
RX TX |   CARD   |
() ()  ----------
      ---------
     |         |
     |   SoC   |
     |   T23   |
     |         |
      ---------
```
