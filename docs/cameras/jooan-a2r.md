Jooan A2R-U
===========

### Hardware

- SoC: Ingenic T23N (64MB)
- Image Sensor: SmartSense SC1A4T (1MP)
- Wi-Fi Module:
  - AltoBeam ATBM6012BX (USB)
  - SSC6355 (USB)
- Flash Chip: NOR 8MB (25Q64)
- Power: 5V DC (USB-C)

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

### Motors

```
  Tilting motor       Panning motor
[ +  *  *  *  * ]   [ +  *  *  *  * ]
  C  14 54 52 53      C  14 54 52 53
```

Both motors are controlled by the same GPIO pins: 14, 52, 53, 54.
Setting the GPIO 17 to Hi or LOW switches the active motor.
When the GPIO 17 is set to Hi, the tilt motor is active.
When the GPIO 17 is set to LOW, the pan motor is active.
When the GPIO 17 is floating (not connected), both motors are active.
