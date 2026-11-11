# Orno OR-MT-BT-1812

Pan/tilt Wi-Fi camera based on the Ingenic T31L. GPIO assignments were
reverse-engineered from the stock firmware and verified on hardware.

## Hardware

- SoC: Ingenic T31L
- Sensor: SmartSens SC3336 (chip id 0xcc41, i2c 0x30, native 2304x1296)
- Wi-Fi: ATBM6012BX
- Flash: 8 MB SPI NOR
- IR-cut: LK6208 dual-line driver (pulsed)
- Motors: stepper pan + tilt with homing

## GPIO map (measured)

- 6:  Wi-Fi / USB enable (net)
- 14: Reset button (button_reset; input, active-low)
- 16: IR-cut line 1 (LK6208 pin 8)
- 17: IR-cut line 2 (LK6208 pin 5)
- 18: Sensor reset
- 35: LED (green)
- 49: SD card detect (mmc_cd)
- 50: IR 850 nm LED
- 59: White light LED

IR-cut is the pair 16+17 via the LK6208; the ircut order "17 16" gives
correct polarity (engaged = colour/day, disengaged = mono/night).

GPIO 7 is present on the board but its function is not yet confirmed,
so it is intentionally left unmapped.

## PTZ

Legacy stepper driver. Direction was corrected by reversing the phase
pin order (invert_x / invert_y have no effect with the legacy driver).
Phase pins and homing match the closely related litokam_m1 board; steps
and speeds were tuned for this unit.

- Pan:  pins 54 52 53 64, steps 3128, speed 250
- Tilt: pins 61 62 63 51, steps 1024, speed 241

## How the GPIO map was measured

On the running stock firmware, not from a schematic:

- Register diff: /proc/jz/gpio/gpios dumps the GPIO registers. Toggle a
  function from the stock app, diff before/after to find the pin.
  Quieten the console first: echo 1 > /proc/sys/kernel/printk
- Datasheet cross-check: T31 QFN pins do not map linearly to GPIO
  numbers (e.g. package pin 14 -> PA17 -> GPIO 17).
- Physical confirmation: IR-cut by audible click and mono/colour
  switch; button and LEDs with a meter and gpio read.

T31 datasheet: https://www.mouser.com/datasheet/2/198/T31_ZL_DS-2399949.pdf
