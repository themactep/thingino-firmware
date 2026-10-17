# ISP debug logging

The T31 ISP driver (`open-tx-isp-mainline`) mixes four kinds of output. Keep
them separated so release logs stay quiet and development logs stay useful.

## Levels

| Macro | Level | Kernel tag | Use |
|-------|-------|------------|-----|
| `ISP_ERROR` | 2 | `KERN_ERR` | real failures and unexpected conditions |
| `ISP_WARNING` | 1 | `KERN_WARNING` | recoverable or expected anomalies |
| `ISP_INFO` | 0 | `KERN_INFO` | lifecycle: sensor probe, channel start/stop |
| `ISP_DEBUG` | 0 (trace build only) | `KERN_DEBUG` | per-event, per-frame, V4L2 and pad details |

All messages go through `isp_printf()` and are printed as
`tx-isp: <message>`. `isp_printf()` also applies the level tag, so
`dmesg -w | grep tx-isp` is the complete ISP log.

Runtime selection is the `print_level` module parameter:

- `print_level=0`: INFO, WARNING and ERROR (development)
- `print_level=1`: WARNING and ERROR (release default)
- `print_level=2`: ERROR only
- `print_level=3`: silent

The build chooses the default with the `ISP Debug Print Level` choice in
`Config.soc.in`. The default is 1. Do not put `BR2_ISP_PRINT_LEVEL_0=y` in a
camera defconfig; select it locally in menuconfig for a debug build.

## Release build

- `print_level=1`, so INFO and DEBUG are not printed.
- `TX_ISP_T31_NO_TRACE` is defined, so `pr_info()` and `ISP_DEBUG()` strings
  are compiled out. The recovered bring-up firehose costs no module space.
- No stack dumps: `dump_stack()` is only called when the bring-up trace is
  explicitly enabled (see below).
- Use `ISP_ERROR`/`ISP_WARNING` for anything that should appear in a release
  log. Never use an unconditional `isp_printf(0, ...)` for a diagnostic.

## Runtime debug without a rebuild

The production module still contains the `ISP_INFO` lifecycle messages.
Set `print_level=0` at load time (menuconfig or `/etc/modules.d/20-isp`) to
see sensor probe/stream and channel start/stop events. This does not enable
the per-event `ISP_DEBUG` lines; those are compiled out of a release build.

## Bring-up trace build

The recovered driver has a large `pr_info()` firehose (init, AE/AWB/ADR,
DMA). It is kept only when the module is built with `TX_ISP_T31_TRACE=y`.
Enable `BR2_ISP_TRACE` in menuconfig for such a build, or pass
`TX_ISP_T31_TRACE=y` to the module make. The trace adds ~220 KB and does not
fit the standard 4608 KB rootfs; load it from `/tmp` after `rmmod`, or use a
larger image.

With the trace build:

- `t31_runtime_trace=1` enables the `pr_info()` firehose and `ISP_DEBUG()`.
- `print_level=0` is still required for the level-0 messages.
- `t31_runtime_trace=0` keeps the trace quiet even in a trace build.

Do not ship a trace build. The release image must be built with
`BR2_ISP_TRACE` off.

## Message rules

- `ISP_ERROR`: include what failed and the value that failed. Do not log an
  expected NAK or an optional GPIO as an error.
- `ISP_WARNING`: state the degraded condition and the fallback.
- `ISP_INFO`: one line per lifecycle event. No per-frame, per-buffer or
  per-ioctl lines.
- `ISP_DEBUG`: per-event details only. These are trace-build strings.
- No unconditional debug messages. A message must describe a real condition
  (the old `not support the gpio mode!` line was unconditional and false; it
  was removed).

## Source location

The active source is the `open-tx-isp-mainline` override
(`~/thingino/overrides/open-tx-isp-mainline`). Overrides bypass Buildroot
patches, so these changes live in that tree, not in a `package/open-tx-isp`
patch. The relevant files are `driver/t31/include/tx_isp_debug.h` and
`driver/t31/tx_isp_core.c` (`isp_printf`, `ispcore_pad_event_handle`,
`frame_channel_vidioc_*`, `tisp_channel_attr_set`).
