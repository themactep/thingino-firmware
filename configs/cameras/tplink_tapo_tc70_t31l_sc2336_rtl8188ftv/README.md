# TP-Link Tapo TC70 / Tapo C200 (T31L revision)

Pan/tilt Wi-Fi camera. The TC70 and the Tapo C200 (T31L hardware
revision) are the same board: Ingenic T31L, SmartSens SC2336,
Realtek RTL8188FTV, 8 MB SPI NOR. The existing
`tplink_tapo_c200_t23n_sc2336p_rtl8188ftv` profile covers the older
T23N C200 revision.

This profile was originally submitted from the TC70 side and has since
been re-verified and recalibrated against a physically measured C200
(T31L) unit - the first thingino build known to drive its motors.

## Hardware

- SoC: Ingenic T31L
- Sensor: SmartSens SC2336
- Wi-Fi: Realtek RTL8188FTV (USB)
- Flash: 8 MB SPI NOR
- Motors: open-loop steppers via a UTC2803M Darlington array on plain
  GPIOs (no SPI motor controller, no TCU/PWM)

## GPIO map

- 42/43: green/red indicator LEDs (from the original TC70 submission;
  not re-verified on the C200 unit)
- 49: IR 850 nm LED (measured)
- 50: white light LED, active low (measured)
- 51: Wi-Fi enable / wlan (measured)
- 57/58: IR-cut pair, "57o 58o" (both pins active low; the `o` suffix
  is deliberate and kept from the original profile)
- 59: SD card detect / mmc_cd (measured on the C200 unit)
- 60: SD card power / mmc_power, active low (measured on the C200
  unit)
- 62: reset button (measured)
- 63: speaker (from the original TC70 submission)

Sensor mode: `data_interface=1 shvflip=1` (measured on the C200 unit).

## PTZ

Phase pins were measured by physically probing the stepper coils and
confirmed under thingino:

- Pan:  pins 39 45 46 40, steps 3900, speed 700
- Tilt: pins 38 48 47 41, steps 700, speed 700

Tilt direction is set by the `gpio_tilt` phase pin order, not
`invert_y` (matching the current convention). Steps were measured
against the mechanical stops of one unit and can vary between units;
recalibrate if travel looks off.

`homing` defaults to false: the startup homing sweep moves both axes
at once, which can brown out the 5V rail on stock power supplies and
reboot the camera (reproduced on the original TP-Link supply).
One-axis-at-a-time moves are fine. With a solid supply, enable it with
`jct /etc/thingino.json set motors.homing true`. The stored home point
(pan 1950, tilt 200) is what `motors -d b` returns to.

## How the GPIO map was measured

On the running stock firmware and confirmed under thingino, following
the method documented in
`configs/cameras/orno_or_mt_bt_1812_t31l_sc3336_atbm6012bx/README.md`:
register diffing of /proc/jz/gpio/gpios while toggling each function
from the stock app, datasheet cross-check, and physical confirmation
(motor coil probing, meter on LEDs and button).
