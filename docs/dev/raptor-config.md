# Raptor configuration

Raptor's runtime settings (`/etc/raptor.conf`) are configured through their own
Kconfig with their own `.config`, the way the kernel and BusyBox are. They are
deliberately **not** Buildroot symbols: a camera defconfig should describe
hardware, not encode bitrates and OSD positions.

## Editing

```bash
CAMERA=<camera> make raptor-menuconfig   # edit
CAMERA=<camera> make raptor-saveconfig   # write back to <camera>/raptor.fragment
```

Buildroot's own package targets also work, via the `br-%` passthrough:

```bash
make br-thingino-raptor-config-menuconfig
make br-thingino-raptor-config-savedefconfig
make br-thingino-raptor-config-diff-config
```

## Where the values live

| path | role |
|------|------|
| `configs/raptor/default.config` | shared base for every camera |
| `<camera>/raptor.fragment` | that camera's delta, merged over the base |

Buildroot merges the two with `support/kconfig/merge_config.sh`, so a fragment
only carries what differs. `raptor-saveconfig` writes a minimal config, which
keeps fragments at a handful of lines rather than a dump of every symbol.

## How it renders

```
Kconfig + raptor.fragment -> .config -> conf-map -> gen-raptor-conf.sh -> /etc/raptor.conf
```

`gen-raptor-conf.sh` *patches* the `config/raptor.conf` template that raptor
itself ships, rather than generating the file from scratch. That is deliberate:
keys raptor adds upstream keep flowing through with raptor's own defaults even
before this Kconfig knows about them.

`conf-map` maps each symbol to its `raptor.conf` section and key:

```
str  sensor name              RAPTOR_SENSOR_NAME
bool stream0 ivdc             RAPTOR_STREAM0_IVDC
enum webrtc audio_mode        RAPTOR_WEBRTC_AUDIO_MODE OPUS AUTO PCMU
```

- `str` writes the value when non-empty, otherwise leaves the line commented.
- `bool` is a three-way choice: `_TRUE` and `_FALSE` force a value, `_DEFAULT`
  leaves raptor's own default in place. A plain bool cannot express the third
  state, which is why each one costs three symbols.
- `enum` picks the selected suffix, lowercased.

## Adding a setting

Two files, same name in both:

1. `package/thingino-raptor-config/Kconfig` -- the symbol and its help text.
2. `package/thingino-raptor-config/conf-map` -- its section and key.

## Values imported from Buildroot

Five Buildroot values are visible to the Kconfig through `option env`, because
they gate which settings apply. They are passed in by
`THINGINO_RAPTOR_CONFIG_KCONFIG_OPTS`:

`RAPTOR_SENSOR_QTY`, `RAPTOR_DEV_WEBCAM`, `RAPTOR_IVS_DETECT`,
`RAPTOR_WEBRTC`, `RAPTOR_RFS`.

The sensor count is the important one: with one sensor the `[sensor]` section
applies, with two or more the layout switches to `[sensor0]` / `[sensor1]`
plus `[mipi_switch]`.

## Gotchas

- Buildroot's `-update-config` and `-update-defconfig` refuse to run while
  `KCONFIG_FRAGMENT_FILES` is set. `raptor-saveconfig` exists for that reason.
- `raptor-saveconfig` assumes `configs/raptor/default.config` is empty, so a
  minimal config equals the per-camera delta. If shared defaults are ever put
  in that base, the helper has to diff against it instead.
- The shim that drives kconfig is `Makefile.kconfig`, deliberately **not**
  named `*.mk`: `external.mk` includes every `package/*/*.mk`, and a `.mk`
  here would override Buildroot's own `menuconfig` recipe.
