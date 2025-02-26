Pesita X09
==========

https://www.amazon.ca/dp/B0B6J5TZJB

### Hardware

- SoC: Ingenic T31N (64 MB)
- Image Sensor:
	- JXF23 (2MP)
- Wi-Fi Module: RTL8189FTV (SDIO)
- Flash Chip: NOR 16MB
- Power: 5V DC microUSB

### Installation

1. Rotate the ball all the way face down, remove rubber plug and undo a single screw on the back of the ball.
2. Slightly squeeze the ball from sides and use a guitar pick to split the ball open.
3. Undo two screws holding the PCB to get access to the flash chip on the front side of the PCB.
3. Clip the flash chip and use a CH341A programmer to install the firmware.

### UART

UART contacts are available as 1.27mm pitch holes near the vertical motor
terminals, marked `R`, `T`, and `G`.

### Motors

Motor terminals are 1.5mm pitch JST-ZH 5-pin connectors.

### Notes

My unit had a low quality soldering. Both motor terminals came off the PCB when
I tried to unplugged them. I had to re-solder them back.
