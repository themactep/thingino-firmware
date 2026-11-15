LittlElf LF-P1T (Litokam M1 board, SC2336)
==========================================

Indoor pan/tilt Wi-Fi camera sold as **LittlElf LF-P1T** (also listed under the
Litokam brand). Inside is the same "M1" board as the existing
`litokam_m1_t31l_sc3336_atbm6012b` profile, but this unit ships with a
**SmartSens SC2336** image sensor instead of the SC3336. Both sensors are used in
the same retail model, so check which one your camera has before flashing.

Profile: `litokam_m1_t31l_sc2336_atbm6012b`

### Hardware

- SoC: Ingenic T31L, 64 MB RAM (≈34 MB available to Linux)
- Image sensor: SmartSens SC2336 (2 MP, 1920×1080), mounted upside down (`shvflip=1`)
- Wi-Fi: AltoBeam ATBM6012B (USB, VID:PID 007a:8888)
- Flash: Winbond W25Q64 SPI NOR, 8 MB
- Pan/tilt: two stepper motors (pan 3700 steps, tilt 1000 steps)
- IR LEDs (850 nm) with IR-cut filter, white LED
- Microphone and speaker, microSD slot, reset button

### GPIOs

Same as the SC3336 variant of the M1 board:

| Function       | GPIO          |
|----------------|---------------|
| Reset button   | 18            |
| IR 850 nm      | 50            |
| IR-cut         | 10 / 11       |
| White LED      | 9             |
| Speaker enable | 60            |
| SD detect      | 49            |
| Wi-Fi (net)    | 39, active low |
| Pan motor      | 54 52 53 64   |
| Tilt motor     | 61 62 63 51   |

### Which sensor do I have?

The stock firmware prints the detected sensor in its boot log on the UART.
After flashing Thingino, `cat /proc/jz/sensor/name` shows it as well.
If the image stays black with the SC3336 profile, the camera most likely has
the SC2336 and needs this profile (and vice versa).

### Installation

The unit described here was flashed with a CH341A programmer and a SOIC-8 clip
on the W25Q64 chip:

1. Read the stock firmware twice and compare the dumps; keep the backup.
2. Write `thingino-litokam_m1_t31l_sc2336_atbm6012b.bin` to the chip.
3. Power the camera; it starts the Thingino Wi-Fi portal for setup.

Tested on this unit (SC2336 driver on the M1 board): video on main and sub
stream (H.264), audio (AAC), pan/tilt with homing and presets, IR and white
LED, motion detection via MQTT.
