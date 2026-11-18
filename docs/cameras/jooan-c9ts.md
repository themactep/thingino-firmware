Jooan C9TS
==========

### Hardware

- SoC: Ingenic T23N (64MB)
- Image Sensor: SmartSens SC2336P / SC2335P (2MP)
- Flash Chip: SPI NOR 8MB (25Q64 / PY25Q64HA)
- Power: 5V DC (USB-C)

#### Wi-Fi Variants

1. **AltoBeam ATBM6132U (USB)**:
   - Config: `jooan_c9ts_t23n_sc2336p_atbm6132u_defconfig`
   - Driver: `atbm6132u`
2. **SeekWave SKW6621S / SV6160 (USB `3607:6621`)**:
   - Config: `jooan_c9ts_t23n_sc2336p_skw6316_defconfig`
   - Driver: `wifi-skw6316` (`skw_usb_lite.ko`, `skw6316.ko`)
   - Requires `modem_enable_gpio=6` and memory compaction for 352KB IRAM firmware allocation

### GPIO Pinout

- `GPIO 6`: Wi-Fi power enable (`wlan.pin`)
- `GPIO 17`: Motor selector (HIGH = Tilt, LOW = Pan)
- `GPIO 49, 50`: IR cut filter
- `GPIO 51, 52, 53, 54`: Stepper motor coils (shared pan/tilt)
- `GPIO 59`: IR 850nm night vision LED
- `GPIO 60`: White spotlight LED
- `GPIO 61`: MicroSD card detect (`mmc_cd`)
- `GPIO 62`: Reset button (`button_reset`, active low)
- `GPIO 63`: Audio amplifier enable (active low)

### Installation

#### Flashing via UART and MicroSD Card

1. Download or build the Thingino firmware image for `jooan_c9ts_t23n_sc2336p_skw6316`.
2. Format a MicroSD card as FAT32 and copy the full firmware image to the card root as `autoupdate-full.bin`.
3. Connect a USB-to-UART adapter to the camera's UART pads (115200 baud, 8N1, 3.3V).
4. Power on the camera.
5. **Interrupt U-Boot Autoboot:**
   - The vendor U-Boot does **not** interrupt with space or Enter. Send **`Ctrl+Q`** (`0x11` / ASCII 17) repeatedly right after applying power.
   - When prompted for `password:`, enter:
     ```
     c029bdbdd4b958c8e83d8dd080ccc080
     ```
     *(Secondary fallback password if needed: `c081e8d4d4e929bdc885b958cc8de8d0`)*
6. At the `isvp_t23#` prompt, flash the full image to SPI NOR flash:
   ```sh
   mmc rescan
   fatload mmc 0:1 0x80600000 autoupdate-full.bin
   sf probe 0
   sf erase 0x0 0x800000
   sf write 0x80600000 0x0 0x800000
   reset
   ```
7. After reboot, Thingino will boot. Connect to serial or the Wi-Fi setup AP (`THINGINO-...`), log in with `root`, and set your initial password.

> [!NOTE]
> The stock factory Linux OS has a locked root password hash in `/etc/shadow`. Accessing the stock factory OS console requires appending `init=/bin/sh` to `bootargs` from U-Boot, or flashing Thingino directly as outlined above.

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
  C  51 54 52 53      C  51 54 52 53
```

Both motors are controlled by the same GPIO pins: 51, 52, 53, 54.
Setting the GPIO 17 to Hi or LOW switches the active motor.
When the GPIO 17 is set to Hi, the tilt motor is active.
When the GPIO 17 is set to LOW, the pan motor is active.
When the GPIO 17 is floating (not connected), both motors are active.
