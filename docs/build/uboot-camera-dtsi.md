# Per-camera U-Boot device tree

U-Boot (2026.10 tree) builds one device tree per SoC, describing the
Ingenic reference board. A camera that wires something differently puts
its overrides in `configs/cameras/<camera>/u-boot.dtsi`. The build passes
that file to U-Boot's `CONFIG_DEVICE_TREE_INCLUDES`, which appends it after
the SoC tree, so it overrides both the SoC tree and the values thingino
injects from `thingino.json`.

The file is plain DTS that refers to nodes by their label:

```dts
// SPDX-License-Identifier: GPL-2.0+

#include <dt-bindings/gpio/gpio.h>

&gmac_phy {
	reset-gpios = <&gpc 0 GPIO_ACTIVE_LOW>;
};
```

Cameras without the file build exactly as before. The 2013.07 tree has no
device tree and ignores the file.

## Ethernet PHY reset

The wired PHY sits under the MAC's MDIO bus with the standard
`ethernet-phy` reset properties. U-Boot pulses `reset-gpios`, holding it
for `reset-assert-us` and waiting `reset-deassert-us` afterwards.

| SoC            | PHY label   | Reference default                 |
|----------------|-------------|-----------------------------------|
| T23, T30, T31  | `gmac_phy`  | PB28, active low, 50 ms / 10 ms   |
| A1             | `gmac0_phy` | PC18, active low, 15 ms / 80 ms   |

- Another pin: override `reset-gpios`, as above.
- Different timing: override `reset-assert-us` / `reset-deassert-us`.
- No reset line wired: `&gmac_phy { /delete-property/ reset-gpios; };`, so
  U-Boot never drives a pin the board uses for something else.

GPIO banks are labelled `gpa`, `gpb`, `gpc`, ... with the pin number inside
the bank: Linux GPIO 64 is `<&gpc 0 ...>`.
