# Raptor configuration

Raptor's runtime settings (`/etc/raptor.conf`) are configured through their own
Kconfig with their own `.config`, the way the kernel and BusyBox are. They are
deliberately **not** Buildroot symbols: a camera defconfig should describe
hardware, not encode bitrates and OSD positions.

## Editing

```bash
CAMERA=<camera> make raptor-menuconfig   # edit
CAMERA=<camera> make raptor-saveconfig   # write back to <camera>/raptor.config
```

Cameras under `configs/cameras-exp/` need `GROUP=exp`, as with any other make
target in this tree:

```bash
GROUP=exp CAMERA=wyze_cam3pro_t40xp_gc4653_rtl8192fs make raptor-menuconfig
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
| `<camera>/raptor.config` | that camera's delta, merged over the base |

It is named `raptor.config`, not `.fragment`, because in this tree a
`.fragment` is a *Buildroot* `.config` fragment (`configs/fragments/`,
`local.fragment`). This file is in raptor's own Kconfig namespace and has
nothing to do with those. Buildroot's variable that consumes it is still
called `_KCONFIG_FRAGMENT_FILES`; that is its API, not our filename.

Buildroot merges the two with `support/kconfig/merge_config.sh`, so a fragment
only carries what differs. `raptor-saveconfig` writes a minimal config, which
keeps fragments at a handful of lines rather than a dump of every symbol.

The file is exactly what `savedefconfig` emits: no header, and ordered by
Kconfig declaration rather than alphabetically. Do not sort it. Saving a
camera you have not changed produces no diff.

## How it renders

```
Kconfig + raptor.config -> .config -> conf-map -> gen-raptor-conf.sh -> /etc/raptor.conf
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

This menu is **only** about streamer settings. Build options (which codecs and
daemons get compiled) are not editable here and never will be: Buildroot's
`.config` is assembled before raptor is extracted, so a change here could not
make Buildroot `select` the needed package. Change those in
`make menuconfig` under Streamer, Raptor Streaming System.

Twelve Buildroot values are imported read-only through `option env` so this menu
only offers settings that the built image can actually use. They have no
prompt, so they are invisible; they only gate. Passed in by
`THINGINO_RAPTOR_CONFIG_KCONFIG_OPTS`:

| import | hides / constrains |
|--------|--------------------|
| `RAPTOR_SENSOR_QTY` | `[sensor]` vs `[sensor0]`/`[sensor1]`/`[mipi_switch]`, 7 menus |
| `RAPTOR_AAC`, `RAPTOR_OPUS` | the `audio codec` default, so it never names an unbuilt codec |
| `RAPTOR_RSR` | `[srt]`, 8 settings |
| `RAPTOR_WEBTORRENT` | `[webtorrent]`, 7 settings |
| `RAPTOR_WEBRTC` | `[webrtc]`, 13 settings |
| `RAPTOR_AUDIO_EFFECTS` | the ns / hpf / agc settings in `[audio]`, 6 settings |
| `RAPTOR_IVS_DETECT` | the motion model settings, 6 settings |
| `RAPTOR_RFS` | its section |
| `RAPTOR_DEV_WEBCAM` | several defaults (codec, fps, jpeg idle) |
| `RAPTOR_SOC_FAMILY`, `RAPTOR_SOC_MODEL` | available for per-SoC conditional defaults |

With every gated feature off, 87 settings disappear from the menu.

### Shared and per-SoC defaults

Put them in the Kconfig as conditional defaults, never in
`configs/raptor/default.config` (which must stay empty, see the comment in it):

```kconfig
config RAPTOR_STREAM0_BITRATE
	string "bitrate (default 3000000)"
	default "2000000" if (RAPTOR_ENV_SOC_FAMILY = "t31")
	default ""
```

`savedefconfig` measures minimality against these `default` statements, so a
camera matching the shared default has nothing written into its fragment, and
a later change to the default still reaches it. A camera that genuinely
overrides the value keeps it. Verified both ways:

| soc | camera sets | effective | saved to fragment |
|-----|-------------|-----------|-------------------|
| t31 | nothing | `2000000` | omitted |
| t40 | nothing | `""` | omitted |
| t31 | `1500000` | `1500000` | kept |

A value placed in `default.config` instead would be written into every
camera's fragment on the next `raptor-saveconfig`, silently ending the
sharing.

## Gotchas

- Buildroot's `-update-config` and `-update-defconfig` refuse to run while
  `KCONFIG_FRAGMENT_FILES` is set. `raptor-saveconfig` exists for that reason.
- `raptor-saveconfig` assumes `configs/raptor/default.config` is empty, so a
  minimal config equals the per-camera delta. If shared defaults are ever put
  in that base, the helper has to diff against it instead.
- The shim that drives kconfig is `Makefile.kconfig`, deliberately **not**
  named `*.mk`: `external.mk` includes every `package/*/*.mk`, and a `.mk`
  here would override Buildroot's own `menuconfig` recipe.
