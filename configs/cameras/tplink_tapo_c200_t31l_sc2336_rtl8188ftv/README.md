# TP-Link Tapo C200 (T31L revision)

Pan/tilt Wi-Fi camera. This profile covers the T31L hardware revision;
the existing `tplink_tapo_c200_t23n_sc2336p_rtl8188ftv` profile covers
the T23N revision. GPIO assignments were measured on hardware by
physically probing the stepper phases, then confirmed under Thingino.

## Hardware

- SoC: Ingenic T31L
- Sensor: SmartSens SC2336
- Wi-Fi: Realtek RTL8188FTV (USB)
- Flash: 8 MB SPI NOR
- Motors: open-loop steppers via a UTC2803M Darlington array (no SPI
  motor controller, no TCU/PWM)

## GPIO map (measured)

- 49: IR 850 nm LED
- 50: White light LED (active low)
- 51: Wi-Fi enable (wlan)
- 57/58: IR-cut pair ("58 57")
- 59: SD card detect (mmc_cd)
- 60: SD card power (mmc_power, active low)
- 62: Reset button (button_reset)

## PTZ

The board wires the pan/tilt steppers to plain GPIOs through a
UTC2803M Darlington array; nothing in stock firmware drove them via
TCU/PWM. Direction is handled by the gpio_tilt phase pin order, not
invert_y (matching the current convention):

- Pan: pins 39 45 46 40, steps 3900, speed 700
- Tilt: pins 38 48 47 41, steps 700, speed 700

Steps were measured against the mechanical stops of a specific unit;
they can vary between units, so recalibrate if travel looks off.
Home position (pan 1950, tilt 200) is what the daemon returns to on
`motors -d b` and after a homing sweep.

## Notes

- The C200 (T31L) board is closely related to the Tapo C500 (T31L)
  profile; the motor phase pins match. Pan travel measured on this
  unit is longer than the C500 default (3900 vs 2100 steps).
- Red and green indicator LEDs were verified on hardware (GPIO 42/43).
- There are no limit switches: homing sweeps into the mechanical
  stops. `homing` is set to false here because moving both axes at
  once (the startup homing sweep) can brown out the 5V rail on stock
  power supplies and reboot the camera; one-axis-at-a-time moves are
  fine. If your supply is solid, `jct /etc/thingino.json set motors.homing true`
  enables homing at startup.
- LED_G/LED_R GPIOs (42/43, inherited from the C100 T31L profile this
  was based on) were not verified on this unit.
