Jooan A12
=========

The A12 ships in more than one hardware revision, with different sensors and
Wi-Fi modules. Check which one you have before installing.

### Hardware

#### SC2336 revision

- SoC: Ingenic T23N
- Image Sensor: 2 x SmartSense SC2336 (2MP)
- Wi-Fi Module: AltoBeam ATBM6132BU (USB)
- Flash Chip: NOR 8MB (25QH64DHIQ)
- Ethernet Port
- SD Card
- Power: 5V DC (USB-C, no data)

#### CV2005 revision

- SoC: Ingenic T23N
- Image Sensor: 2 x CV2005 (2MP), on I2C-0: `cv2005` at 0x35, `cv2005s1` at 0x36 (chip id 0x2005)
- Wi-Fi Module: SeekWave SV6160LITE / SKW6316 (USB, ID 3607:6621), see the [wifi-swt6621s](../../package/wifi-swt6621s/README.md) package
- Flash Chip: NOR 8MB
- Stock firmware: model `JA-A12`, Linux 3.10.14 (isvp_pike), sensor modules `sensor_cv2005_t23` and `sensor_cv2005s1_t23`

Seen on the one unit documented here, not confirmed on others: PCB marked
`JA-6621 V1.0`, flash chip Puya P25Q64HA.

**Not supported yet.** Thingino has no CV2005 sensor driver for the T23:
[thingino/ingenic-sdk](https://github.com/thingino/ingenic-sdk/tree/main/3.10.14/sensor-src/t23)
has CV2005 drivers only for the T32 and T33.

### Installation

The methods below are for the SC2336 revision. The model name alone has not
been shown to tell the revisions apart: the CV2005 unit's stock firmware
reports `JA-A12`, and jooan-updater builds its package for a model name
(`A12`), not for a hardware revision. Reading the sensor and Wi-Fi module
markings inside the camera is the reliable check.

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
