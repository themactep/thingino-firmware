# pstore / ramoops (kernel log across a reset)

`BR2_THINGINO_RAMOOPS=y` (T20, T21, T23, T31; kernel 3.10.14, T31 also 4.4.94) is strictly opt-in
(default off, no camera defconfig sets it; a build without it is unchanged). Enable it per camera,
e.g. in a local fragment or your own defconfig: `BR2_THINGINO_RAMOOPS=y` (optionally
`BR2_THINGINO_RAMOOPS_KB=128`). It keeps the last kernel
messages over a panic, oops or watchdog reset in `/sys/fs/pstore`.

* `thingino-kopt` enables `PSTORE`, `PSTORE_CONSOLE` and `PSTORE_RAM` via `LINUX_CONFIG_FIXUPS` only with the option.
* `package/thingino-uboot/files/ramoops-env.sh` shortens `osmem` in the generated `uenv.txt` by
  `BR2_THINGINO_RAMOOPS_KB` (default 128 KB, written as `osmem=<n>K@0x0`) and adds
  `ramoops.mem_address/mem_size/console_size/record_size/dump_oops` to the bootargs. The area sits
  between `osmem` and `rmem` (T20/T21: between `osmem` and `ispmem`), so Linux never maps it.
  Example (T23, 64 MB, rmem 22M): `osmem=42880K@0x0`, `ramoops.mem_address=0x29e0000`.
* `/etc/init.d/S01pstore` (installed only with the option) mounts `pstore` on `/sys/fs/pstore`.

Whether the SoC's DRAM keeps its content across a watchdog reset is not documented; test it:

1. Boot, `echo c > /proc/sysrq-trigger` (panic, `panic=` seconds later the board resets).
2. After the reboot `ls /sys/fs/pstore`: `console-ramoops-0` and `dmesg-ramoops-0` hold the old log.
3. Same with the watchdog: stop feeding `/dev/watchdog` and compare.

An existing device keeps its old U-Boot environment; a full OTA that rewrites the env, or
`fw_setenv`, is needed to get the new `osmem` and bootargs.
