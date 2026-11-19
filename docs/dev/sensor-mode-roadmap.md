# Sensor mode roadmap

The sensor drivers in [thingino/ingenic-sdk](https://github.com/thingino/ingenic-sdk)
state each mode's frame in more than one place, and in the drivers listed here
two of those places disagree. This page is the list, with a status per row.
How to take a row, fix it, measure it and send it is in
[sensor-mode-fixes.md](sensor-mode-fixes.md).

A row says that two places in a driver disagree. It does not say which of them
is right: that takes a measurement on a camera or the sensor's datasheet.

## Where the list comes from

- `tools/check_sensor_modes.py` of ingenic-sdk, run on `main` at
  `1ecb6041`: 1066 driver files, 1065 analysed, 2158 modes.
- Findings: 200 high in 131 files, 276 medium in 174 files. Low findings (names,
  labels, fields whose use by the ISP is not known) are not listed; the script
  prints them with `--min-severity low`.
- The Profiles column counts the camera profiles under `configs/` that build
  that file, at thingino-firmware `54cf7679960d` (286 profiles read): by the
  profile's SoC family, kernel version and `BR2_SENSOR_<n>_NAME`. It counts
  profiles that build the driver, not profiles that run the row's mode.
- Line numbers are those of the SDK commit above. After a later commit, run the
  script again and go by its output.

## Columns

- **Status**: `open`; `fixed: <ingenic-sdk pull request>, measured on <camera
  profile>`; `fixed, not measured: <pull request>`; `not a bug: <why>`.
- **Driver**: the file under `<kernel>/sensor-src/`. A driver present in both
  kernel trees has a row for each; fix both in one pull request.
- **Mode**: the module parameters or the `default_boot` value that select the mode,
  as the driver's own code tests them. `-` when the driver has one mode.
- **What disagrees**, in lines per frame: `table` is what the mode's register init
  table programs, `reports` is the `total_height` the mode gives the ISP, `set_fps`
  is what the driver's `set_fps` computes from its clock constant at the mode's
  own rate. `-` means that value could not be read from the source.

## Checks

- `frame-length`: the table and `total_height` disagree. The ISP takes its line
  time from the frame rate and `total_height`, so exposure times and anti-flicker
  steps are off by the same ratio.
- `frame-short`: `total_height` is smaller than the image height of the mode.
- `byte-order`: `set_fps` writes the two frame-length bytes to the registers in
  the opposite order to the init table.

## Start here: flagged modes a profile runs

4 rows in 4 files. Which mode a profile runs was read by hand from its
`BR2_SENSOR_1_PARAMS` and the driver's parameter defaults; check it on the
camera before relying on it (`/sys/module/sensor_<sensor>_<soc>/parameters/`).

| Status | Driver | Kernel | Line | Mode | What disagrees | Profiles that run it | Why this mode |
|---|---|---|---|---|---|---|---|
| open | `t41/gc4023.c` | 4.4.94 | 1633 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | table 1875, reports 1500, set_fps 1687 | `360_k7ts_t41nq_gc4023_eth`, `iget_c5pt_t41lq_gc4023_jl1101`, `noorio_t110_t41nq_gc4023_aic8800d`, `qemu_t41nq`, `vanhua_z66si_t41nq_gc4023_eth` | no profile sets the streamer's sensor boot mode; `default_boot` is taken to be 0 then |
| open | `t21/sc2300.c` | 3.10.14 | 327 | `-` | table 1125, reports 2250, set_fps 1125 | `primecables_08360_t21z_sc2300_rtl8188ftv`, `primecables_08361_t21n_sc2300_rtl8188ftv` | the driver has one mode |
| open | `t23/jxh63p.c` | 3.10.14 | 249 | `-` | table 750, reports 3000, set_fps 750 | `aobocam_a12_t23dl_jxh63p_txw901u` | the driver has one mode |
| open | `t31/jxk04.c` | 3.10.14 | 230 | `sensor_max_fps=25` | table 1500, reports 1560, set_fps 1500 | `h3c_c2041_t31x_jxk04_eth+rtl8188ftv` | `sensor_max_fps` is not set and defaults to 25 |

## High findings in other modes of drivers a profile builds

12 rows in 9 files, most-built first. The profiles build the driver and run
another of its modes, so a camera shows the fault only when loaded with the
row's parameters.

| Status | Driver | Kernel | Line | Mode | Check | What disagrees | Profiles | Why no profile runs it |
|---|---|---|---|---|---|---|---|---|
| open | `t31/gc4653.c` | 3.10.14 | 1667 | `sensor_resolution=RES_100,data_type=0` | frame-length | table 1488, reports 1600, set_fps 1501 | 9 | `sensor_resolution` is left at its default, 400 |
| open | `t31/sc3336.c` | 3.10.14 | 1483 | `sensor_resolution=RES_100` | frame-length | table 1360, reports 1320, set_fps 660 | 6 | `sensor_resolution` is left at its default, 300 |
| open | `t41/gc4023.c` | 4.4.94 | 1646 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 2025, reports 1500, set_fps 2025 | 5 | `default_boot` is left at 0 |
| open | `t41/gc4023.c` | 4.4.94 | 1659 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 2250, reports 1500, set_fps 2250 | 5 | `default_boot` is left at 0 |
| open | `t41/gc4023.c` | 4.4.94 | 1672 | `default_boot=3,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 3000, reports 1500, set_fps 3375 | 5 | `default_boot` is left at 0 |
| open | `t31/jxf23.c` | 3.10.14 | 1864 | `data_interface=MIPI,data_type=DATA_TYPE_WDR_FS` | frame-length | table 4500, reports 7828, set_fps 2250 | 3 | `data_type` is left at its default, linear |
| open | `t23/sc3336.c` | 3.10.14 | 1483 | `sensor_resolution=RES_100` | frame-length | table 1360, reports 1320, set_fps 660 | 2 | `sensor_resolution` is left at its default, 300 |
| open | `t31/gc2063.c` | 3.10.14 | 1813 | `sensor_max_fps=25,data_interface=MIPI` | frame-length | table 1181, reports 1308, set_fps 2181 | 1 | `sensor_max_fps` is left at its default, 30 |
| open | `t31/jxk04.c` | 3.10.14 | 230 | `sensor_max_fps=15` | frame-length | table 1500, reports 1560, set_fps 1500 | 1 | `sensor_max_fps` is left at its default, 25 |
| open | `t31/jxk04.c` | 3.10.14 | 230 | `sensor_max_fps=30` | frame-length | table 1672, reports 1560, set_fps 1666 | 1 | `sensor_max_fps` is left at its default, 25 |
| open | `t31/sc4236.c` | 3.10.14 | 1376 | `sensor_resolution=SENSOR_RES_300` | frame-length | table 1920, reports 2000, set_fps 1920 | 1 | the profile sets `sensor_resolution=400` |
| open | `t31/sc5235.c` | 3.10.14 | 1633 | `data_interface=MIPI,sensor_resolution=SENSOR_RES_400,data_type=DATA_TYPE_LINEAR` | frame-length | table 1500, reports 1650, set_fps 1500 | 1 | `sensor_resolution` is left at its default, 500 |

## High findings in drivers no profile builds

184 rows in 120 files, by sensor name. No profile in this tree is affected; a
fix still needs a camera that carries the sensor.

| Status | Driver | Kernel | Line | Mode | Check | What disagrees | Profiles |
|---|---|---|---|---|---|---|---|
| open | `t32/gc02m1.c` | 3.10.14 | 1218 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1268, reports 1252, set_fps 1268 | 0 |
| open | `t32/gc02m1.c` | 4.4.94 | 1218 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1268, reports 1252, set_fps 1268 | 0 |
| open | `t31/gc032a.c` | 3.10.14 | 349 | `-` | frame-length | table 504, reports 627, set_fps - | 0 |
| open | `t31/gc032a.c` | 4.4.94 | 340 | `-` | frame-length | table 504, reports 627, set_fps - | 0 |
| open | `t31/gc1054.c` | 3.10.14 | 378 | `data_interface=DVP` | frame-length | table 750, reports 903, set_fps - | 0 |
| open | `t31/gc1054.c` | 4.4.94 | 357 | `data_interface=DVP` | frame-length | table 750, reports 903, set_fps - | 0 |
| open | `t32/gc13b0.c` | 3.10.14 | 1591 | `-` | frame-short | reports total_height 1696 for a 2880-line image | 0 |
| open | `t32/gc13b0.c` | 3.10.14 | 1950 | `-` | byte-order | set_fps writes high/low to 0x341/0x340,, the table holds them the other way round | 0 |
| open | `t32/gc13b0.c` | 4.4.94 | 1591 | `-` | frame-short | reports total_height 1696 for a 2880-line image | 0 |
| open | `t32/gc13b0.c` | 4.4.94 | 1950 | `-` | byte-order | set_fps writes high/low to 0x341/0x340,, the table holds them the other way round | 0 |
| open | `t23/gc2053-double.c` | 3.10.14 | 1886 | `sensor_max_fps=30,data_interface=MIPI,fsync_mode=2` | frame-length | table 1181, reports 1418, set_fps 1185 | 0 |
| open | `t23/gc2053-double.c` | 3.10.14 | 1938 | `sensor_max_fps=30,data_interface=MIPI,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 1181, reports 1418, set_fps 1183 (total_height 3781, rescaled to the window's rate) | 0 |
| open | `t23/gc2053.c` | 3.10.14 | 1712 | `sensor_max_fps=30,data_interface=MIPI` | frame-length | table 1181, reports 1418, set_fps 1181 | 0 |
| open | `t30/gc2053.c` | 3.10.14 | 1180 | `sensor_max_fps=15,data_interface=MIPI` | frame-length | table 1350, reports 1128, set_fps 1350 | 0 |
| open | `t23/gc2053s0.c` | 3.10.14 | 1949 | `sensor_max_fps=30,data_interface=MIPI,fsync_mode=2` | frame-length | table 1181, reports 1418, set_fps 1185 | 0 |
| open | `t23/gc2053s0.c` | 3.10.14 | 2003 | `sensor_max_fps=30,data_interface=MIPI,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 1181, reports 1418, set_fps 1183 (total_height 3781, rescaled to the window's rate) | 0 |
| open | `t23/gc2053s1.c` | 3.10.14 | 1927 | `sensor_max_fps=30,data_interface=MIPI,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 1181, reports 1418, set_fps 1182 (total_height 3781, rescaled to the window's rate) | 0 |
| open | `t23/gc2063.c` | 3.10.14 | 1721 | `sensor_max_fps=30,data_interface=MIPI` | frame-length | table 1181, reports 1418, set_fps 1181 | 0 |
| open | `t41/gc2063.c` | 3.10.14 | 1010 | `default_boot=0,video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 1104, reports 1350, set_fps 1125 | 0 |
| open | `t41zrt/gc2063.c` | 3.10.14 | 1038 | `default_boot=1,video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 1104, reports 1350, set_fps 1125 | 0 |
| open | `t31/gc2063.c` | 4.4.94 | 1796 | `sensor_max_fps=25,data_interface=MIPI` | frame-length | table 1181, reports 1308, set_fps 2181 | 0 |
| open | `t41/gc2063.c` | 4.4.94 | 1004 | `default_boot=0,video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 1104, reports 1350, set_fps 1125 | 0 |
| open | `t41zrt/gc2063.c` | 4.4.94 | 1028 | `default_boot=1,video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 1104, reports 1350, set_fps 1125 | 0 |
| open | `t23/gc2063s0.c` | 3.10.14 | 1949 | `sensor_max_fps=30,data_interface=MIPI,fsync_mode=2` | frame-length | table 1181, reports 1418, set_fps 1185 | 0 |
| open | `t23/gc2063s0.c` | 3.10.14 | 2003 | `sensor_max_fps=30,data_interface=MIPI,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 1181, reports 1418, set_fps 1183 (total_height 3781, rescaled to the window's rate) | 0 |
| open | `t23/gc2063s1.c` | 3.10.14 | 1989 | `sensor_max_fps=30,data_interface=MIPI,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 1181, reports 1418, set_fps 1182 (total_height 3781, rescaled to the window's rate) | 0 |
| open | `t23/gc2083s0.c` | 3.10.14 | 617 | `-` | byte-order | set_fps writes high/low to 0xd42/0xd41,, the table holds them the other way round | 0 |
| open | `t23/gc2083s1.c` | 3.10.14 | 618 | `-` | byte-order | set_fps writes high/low to 0xd42/0xd41,, the table holds them the other way round | 0 |
| open | `t40/gc2083s1.c` | 3.10.14 | 727 | `-` | frame-length | table 3480, reports 1418, set_fps 3480 | 0 |
| open | `t40/gc2083s1.c` | 4.4.94 | 719 | `-` | frame-length | table 3480, reports 1418, set_fps 3480 | 0 |
| open | `t23/gc2093.c` | 3.10.14 | 182 | `-` | frame-length | table 1350, reports 1125, set_fps 1350 | 0 |
| open | `t41/gc4023.c` | 3.10.14 | 1646 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 1875, reports 1500, set_fps 1687 | 0 |
| open | `t41/gc4023.c` | 3.10.14 | 1659 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 2025, reports 1500, set_fps 2025 | 0 |
| open | `t41/gc4023.c` | 3.10.14 | 1672 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 2250, reports 1500, set_fps 2250 | 0 |
| open | `t41/gc4023.c` | 3.10.14 | 1685 | `default_boot=3,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 3000, reports 1500, set_fps 3375 | 0 |
| open | `t41zrt/gc4023.c` | 3.10.14 | 1709 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 1875, reports 1500, set_fps 1687 | 0 |
| open | `t41zrt/gc4023.c` | 3.10.14 | 1722 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 2025, reports 1500, set_fps 2025 | 0 |
| open | `t41zrt/gc4023.c` | 3.10.14 | 1735 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 2250, reports 1500, set_fps 2250 | 0 |
| open | `t41zrt/gc4023.c` | 3.10.14 | 1748 | `default_boot=3,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 3000, reports 1500, set_fps 3375 | 0 |
| open | `t41zrt/gc4023.c` | 4.4.94 | 1698 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 1875, reports 1500, set_fps 1687 | 0 |
| open | `t41zrt/gc4023.c` | 4.4.94 | 1711 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 2025, reports 1500, set_fps 2025 | 0 |
| open | `t41zrt/gc4023.c` | 4.4.94 | 1724 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 2250, reports 1500, set_fps 2250 | 0 |
| open | `t41zrt/gc4023.c` | 4.4.94 | 1737 | `default_boot=3,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 3000, reports 1500, set_fps 3375 | 0 |
| open | `t41/gc4023s1.c` | 3.10.14 | 1866 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=3` | frame-length | table 1875, reports 1500, set_fps 1687 | 0 |
| open | `t41/gc4023s1.c` | 3.10.14 | 1879 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=3` | frame-length | table 2025, reports 1500, set_fps 2025 | 0 |
| open | `t41/gc4023s1.c` | 3.10.14 | 1892 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=3` | frame-length | table 2250, reports 1500, set_fps 2250 | 0 |
| open | `t41/gc4023s1.c` | 3.10.14 | 1905 | `default_boot=3,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=3` | frame-length | table 3000, reports 1500, set_fps 3375 | 0 |
| open | `t41/gc4023s1.c` | 3.10.14 | 1943 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 1875, reports 1500, set_fps 1688 (total_height 3000, rescaled to the window's rate) | 0 |
| open | `t41/gc4023s1.c` | 3.10.14 | 1943 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 2025, reports 1500, set_fps 2025 (total_height 3000, rescaled to the window's rate) | 0 |
| open | `t41/gc4023s1.c` | 3.10.14 | 1943 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 2250, reports 1500, set_fps 2250 (total_height 3000, rescaled to the window's rate) | 0 |
| open | `t41/gc4023s1.c` | 3.10.14 | 1943 | `default_boot=3,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 3000, reports 1500, set_fps 3375 (total_height 3000, rescaled to the window's rate) | 0 |
| open | `t41/gc4023s1.c` | 4.4.94 | 1850 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=3` | frame-length | table 1875, reports 1500, set_fps 1687 | 0 |
| open | `t41/gc4023s1.c` | 4.4.94 | 1863 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=3` | frame-length | table 2025, reports 1500, set_fps 2025 | 0 |
| open | `t41/gc4023s1.c` | 4.4.94 | 1876 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=3` | frame-length | table 2250, reports 1500, set_fps 2250 | 0 |
| open | `t41/gc4023s1.c` | 4.4.94 | 1889 | `default_boot=3,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=3` | frame-length | table 3000, reports 1500, set_fps 3375 | 0 |
| open | `t41/gc4023s1.c` | 4.4.94 | 1927 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 1875, reports 1500, set_fps 1688 (total_height 3000, rescaled to the window's rate) | 0 |
| open | `t41/gc4023s1.c` | 4.4.94 | 1927 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 2025, reports 1500, set_fps 2025 (total_height 3000, rescaled to the window's rate) | 0 |
| open | `t41/gc4023s1.c` | 4.4.94 | 1927 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 2250, reports 1500, set_fps 2250 (total_height 3000, rescaled to the window's rate) | 0 |
| open | `t41/gc4023s1.c` | 4.4.94 | 1927 | `default_boot=3,video_interface=TISP_SENSOR_VI_MIPI_CSI0,fsync_mode=TX_ISP_SENSOR_FSYNC_MODE_MS_REALTIME_MISPLACE` | frame-length | table 3000, reports 1500, set_fps 3375 (total_height 3000, rescaled to the window's rate) | 0 |
| open | `t31/gc4653.c` | 4.4.94 | 1648 | `sensor_resolution=RES_100,data_type=0` | frame-length | table 1488, reports 1600, set_fps 1501 | 0 |
| open | `t41/gc4663.c` | 3.10.14 | 1193 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1600, reports 1375, set_fps 1600 | 0 |
| open | `t41/gc4663.c` | 4.4.94 | 1181 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1600, reports 1375, set_fps 1600 | 0 |
| open | `t41zrt/gc5603.c` | 3.10.14 | 973 | `default_boot=1` | frame-length | table 2334, reports 1750, set_fps 2317 | 0 |
| open | `t41zrt/gc5603.c` | 4.4.94 | 961 | `default_boot=1` | frame-length | table 2334, reports 1750, set_fps 2317 | 0 |
| open | `t32/gc5613.c` | 3.10.14 | 1091 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1750, reports 2917, set_fps 1754 | 0 |
| open | `t32/gc5613.c` | 4.4.94 | 1091 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1750, reports 2917, set_fps 1754 | 0 |
| open | `t32/gc8602.c` | 3.10.14 | 1842 | `-` | byte-order | set_fps writes high/low to 0x341/0x340,, the table holds them the other way round | 0 |
| open | `t32/gc8602.c` | 4.4.94 | 1842 | `-` | byte-order | set_fps writes high/low to 0x341/0x340,, the table holds them the other way round | 0 |
| open | `t41/gc8613.c` | 3.10.14 | 1343 | `default_boot=2` | frame-length | table 2250, reports 1600, set_fps 2250 | 0 |
| open | `t41/gc8613.c` | 3.10.14 | 1343 | `default_boot=2` | frame-short | reports total_height 1600 for a 2160-line image | 0 |
| open | `t41/gc8613.c` | 4.4.94 | 1332 | `default_boot=2` | frame-length | table 2250, reports 1600, set_fps 2250 | 0 |
| open | `t41/gc8613.c` | 4.4.94 | 1332 | `default_boot=2` | frame-short | reports total_height 1600 for a 2160-line image | 0 |
| open | `t32/imx415.c` | 3.10.14 | 702 | `-` | frame-length | table 2226, reports 2262, set_fps 2289 | 0 |
| open | `t32/imx415.c` | 4.4.94 | 702 | `-` | frame-length | table 2226, reports 2262, set_fps 2289 | 0 |
| open | `t23/jxf23.c` | 3.10.14 | 1887 | `data_interface=MIPI,data_type=DATA_TYPE_WDR_FS` | frame-length | table 4500, reports 7828, set_fps 2250 | 0 |
| open | `t31/jxf23.c` | 4.4.94 | 1862 | `data_interface=MIPI,data_type=DATA_TYPE_WDR_FS` | frame-length | table 4500, reports 7828, set_fps 2250 | 0 |
| open | `t40/jxf23s1.c` | 3.10.14 | 1922 | `data_interface=MIPI,data_type=DATA_TYPE_WDR_FS` | frame-length | table 4500, reports 7828, set_fps 2250 | 0 |
| open | `t40/jxf23s1.c` | 4.4.94 | 1914 | `data_interface=MIPI,data_type=DATA_TYPE_WDR_FS` | frame-length | table 4500, reports 7828, set_fps 2250 | 0 |
| open | `t31/jxf32.c` | 3.10.14 | 1158 | `sensor_resolution=RES_30` | frame-length | table 1133, reports 400, set_fps 1200 | 0 |
| open | `t31/jxf32.c` | 3.10.14 | 1158 | `sensor_resolution=RES_30` | frame-short | reports total_height 400 for a 720-line image | 0 |
| open | `t40/jxf32.c` | 3.10.14 | 448 | `default_boot=1,data_interface=DVP,video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 1125, reports 1350, set_fps 2700 | 0 |
| open | `t31/jxf32.c` | 4.4.94 | 1140 | `sensor_resolution=RES_30` | frame-length | table 1133, reports 400, set_fps 1200 | 0 |
| open | `t31/jxf32.c` | 4.4.94 | 1140 | `sensor_resolution=RES_30` | frame-short | reports total_height 400 for a 720-line image | 0 |
| open | `t40/jxf32.c` | 4.4.94 | 442 | `default_boot=1,data_interface=DVP,video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 1125, reports 1350, set_fps 2700 | 0 |
| open | `t23/jxf35.c` | 3.10.14 | 855 | `sensor_max_fps=30,data_interface=DVP,data_type=DATA_TYPE_LINEAR` | frame-length | table 1125, reports 1350, set_fps 2700 | 0 |
| open | `t31/jxf35.c` | 3.10.14 | 1076 | `sensor_max_fps=PS5270_SENSOR_MAX_FPS_30,data_interface=DVP,data_type=DATA_TYPE_LINEAR` | frame-length | table 1125, reports 1350, set_fps 2700 | 0 |
| open | `t40/jxf35.c` | 3.10.14 | 864 | `default_boot=1,data_interface=DVP,video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 1125, reports 1350, set_fps 2700 | 0 |
| open | `t31/jxf35.c` | 4.4.94 | 1063 | `sensor_max_fps=PS5270_SENSOR_MAX_FPS_30,data_interface=DVP,data_type=DATA_TYPE_LINEAR` | frame-length | table 1125, reports 1350, set_fps 2700 | 0 |
| open | `t40/jxf35.c` | 4.4.94 | 858 | `default_boot=1,data_interface=DVP,video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 1125, reports 1350, set_fps 2700 | 0 |
| open | `t23/jxk04.c` | 3.10.14 | 219 | `sensor_max_fps=15` | frame-length | table 1500, reports 1560, set_fps 1500 | 0 |
| open | `t23/jxk04.c` | 3.10.14 | 219 | `sensor_max_fps=25` | frame-length | table 1500, reports 1560, set_fps 1500 | 0 |
| open | `t23/jxk04.c` | 3.10.14 | 219 | `sensor_max_fps=30` | frame-length | table 1672, reports 1560, set_fps 1666 | 0 |
| open | `t40/jxk04.c` | 3.10.14 | 1328 | `default_boot=1` | frame-length | table 1500, reports 1125, set_fps 1500 | 0 |
| open | `t40/jxk04.c` | 3.10.14 | 1328 | `default_boot=1` | frame-short | reports total_height 1125 for a 1440-line image | 0 |
| open | `t40/jxk04.c` | 3.10.14 | 1343 | `default_boot=2` | frame-length | table 1672, reports 1125, set_fps 1666 | 0 |
| open | `t40/jxk04.c` | 3.10.14 | 1343 | `default_boot=2` | frame-short | reports total_height 1125 for a 1440-line image | 0 |
| open | `t40/jxk04.c` | 3.10.14 | 1359 | `default_boot=3` | frame-length | table 3000, reports 3200, set_fps 3000 | 0 |
| open | `t31/jxk04.c` | 4.4.94 | 218 | `sensor_max_fps=15` | frame-length | table 1500, reports 1560, set_fps 1500 | 0 |
| open | `t31/jxk04.c` | 4.4.94 | 218 | `sensor_max_fps=25` | frame-length | table 1500, reports 1560, set_fps 1500 | 0 |
| open | `t31/jxk04.c` | 4.4.94 | 218 | `sensor_max_fps=30` | frame-length | table 1672, reports 1560, set_fps 1666 | 0 |
| open | `t40/jxk04.c` | 4.4.94 | 1324 | `default_boot=1` | frame-length | table 1500, reports 1125, set_fps 1500 | 0 |
| open | `t40/jxk04.c` | 4.4.94 | 1324 | `default_boot=1` | frame-short | reports total_height 1125 for a 1440-line image | 0 |
| open | `t40/jxk04.c` | 4.4.94 | 1339 | `default_boot=2` | frame-length | table 1672, reports 1125, set_fps 1666 | 0 |
| open | `t40/jxk04.c` | 4.4.94 | 1339 | `default_boot=2` | frame-short | reports total_height 1125 for a 1440-line image | 0 |
| open | `t40/jxk04.c` | 4.4.94 | 1355 | `default_boot=3` | frame-length | table 3000, reports 3200, set_fps 3000 | 0 |
| open | `t20/jxv01.c` | 3.10.14 | 168 | `-` | frame-length | table 524, reports 722, set_fps 524 | 0 |
| open | `t21/mis2003.c` | 3.10.14 | 262 | `-` | frame-length | table 2560, reports 1125, set_fps 2560 | 0 |
| open | `t30/mis2003.c` | 3.10.14 | 254 | `-` | frame-length | table 2560, reports 1125, set_fps 2560 | 0 |
| open | `t31/os02d20.c` | 3.10.14 | 337 | `sensor_max_fps=30,data_type=DATA_TYPE_LINEAR` | frame-length | table 2207, reports 1103, set_fps - | 0 |
| open | `t31/os02d20.c` | 4.4.94 | 320 | `sensor_max_fps=30,data_type=DATA_TYPE_LINEAR` | frame-length | table 2207, reports 1103, set_fps - | 0 |
| open | `t31/os04l10.c` | 3.10.14 | 927 | `-` | frame-length | table 1736, reports 1468, set_fps - | 0 |
| open | `t31/os04l10.c` | 4.4.94 | 914 | `-` | frame-length | table 1736, reports 1468, set_fps - | 0 |
| open | `t31/os05a20.c` | 3.10.14 | 1528 | `sensor_max_fps=30` | frame-length | table 2690, reports 669, set_fps 2672 | 0 |
| open | `t31/os05a20.c` | 3.10.14 | 1528 | `sensor_max_fps=30` | frame-short | reports total_height 669 for a 1080-line image | 0 |
| open | `t31/os05a20.c` | 3.10.14 | 1538 | `sensor_max_fps=60` | frame-length | table 1345, reports 669, set_fps 2672 | 0 |
| open | `t31/os05a20.c` | 3.10.14 | 1538 | `sensor_max_fps=60` | frame-short | reports total_height 669 for a 1080-line image | 0 |
| open | `t31/os05a20.c` | 4.4.94 | 1508 | `sensor_max_fps=30` | frame-length | table 2690, reports 669, set_fps 2672 | 0 |
| open | `t31/os05a20.c` | 4.4.94 | 1508 | `sensor_max_fps=30` | frame-short | reports total_height 669 for a 1080-line image | 0 |
| open | `t31/os05a20.c` | 4.4.94 | 1518 | `sensor_max_fps=60` | frame-length | table 1345, reports 669, set_fps 2672 | 0 |
| open | `t31/os05a20.c` | 4.4.94 | 1518 | `sensor_max_fps=60` | frame-short | reports total_height 669 for a 1080-line image | 0 |
| open | `t40/ov02b10.c` | 3.10.14 | 802 | `video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 2225, reports 1472, set_fps - | 0 |
| open | `t40/ov02b10.c` | 3.10.14 | 802 | `video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 2225, reports 1472, set_fps - | 0 |
| open | `t40/ov02b10.c` | 4.4.94 | 792 | `video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 2225, reports 1472, set_fps - | 0 |
| open | `t40/ov02b10.c` | 4.4.94 | 792 | `video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 2225, reports 1472, set_fps - | 0 |
| open | `t40/ov02b1b.c` | 3.10.14 | 692 | `video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 2444, reports 1472, set_fps - | 0 |
| open | `t40/ov02b1b.c` | 3.10.14 | 692 | `video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 2444, reports 1472, set_fps - | 0 |
| open | `t40/ov02b1b.c` | 4.4.94 | 682 | `video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 2444, reports 1472, set_fps - | 0 |
| open | `t40/ov02b1b.c` | 4.4.94 | 682 | `video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 2444, reports 1472, set_fps - | 0 |
| open | `t41/ov2736.c` | 3.10.14 | 808 | `-` | frame-length | table 2368, reports 1184, set_fps 2368 | 0 |
| open | `t41/ov2736.c` | 4.4.94 | 801 | `-` | frame-length | table 2368, reports 1184, set_fps 2368 | 0 |
| open | `t31/ps5258.c` | 3.10.14 | 231 | `-` | frame-length | table 1350, reports 1125, set_fps 1350 | 0 |
| open | `t40/ps5258.c` | 3.10.14 | 224 | `-` | frame-length | table 1350, reports 1125, set_fps 1350 | 0 |
| open | `t31/ps5258.c` | 4.4.94 | 217 | `-` | frame-length | table 1350, reports 1125, set_fps 1350 | 0 |
| open | `t40/ps5258.c` | 4.4.94 | 216 | `-` | frame-length | table 1350, reports 1125, set_fps 1350 | 0 |
| open | `t40/sc031iot.c` | 3.10.14 | 242 | `-` | frame-length | table 1049, reports 2090, set_fps - | 0 |
| open | `t40/sc031iot.c` | 4.4.94 | 230 | `-` | frame-length | table 1049, reports 2090, set_fps - | 0 |
| open | `t40/sc2232h.c` | 3.10.14 | 238 | `default_boot=0,sensor_max_fps=15,data_interface=DVP,video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 3024, reports 1500, set_fps 1038 | 0 |
| open | `t40/sc2232h.c` | 4.4.94 | 231 | `default_boot=0,sensor_max_fps=15,data_interface=DVP,video_interface=TISP_SENSOR_VI_DVP` | frame-length | table 3024, reports 1500, set_fps 1038 | 0 |
| open | `t23/sc223a.c` | 3.10.14 | 428 | `sensor_mipi_line=1` | frame-length | table 1200, reports 1440, set_fps 1200 | 0 |
| open | `t20/sc2300.c` | 3.10.14 | 327 | `-` | frame-length | table 1125, reports 2250, set_fps 1125 | 0 |
| open | `t31/sc2310.c` | 3.10.14 | 2358 | `sensor_max_fps=25,data_interface=MIPI,data_type=DATA_TYPE_WDR_DOL` | frame-length | table 2250, reports 6752, set_fps 1472 | 0 |
| open | `t31/sc2310.c` | 3.10.14 | 2372 | `sensor_max_fps=15,data_interface=MIPI,data_type=DATA_TYPE_WDR_DOL` | frame-length | table 4704, reports 6752, set_fps 4800 | 0 |
| open | `t40/sc2310.c` | 3.10.14 | 365 | `-` | frame-length | table 2250, reports 1440, set_fps 1350 | 0 |
| open | `t31/sc2310.c` | 4.4.94 | 2344 | `sensor_max_fps=25,data_interface=MIPI,data_type=DATA_TYPE_WDR_DOL` | frame-length | table 2250, reports 6752, set_fps 1472 | 0 |
| open | `t31/sc2310.c` | 4.4.94 | 2358 | `sensor_max_fps=15,data_interface=MIPI,data_type=DATA_TYPE_WDR_DOL` | frame-length | table 4704, reports 6752, set_fps 4800 | 0 |
| open | `t40/sc2310.c` | 4.4.94 | 357 | `-` | frame-length | table 2250, reports 1440, set_fps 1350 | 0 |
| open | `t40/sc2310s1.c` | 3.10.14 | 365 | `-` | frame-length | table 2250, reports 1440, set_fps 1350 | 0 |
| open | `t40/sc2310s1.c` | 4.4.94 | 357 | `-` | frame-length | table 2250, reports 1440, set_fps 1350 | 0 |
| open | `t40/sc2310s2.c` | 3.10.14 | 360 | `-` | frame-length | table 2250, reports 1440, set_fps 1350 | 0 |
| open | `t40/sc2310s2.c` | 4.4.94 | 352 | `-` | frame-length | table 2250, reports 1440, set_fps 1350 | 0 |
| open | `t40/sc2310s3.c` | 3.10.14 | 360 | `-` | frame-length | table 2250, reports 1440, set_fps 1350 | 0 |
| open | `t40/sc2310s3.c` | 4.4.94 | 352 | `-` | frame-length | table 2250, reports 1440, set_fps 1350 | 0 |
| open | `t23/sc2315e.c` | 3.10.14 | 256 | `sensor_max_fps=25,data_interface=DVP` | frame-length | table 1500, reports 1350, set_fps 1500 | 0 |
| open | `t31/sc2315e.c` | 3.10.14 | 263 | `sensor_max_fps=25,data_interface=DVP` | frame-length | table 1500, reports 1350, set_fps 1500 | 0 |
| open | `t31/sc2315e.c` | 4.4.94 | 250 | `sensor_max_fps=25,data_interface=DVP` | frame-length | table 1500, reports 1350, set_fps 1500 | 0 |
| open | `t23/sc2337p.c` | 3.10.14 | 1360 | `sensor_max_fps=25` | frame-length | table 1800, reports 1440, set_fps - | 0 |
| open | `t23/sc3332p.c` | 3.10.14 | 329 | `-` | frame-length | table 2640, reports 1320, set_fps 2640 | 0 |
| open | `t31/sc3336.c` | 4.4.94 | 1462 | `sensor_resolution=RES_100` | frame-length | table 1360, reports 1320, set_fps 660 | 0 |
| open | `t41zrt/sc401ai.c` | 3.10.14 | 1298 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 2640, reports 2460, set_fps 2640 | 0 |
| open | `t41zrt/sc401ai.c` | 4.4.94 | 1287 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 2640, reports 2460, set_fps 2640 | 0 |
| open | `t41/sc401ais1.c` | 3.10.14 | 1371 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 3301, reports 2000, set_fps 0 | 0 |
| open | `t41/sc401ais1.c` | 3.10.14 | 1384 | `default_boot=3,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 3300, reports 2000, set_fps 0 | 0 |
| open | `t41/sc401ais1.c` | 4.4.94 | 1365 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 3301, reports 2000, set_fps 0 | 0 |
| open | `t41/sc401ais1.c` | 4.4.94 | 1378 | `default_boot=3,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 3300, reports 2000, set_fps 0 | 0 |
| open | `t40/sc4210.c` | 3.10.14 | 494 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1562, reports 1800, set_fps 1560 | 0 |
| open | `t41/sc4210.c` | 3.10.14 | 517 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1562, reports 1500, set_fps 1562 | 0 |
| open | `t41/sc4210.c` | 3.10.14 | 517 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1800, reports 1500, set_fps 1800 | 0 |
| open | `t41/sc4210.c` | 3.10.14 | 1792 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1800, reports 1500, set_fps 1800 | 0 |
| open | `t40/sc4210.c` | 4.4.94 | 488 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1562, reports 1800, set_fps 1560 | 0 |
| open | `t41/sc4210.c` | 4.4.94 | 511 | `default_boot=0,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1562, reports 1500, set_fps 1562 | 0 |
| open | `t41/sc4210.c` | 4.4.94 | 511 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1800, reports 1500, set_fps 1800 | 0 |
| open | `t41/sc4210.c` | 4.4.94 | 1785 | `default_boot=2,video_interface=TISP_SENSOR_VI_MIPI_CSI0\|TISP_SENSOR_VI_MIPI_CSI1` | frame-length | table 1800, reports 1500, set_fps 1800 | 0 |
| open | `t40/sc4236.c` | 3.10.14 | 210 | `-` | frame-length | table 1920, reports 2000, set_fps 1920 | 0 |
| open | `t31/sc4236.c` | 4.4.94 | 205 | `-` | frame-length | table 1920, reports 2000, set_fps 1920 | 0 |
| open | `t40/sc4236.c` | 4.4.94 | 203 | `-` | frame-length | table 1920, reports 2000, set_fps 1920 | 0 |
| open | `t31/sc450ai.c` | 3.10.14 | 557 | `sensor_max_fps=25` | frame-length | table 1872, reports 3736, set_fps 1872 | 0 |
| open | `t31/sc450ai.c` | 3.10.14 | 557 | `sensor_max_fps=30` | frame-length | table 1560, reports 3736, set_fps 1560 | 0 |
| open | `t31/sc450ai.c` | 4.4.94 | 544 | `sensor_max_fps=25` | frame-length | table 1872, reports 3736, set_fps 1872 | 0 |
| open | `t31/sc450ai.c` | 4.4.94 | 544 | `sensor_max_fps=30` | frame-length | table 1560, reports 3736, set_fps 1560 | 0 |
| open | `t31/sc5235.c` | 4.4.94 | 1617 | `data_interface=MIPI,sensor_resolution=SENSOR_RES_400,data_type=DATA_TYPE_LINEAR` | frame-length | table 1500, reports 1650, set_fps 1500 | 0 |
| open | `t41/sc5239.c` | 3.10.14 | 1217 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 4000, reports 8000, set_fps 4000 | 0 |
| open | `t41/sc5239.c` | 4.4.94 | 1211 | `default_boot=1,video_interface=TISP_SENSOR_VI_MIPI_CSI0` | frame-length | table 4000, reports 8000, set_fps 4000 | 0 |
| open | `t40/sc8238.c` | 3.10.14 | 428 | `default_boot=2` | frame-length | table 2500, reports 2250, set_fps 2500 | 0 |
| open | `t40/sc8238.c` | 4.4.94 | 421 | `default_boot=2` | frame-length | table 2500, reports 2250, set_fps 2500 | 0 |

## Medium findings

One row per file, with the number of findings of each check. The detail is one
command away: `python3 tools/check_sensor_modes.py --driver <folder>/<sensor> --modes`.

- `frame-length` (medium): the table and `total_height` disagree, but `set_fps`
  sides with `total_height`: the line time is right once `set_fps` has run, and
  the sensor starts at another rate than the mode states.
- `fps-clock`: the driver's clock constant over its line length gives another
  frame than `total_height` at the mode's rate.
- `fps-range`: `set_fps` rejects the mode's own rate.
- `integration-limit`: an exposure limit is longer than the frame.
- `image-size`: the window and the bus image size disagree.
- `dup-enum`: two mode constants have the same value in that SoC's header.

| Status | Driver | Kernel | Findings | Profiles |
|---|---|---|---|---|
| open | `t23/sc2336p.c` | 3.10.14 | image-size 1 | 12 |
| open | `t41/gc4023.c` | 4.4.94 | integration-limit 1 | 5 |
| open | `t40/imx307.c` | 4.4.94 | fps-range 1 | 4 |
| open | `t41/gc5603.c` | 4.4.94 | fps-clock 1 | 3 |
| open | `t31/jxf37.c` | 3.10.14 | fps-clock 2 | 3 |
| open | `t40/gc4653.c` | 4.4.94 | fps-clock 1 | 2 |
| open | `t31/gc2053.c` | 4.4.94 | dup-enum 1 | 1 |
| open | `t31/gc2063.c` | 3.10.14 | frame-length 1 | 1 |
| open | `t31/os03b10.c` | 3.10.14 | fps-range 1 | 1 |
| open | `t21/sc2232h.c` | 3.10.14 | frame-length 1 | 1 |
| open | `t31/sc2336p.c` | 3.10.14 | image-size 1 | 1 |
| open | `t32/sc4336p.c` | 4.4.94 | fps-clock 1 | 1 |
| open | `t31/bf3a03.c` | 3.10.14 | fps-clock 1, integration-limit 1 | 0 |
| open | `t31/bf3a03.c` | 4.4.94 | fps-clock 1, integration-limit 1 | 0 |
| open | `t23/c4390.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t31/c4390.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t31/c4390.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t32/gc02m1.c` | 3.10.14 | frame-length 1, image-size 1 | 0 |
| open | `t32/gc02m1.c` | 4.4.94 | frame-length 1, image-size 1 | 0 |
| open | `t20/gc1034.c` | 3.10.14 | integration-limit 1 | 0 |
| open | `t31/gc2023.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t31/gc2023.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t21/gc2053.c` | 3.10.14 | fps-range 1 | 0 |
| open | `t40/gc2053.c` | 3.10.14 | fps-range 1 | 0 |
| open | `t40/gc2053.c` | 4.4.94 | fps-range 1 | 0 |
| open | `t40/gc2053s1.c` | 3.10.14 | fps-range 1 | 0 |
| open | `t40/gc2053s1.c` | 4.4.94 | fps-range 1 | 0 |
| open | `t41zrt/gc2063.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t31/gc2063.c` | 4.4.94 | dup-enum 1, frame-length 1 | 0 |
| open | `t41zrt/gc2063.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t40/gc2083.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t40/gc2083.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t23/gc2093.c` | 3.10.14 | integration-limit 1 | 0 |
| open | `t31/gc2093.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t31/gc2093.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t41/gc4023.c` | 3.10.14 | integration-limit 1 | 0 |
| open | `t40/gc4653.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t41zrt/gc4653.c` | 3.10.14 | fps-range 2 | 0 |
| open | `t41zrt/gc4653.c` | 4.4.94 | fps-range 2 | 0 |
| open | `t40/gc4653s1.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t40/gc4653s1.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t40/gc5603.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t41/gc5603.c` | 3.10.14 | frame-length 2 | 0 |
| open | `t40/gc5603.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t41/gc5603s0.c` | 4.4.94 | frame-length 2 | 0 |
| open | `t40/gc5603s1.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t41/gc5603s1.c` | 3.10.14 | frame-length 2 | 0 |
| open | `t40/gc5603s1.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t41/gc5603s1.c` | 4.4.94 | frame-length 2 | 0 |
| open | `t32/imx179.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t32/imx179.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t20/imx225.c` | 3.10.14 | integration-limit 1 | 0 |
| open | `t40/imx307.c` | 3.10.14 | fps-range 1 | 0 |
| open | `t40/imx335.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t40/imx335.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t40/imx347.c` | 3.10.14 | fps-range 1 | 0 |
| open | `t40/imx347.c` | 4.4.94 | fps-range 1 | 0 |
| open | `t40/imx385.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t40/imx385.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t40/imx386.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t40/imx386.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t30/jxf22.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t40/jxf23.c` | 3.10.14 | fps-clock 6 | 0 |
| open | `t40/jxf23.c` | 4.4.94 | fps-clock 6 | 0 |
| open | `t31/jxf28p.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t31/jxf28p.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t31/jxf32.c` | 3.10.14 | image-size 1 | 0 |
| open | `t40/jxf32.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t31/jxf32.c` | 4.4.94 | image-size 1 | 0 |
| open | `t40/jxf32.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t23/jxf35.c` | 3.10.14 | fps-clock 1, fps-range 1 | 0 |
| open | `t40/jxf35.c` | 3.10.14 | fps-clock 2 | 0 |
| open | `t40/jxf35.c` | 4.4.94 | fps-clock 2 | 0 |
| open | `t23/jxf37.c` | 3.10.14 | fps-clock 2 | 0 |
| open | `t40/jxf37.c` | 3.10.14 | fps-clock 1, fps-range 2 | 0 |
| open | `t41/jxf37.c` | 3.10.14 | fps-clock 1, fps-range 2 | 0 |
| open | `t41zrt/jxf37.c` | 3.10.14 | fps-clock 2, fps-range 2 | 0 |
| open | `t31/jxf37.c` | 4.4.94 | fps-clock 2 | 0 |
| open | `t40/jxf37.c` | 4.4.94 | fps-clock 1, fps-range 2 | 0 |
| open | `t41/jxf37.c` | 4.4.94 | fps-clock 1, fps-range 2 | 0 |
| open | `t41zrt/jxf37.c` | 4.4.94 | fps-clock 2, fps-range 2 | 0 |
| open | `t23/jxf37p.c` | 3.10.14 | fps-clock 2 | 0 |
| open | `t23/jxf37pas0.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t23/jxf37pas1.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t40/jxf37s1.c` | 3.10.14 | fps-clock 1, fps-range 2 | 0 |
| open | `t40/jxf37s1.c` | 4.4.94 | fps-clock 1, fps-range 2 | 0 |
| open | `t31/jxf51.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t31/jxf51.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t31/jxf53.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t31/jxf53.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t23/jxf57.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t31/jxh63.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t40/jxh63.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t31/jxh63.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t40/jxh63.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t40/jxh63s1.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t40/jxh63s1.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t31/jxh66.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t31/jxh66.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t40/jxk04.c` | 3.10.14 | integration-limit 2 | 0 |
| open | `t40/jxk04.c` | 4.4.94 | integration-limit 2 | 0 |
| open | `t32/jxk06.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t32/jxk06.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t40/jxk08.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t41/jxk08.c` | 3.10.14 | fps-clock 1, fps-range 1 | 0 |
| open | `t40/jxk08.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t41/jxk08.c` | 4.4.94 | fps-clock 1, fps-range 1 | 0 |
| open | `t23/jxk306p.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t40/mis2008.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t40/mis2008.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t23/mis2009.c` | 3.10.14 | fps-clock 2 | 0 |
| open | `t41/mis2009.c` | 3.10.14 | fps-clock 2 | 0 |
| open | `t41/mis2009.c` | 4.4.94 | fps-clock 2 | 0 |
| open | `t31/os03b10.c` | 4.4.94 | fps-range 1 | 0 |
| open | `t23/os04c10.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t31/os04c10.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t31/os04c10.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t31/os04l10.c` | 3.10.14 | integration-limit 1 | 0 |
| open | `t31/os04l10.c` | 4.4.94 | integration-limit 1 | 0 |
| open | `t23/os05a10.c` | 3.10.14 | fps-clock 2 | 0 |
| open | `t31/os05a10.c` | 3.10.14 | fps-clock 2 | 0 |
| open | `t40/os05a10.c` | 3.10.14 | fps-clock 4, fps-range 4 | 0 |
| open | `t31/os05a10.c` | 4.4.94 | fps-clock 2 | 0 |
| open | `t40/os05a10.c` | 4.4.94 | fps-clock 4, fps-range 4 | 0 |
| open | `t40/os05a10s1.c` | 3.10.14 | fps-clock 6, fps-range 2 | 0 |
| open | `t40/os05a10s1.c` | 4.4.94 | fps-clock 6, fps-range 2 | 0 |
| open | `t40/ov01a1s.c` | 3.10.14 | fps-clock 2 | 0 |
| open | `t40/ov01a1s.c` | 4.4.94 | fps-clock 2 | 0 |
| open | `t40/ov02b10.c` | 3.10.14 | integration-limit 2 | 0 |
| open | `t40/ov02b10.c` | 4.4.94 | integration-limit 2 | 0 |
| open | `t40/ov02b1b.c` | 3.10.14 | integration-limit 2 | 0 |
| open | `t40/ov02b1b.c` | 4.4.94 | integration-limit 2 | 0 |
| open | `t30/ov2732.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t41/ov2740.c` | 4.4.94 | fps-range 1 | 0 |
| open | `t31/ov2745.c` | 3.10.14 | fps-range 1 | 0 |
| open | `t31/ov2745.c` | 4.4.94 | fps-range 1 | 0 |
| open | `t31/ps5268.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t31/ps5268.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t23/ps5270.c` | 3.10.14 | fps-range 1 | 0 |
| open | `t30/ps5270.c` | 3.10.14 | fps-range 1 | 0 |
| open | `t31/ps5270.c` | 3.10.14 | fps-range 2 | 0 |
| open | `t31/ps5270.c` | 4.4.94 | fps-range 2 | 0 |
| open | `t40/sc035hgs.c` | 3.10.14 | fps-range 1 | 0 |
| open | `t40/sc035hgs.c` | 4.4.94 | fps-range 1 | 0 |
| open | `t31/sc1346.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t31/sc1346.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t20/sc2035.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t41/sc2210.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t41/sc2210.c` | 4.4.94 | frame-length 1 | 0 |
| open | `t30/sc2232h.c` | 3.10.14 | frame-length 1 | 0 |
| open | `t23/sc223a.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t31/sc2310.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t31/sc2310.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t41/sc301iot.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t41/sc301iot.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t41zrt/sc401ai.c` | 3.10.14 | integration-limit 1 | 0 |
| open | `t41zrt/sc401ai.c` | 4.4.94 | integration-limit 1 | 0 |
| open | `t41/sc4210.c` | 3.10.14 | integration-limit 2 | 0 |
| open | `t41/sc4210.c` | 4.4.94 | integration-limit 2 | 0 |
| open | `t40/sc430ai.c` | 3.10.14 | integration-limit 2 | 0 |
| open | `t41/sc430ai.c` | 3.10.14 | integration-limit 2 | 0 |
| open | `t40/sc430ai.c` | 4.4.94 | integration-limit 2 | 0 |
| open | `t41/sc430ai.c` | 4.4.94 | integration-limit 2 | 0 |
| open | `t32/sc4336p.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t41/sc450ai.c` | 3.10.14 | image-size 1 | 0 |
| open | `t41/sc450ai.c` | 4.4.94 | image-size 1 | 0 |
| open | `t41/sc500ai.c` | 3.10.14 | fps-range 2 | 0 |
| open | `t41/sc500ai.c` | 4.4.94 | fps-range 2 | 0 |
| open | `t41/sc500ais1.c` | 3.10.14 | fps-range 2 | 0 |
| open | `t41/sc500ais1.c` | 4.4.94 | fps-range 2 | 0 |
| open | `t30/sc5235.c` | 3.10.14 | fps-range 1 | 0 |
| open | `t32/sc635hai.c` | 3.10.14 | fps-clock 1 | 0 |
| open | `t32/sc635hai.c` | 4.4.94 | fps-clock 1 | 0 |
| open | `t20/sp1409.c` | 3.10.14 | fps-clock 1 | 0 |

## Not analysed

- `3.10.14/sensor-src/t23/gc4653.c`: parse: the source's brackets do not pair up: '}' at line 740 closes '(' opened at line 737 (does this file compile?)

## Done

Rows leave the tables above when their fix is merged, and are listed here.

| Driver | Kernel | Mode | Fix | Measured on |
|---|---|---|---|---|
| `t31/gc2053.c` | 3.10.14, 4.4.94 | `sensor_max_fps=30,data_interface=MIPI` | [ingenic-sdk#13](https://github.com/thingino/ingenic-sdk/pull/13): reports the 1181 lines the table programs, was 1418 | `wyze_campan3_t31x_gc2053_atbm6031` |
