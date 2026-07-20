# Wyze Floodlight v2 hardware notes

The camera definition and device tree were recovered from the stock
`wyze_floodlightv2C.bin` backup (Wyze product `HL_CAM3P`, app 4.53.3.9759).
The stock firmware identifies the platform as T41 `isvp_marmot` and runs a
4.4.94 kernel.

## Hardware

| Component | Stock evidence and Thingino setting |
|-----------|--------------------------------------|
| SoC | The stock board strings cover the T41 family and the firmware loads the NPU and AVPU modules. Thingino selects T41NQ to match the NPU-capable variant and the related Wyze Cam v4. |
| Sensor | GalaxyCore GC3003A, two-lane MIPI, 2304x1296 at 30 fps, I2C0 address 0x37, and 27 MHz MCLK. Stock loads `sensor_gc3003a_t41.ko shvflip=1`. |
| ISP/encoder | Stock loads `tx-isp-t41` with `isp_memopt=1 direct_mode=1 ivdc_mem_line=540`, and configures the AVPU for a 552 MHz `sclka` clock. Thingino uses the nearest 550 MHz option. |
| Wi-Fi | AltoBeam ATBM603x SDIO on non-removable MSC1. The stock 2.4 GHz-only gain table identifies it as an ATBM6031. |
| Storage | 16 MB SPI NOR on SFC0, plus an SD card on MSC0. The SD card uses active-low card detect on GPB26 (GPIO 58) and power on GPB29 (GPIO 61). |
| Console | UART1 on the `uart1-pb` pin group, exposed as `/dev/ttyS1`. |

The Thingino reserved-memory values are inherited from the Wyze Cam v4 because
it uses the same SoC. The stock firmware confirms `isp_memopt=1`, but not those
exact reserved-memory sizes.

## Device-tree details

The MSC1 `max-frequency` value of 10 MHz and `enable_cpm_tx_tuning` property in
`board/ingenic/dts/wyze_floodlightv2_t41nq.dts` are preserved from the stock
device tree.

Wi-Fi reset is GPC8 (GPIO 72). It is described by the MSC1
`mmc-pwrseq-simple` node so the reset is sequenced as part of bringing up the
SDIO device. The Ingenic 4.4 power-sequence driver requests the GPIO before
userspace and drives 0 before power-on followed by 1 after power-on. For that
reason, the device tree uses active-high GPIO flags even though the physical
reset signal is active-low. UART0 must remain disabled because its `uart0-pc`
pin group also claims GPC8.

## SoC GPIO map

The following map was recovered from the stock `iCamera` dynamic symbols,
`g_gpioParaMap`, and the `gpio_read`/`gpio_write` call sites.

| GPIO | Function | Evidence or behavior |
|-----:|----------|----------------------|
| 38 | Status LED B | Second argument to the stock status-LED function. |
| 39 | Status LED A | First argument to the stock status-LED function; boot level is 1. |
| 49 | IR-cut B | Driven 100 ms after GPIO 50 by the stock IR-cut function. |
| 50 | IR-cut A | First output driven by the stock IR-cut function. |
| 57 | Auxiliary SD detect | Named `sd_cd_ex_pin` by the stock application. |
| 58 | Kernel SD card detect | Active-low GPB26 in the stock device tree. |
| 59 | Application SD card detect | Read by the stock `sdk_device_check_mmc_insert` path. |
| 61 | SD card power | GPB29. |
| 62 | Reset button | Active-low input. |
| 63 | Speaker amplifier enable | Used by the stock speaker PA control function. |
| 72 | Wi-Fi reset | GPC8, owned by the MSC1 power-sequence node. |
| 81 | 850 nm IR LED | Driven by the stock IR LED function. |

The apparent GPIO 60 and 79 references are coincidental constants rather than
GPIO writes. Three `-1` entries in the stock map represent unpopulated
functions.

## Floodlight controller

The floodlight LEDs, three-zone PIR array, and siren are not connected to SoC
GPIOs. They are managed by an external CH554 MCU over `/dev/ttyS2` (UART2 on
GPC13/14 and GPC19/20) at 115200 8N1. Thingino therefore controls those
features in userspace with `floodlightd` while the device tree enables UART2.

See `docs/wyze-floodlightv2-mcu-protocol.md` for the serial protocol and
`docs/wyze-floodlightv2-floodlightd.md` for daemon operation.
