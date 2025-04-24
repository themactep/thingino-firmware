Jooan Q3R
=========

### Hardware

- SoC: Ingenic T23N (64MB)
- Image Sensor: SmartSense SC1A4T (1MP)
- Wi-Fi Module: AltoBeam ATBM6012BX (USB)
- Flash Chip: NOR 8MB (25Q64)
- Ethernet: RTL8201CP (PHY)
- Power: 5V DC (1ft cable USB-C)

### Installation


### UART

UART connection pads are tiny copper dots on the back side of the PCB, near the
SoC. The pads are not marked, but here's the mapping:

```
                  GND ()

                  RX
               TX ()
               ()
-------------
             |
   SoC       |
   T23       |
             |
```
