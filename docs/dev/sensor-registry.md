# Sensor registry (/proc/jz/sensor)

The ISP publishes an indexed sensor registry under `/proc/jz/sensor`. It
replaces the per-driver flat tree as the source of truth for sensor identity
and live state. Consumers (`rvd`, the `sensor` CLI, the webui CGIs) read it
before and after a sensor is bound.

## ABI

`sensorN` is a stable slot, not a dense index. A removed sensor leaves a hole;
slots are never renumbered while the ISP is loaded. Enumerate by globbing
`sensorN/` or read `/proc/jz/sensor/count`.

Each slot directory holds:

| File | Meaning |
|------|---------|
| `name` | driver/sensor name |
| `chip_id` | chip ID (hex, `0x...`) |
| `i2c_addr` | live client address, or the pre-bind default |
| `i2c_adapter` | adapter number |
| `width`, `height` | configured mbus geometry |
| `fps` | configured fps |
| `status` | `loaded` (pre-bind) or `active` (bound) |

Families that carry board wiring in `tx_isp_sensor_register_info` (T40/T41)
also publish `min_fps`, `max_fps`, `mclk`, `boot`, `video_interface`,
`rst_gpio`, `pwdn_gpio`. A value that is not yet knowable reads as an empty
file, never a placeholder: consumers treat empty as "fall back to defaults".

Registration is two-stage, driven from the hooks in
`common/isp/<soc>/include/sensor-common.h`:

1. driver load (`private_i2c_add_driver`) publishes name and i2c address, the
   two values a streamer needs before `IMP_ISP_AddSensor` creates the client.
2. probe (`tx_isp_subdev_init`) binds the live `tx_isp_sensor`, after which
   every read reports actual state.

## Build wiring

Two registries publish the same ABI, chosen per build:

- `SENSOR_PROC_OWNED_BY_ISP` (open stack): the registry is
  `open-tx-isp/driver/common/tx_isp_sinfo.c`, compiled into the open tx-isp
  module.
- `SENSOR_REGISTRY_IN_SDK` (proprietary/blob): the registry is
  `common/isp/common/tx-isp-sinfo.c`, compiled into the SDK's per-family
  tx-isp module (`common/isp/<soc>/Kbuild`). Enabled per family in
  `package/ingenic-sdk/ingenic-sdk.mk`.

`SENSOR_PROC_PUBLISH_FLAT_TREE` keeps the vendor flat tree published by
`common/sensor/common/sensor-info.c` alongside the registry. The proprietary
build keeps it because prudynt resolves the sensor through the flat
`/proc/jz/sensor/{width,height,max_fps,min_fps}` files; the registry alone does
not carry min/max fps on T23.

## Per-family status

| Family | Registry source | State |
|--------|-----------------|-------|
| t23 | SDK (`SENSOR_REGISTRY_IN_SDK`) | validated on hardware (Sonoff B1P, sc2337p) |
| t31 | SDK (`SENSOR_REGISTRY_IN_SDK`) | validated on hardware (Wyze Cam v3, gc2053) |
| t40 | SDK (`SENSOR_REGISTRY_IN_SDK`) | builds (eufy T8416, sc830ai+sc3338); kernel partition overflow warning |
| t41 | SDK (`SENSOR_REGISTRY_IN_SDK`) | builds (wyze_cam4, os04d10); hardware validation pending |

## Notes

- The registry lives in the tx-isp module, which loads before any sensor
  module (sensors depend on its symbols). Its `/proc/jz/sensor` directory is
  therefore created first; `sensor_common_init`'s later `proc_mkdir` of the
  same path returns the existing entry and its flat files land under it.
- Old and new cannot coexist when both claim the same slot name. For the
  proprietary build the registry owns `sensorN/` and `count`; the flat
  publisher owns the root files. They do not share names.
- The t23 driver-level `0x801e` revision check stays in the driver
  (`sc2336p.c`/`sc2337p.c` `sensor_detect`); the registry must not mask it.
