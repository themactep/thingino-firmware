# libimp userspace

The userspace half of the Ingenic media stack is `libimp.so` — the IMP
(Ingenic Media Platform) core library — plus a small set of companion
libraries. `libimp` exposes the `IMP_*` API (`IMP_System_*`,
`IMP_FrameSource_*`, `IMP_Encoder_*`, `IMP_ISP_*`, `IMP_OSD_*`, ...) that
streamers link against; internally it drives the `tx-isp` miscdevices through
ioctls.

## Library set

| Library | Package | Purpose |
| --- | --- | --- |
| `libimp.so` | `ingenic-lib` / `openimp` | IMP core (video/audio/ISP/OSD) |
| `libalog.so` | `ingenic-lib` | Ingenic logging |
| `libsysutils.so` | `ingenic-lib` | `SU_*` system utilities |
| `libaudioProcess.so` | `ingenic-lib` | audio processing |
| `libjzdl.m.so` | `ingenic-lib` (JZDL) | standalone NN inference (609 KB) |
| `libpersonDet_inf.so` + MXU | `ingenic-lib` (PersonDet) | person detection IVS (1.5 MB) |

All are proprietary blobs from `gtxaspec/ingenic-lib`, selected per
SoC/kernel/libc by the version matrix in `docs/media/ingenic-sdk-versions.md`.

## libc linkage quirks

Recorded in `package/ingenic-lib/Config.in`:

- The T30 `libimp.so` (SDK 1.0.5) is the **only** libimp that links
  `libstdc++.so.6`, so the C++ runtime is kept on target only for T30.
- Every family's `libaudioProcess.so` links `libstdc++.so.6`.

## Open replacements

The open ISP stack (`BR2_PACKAGE_THINGINO_ISP_OPEN`) swaps in
reverse-engineered components:

| Component | Package | Scope |
| --- | --- | --- |
| `open-tx-isp` | `open-tx-isp` | kernel driver, installed as `tx-isp-<soc>.ko` |
| OpenIMP | `openimp` | `libimp.so`, builds for T20/T21/T30/T31/T40/T41 |
| `ingenic-system-libs-neo` | — | `libalog` + `libsysutils` (thread-safe, 51% smaller) |
| `libaudioprocess-neo` | — | `libaudioProcess` (libc-only) |

T23 is excluded from the OpenIMP gate: upstream's T23 build is a hybrid that
keeps the OEM `libimp.so` for audio and the Helix encoder. See
`docs/media/open-isp-stack.md` for the full matrix.

## Runtime control: imp-control

`package/ingenic-libimp-control` builds `libimp_control.so` (from
`gtxaspec/libimp_control`) plus the `imp-control` CLI and the `S33impconfig`
init script. The library is loaded into the streamer and listens on TCP port
4000; strero's init script shows the pattern (`LD_PRELOAD=/lib/libimp_control.so`).

The CLI is a thin client:

```sh
echo "imp_control $*" | nc localhost 4000
```

`S33impconfig` is also a client, not the server: it waits for the ISP to come
up (checks `/proc/jz/isp/isp_info` on t10/t20, else `/proc/jz/isp/isp-fs`),
then replays `/etc/imp.conf` line-by-line through `imp-control` to restore
saved ISP/IMP settings.

## Diagnostics: libimp-debug

`package/libimp-debug` builds `libimp-debug`, which queries the video
pipeline, encoder, framesource, audio, and ISP subsystems via shared-memory
IPC. `thingino-diag` invokes:

```sh
libimp-debug --system_info
libimp-debug --fs_info
libimp-debug --enc_info
```

Related runtime artifacts gathered by diagnostics:

- `/tmp/continuous_mem_info` — libimp allocator report (written by the blob).
- `/proc/jz/isp/isp-{fs,m0}` and `/proc/jz/isp/isp_info` — kernel ISP state.
- `/proc/jz/sensor/<name>/` — sensor identity and FPS (see
  `docs/media/tx-isp-pipeline.md`).

## Related

- [Ingenic media stack](ingenic-media-stack.md) — stack overview
- [TX-ISP pipeline](tx-isp-pipeline.md) — the kernel ioctl surface libimp drives
- [Ingenic SDK versions](ingenic-sdk-versions.md) — blob version selection
- [Open ISP stack](open-isp-stack.md) — OpenIMP / open-tx-isp provider
