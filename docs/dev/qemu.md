# Running Images in QEMU

`scripts/qemu-dev` boots a thingino firmware image under the
[Ingenic QEMU fork](https://github.com/gtxaspec/qemu) and keeps it running
in the background, so a change can be tried without a camera. Each command
is a plain shell command with a plain exit status, so it works the same
typed by hand, run from a script, or used by a coding agent; nothing needs
a terminal or a person at the console. It only ever touches the emulated
camera.

For the automated test suite that runs on the same machinery, see
[`scripts/qemu-test/README.md`](../../scripts/qemu-test/README.md).

## Quick start

```bash
make GROUP=testing CAMERA=qemu_t31x_eth fast   # build a QEMU test profile
scripts/qemu-dev up qemu_t31x_eth              # boot it; returns at a root shell
scripts/qemu-dev sh -- 'cat /proc/cmdline'     # run a command on it
scripts/qemu-dev down                          # stop it
```

To watch a boot from its first line and type at it, stock firmware
included:

```bash
scripts/qemu-dev up dump.bin --soc t31l --console   # Ctrl-] detaches
```

## Commands

| Command | What it does |
| --- | --- |
| `images` | the built images under the output root, with their SoCs |
| `up CAMERA\|IMAGE` | boot an image; returns at a root shell (about a minute), or with `--console` attaches you from power-on |
| `sh [NAME] -- CMD` | run `CMD` on the camera; exits with its status |
| `put [NAME] LOCAL REMOTE` | copy a file onto the camera (`REMOTE` may be a directory) |
| `get [NAME] REMOTE LOCAL` | copy a file off it |
| `log [NAME]` | the console output: `-n N` lines, `--boot` for all of the current boot, `-f` to follow |
| `reboot [NAME]` | reboot and wait for the shell; `--hard` resets the machine instead, `--uboot` stops at the U-Boot prompt, `--no-wait` returns at once |
| `uboot [NAME] -- CMD` | run a U-Boot command at that prompt and exit with its status; `uboot -- boot` goes on to Linux and waits for the shell |
| `wait [NAME]` | wait for the shell, after `up --no-wait` or `reboot --no-wait` |
| `send [NAME] -- TEXT` | type at the console, as a person would; see below |
| `monitor [NAME] -- COMMAND` | a QEMU monitor command, such as `info registers` |
| `gpio [NAME] [PIN[=0\|1] ...]` | the pins set up as GPIO, or drive an input from outside; see below |
| `gpio [NAME] --log\|--watch\|--serve` | every pin change, listed, followed or on a live page; `--vcd FILE` writes a waveform; see below |
| `adc [NAME] [CH[=SAMPLE] ...]` | the samples the ADC channels convert, or set one |
| `console [NAME]` | attach your terminal to the console; Ctrl-] detaches, `--all` prints everything since power-on first |
| `info [NAME]`, `ls`, `down [NAME\|--all]` | show, list and stop sessions |

`NAME` can be left out while only one session runs. `images`, `ls`, `info`
and `up` print JSON with `--json`. `scripts/qemu-dev <command> --help`
lists every option.

## Booting

`up` takes a camera name, meaning its newest build under the output root
(`THINGINO_OUTPUT_ROOT_DIR` and `THINGINO_OUTPUT_DIR` are honoured, as they
are by make), or the path to any image: a release image, or a stock
firmware dump of 16, 32 or 64 MiB of NOR. The SoC comes from the build's
`.config`, or else from the SoC in the camera name; `--soc` overrides both,
and names it for a dump. The QEMU machine and SoC variant follow from it.

QEMU is always the release `package/qemu-ingenic` pins. If the image's
build tree was built with that pin, its QEMU is used; otherwise the
release is downloaded once into `~/.cache/thingino/qemu-ingenic/` and
checked against the pinned hash. `--qemu` or `QEMU_BIN` points at another
binary. The release binary needs glib, pixman and libslirp on the host
(`libpixman-1-0 libslirp0` on Debian and Ubuntu).

Each `up` boots a fresh copy of the image's flash, and the image itself is
never written, so a rebuild is picked up by the next `up`. Running `up`
again for a session that is already up replaces it. Other options:

- `--keep` boots the flash as the last session left it, to test what
  survives a power cycle.
- `--sd card.img` puts an SD card in MSC0; that file is written in place.
  The slot's card-detect switch holds its pin low from power-on, so
  U-Boot sees the card too: the pin is `gpio.mmc_cd` in the camera's
  thingino.json, or for a stock image MSC0's in its kernel's device tree
  (the 4.4 kernels have one). `--sd-cd PB26` names it when neither says,
  `--sd-cd none` leaves it. The pinned QEMU does this from
  ingenic-0.6.17 on; with an older one, insert the card with `gpio` once
  Linux is up.
- `--wifi SSID:PASS` gives the camera its Wi-Fi chip and an access point to
  join (see Wi-Fi).
- `--portal` leaves the camera in its setup portal, with an emulated phone
  joined to it (see Wi-Fi).
- `--uboot` stops at the U-Boot prompt instead of booting Linux.
- `--no-wait` returns as soon as QEMU runs; `wait` logs in later.
- `--console` attaches your terminal to the console with all of the
  boot, from the first line the SPL prints; for a stock image, which
  qemu-dev cannot log into, this is how to watch it.
- Anything after `--` goes to QEMU as it is.

A SPI NAND image (its boot header says so) boots with a 128 MiB
GigaDevice GD5F1GQ5UE for its flash, a chip the SPL, U-Boot and Linux of
thingino's and Ingenic's NAND builds know. The flash copy is padded to the
whole chip, erased, for the UBI volumes to grow into.

## Getting in

Commands run on the serial console, as they would over a board's UART: on
every image, during failsafe, and with the network down or being
reconfigured. Standard output and standard error arrive together, and a
kernel message printed meanwhile lands in the output too.

When the image has a wired interface, the camera's SSH, HTTP and HTTPS are
also forwarded to ports on 127.0.0.1, and `put` and `get` use SSH with a
key the session installs, which is far faster than the console. `info`
prints the ports, the web UI address with its login, and an ssh command
line for your own use. Images without a wired interface cannot be
reached from the host unless they come up on Wi-Fi (`--wifi`), so files
go over the console too: a few seconds per 100 KB instead of well under a
second, still binary-safe and checked with md5sum.

## Wi-Fi

`--wifi SSID:PASS` adds the camera's Wi-Fi chip to the machine, with a
WPA2 access point of that SSID and passphrase behind it, and sets the
camera up to join it:

```sh
scripts/qemu-dev up wyze_cam3_t31x_gc2053_atbm6031 --wifi thingino:thingino123 \
    -- -device image-sensor,model=gc2053,bus=i2c0
```

The chip comes from the build's `.config`, or from the camera name for a
release image; `--wifi-chip` overrides both. AltoBeam's ATBM60xx chips are
emulated, on SDIO (atbm6031, atbm6062s, atbm6162s) and on USB (atbm6012b,
atbm6012bx, atbm6032, atbm6132u, atbm6062u, atbm6062cu, atbm6132cu,
atbm6132cu-6162), and Realtek's RTL8189FS, RTL8189ES and RTL8192FS on SDIO
(rtl8189fs, rtl8189es, rtl8192fs; cameras named rtl8189ftv and rtl8189etv)
and RTL8188FU on USB (rtl8188fu; cameras named rtl8188ftv), the
Broadcom/Synaptics BCM43438 of the syn4343 package on SDIO, iComm-semi's
SSV6155P on USB (cameras named ssv6155 and ssv6155p, and the SSV6256P
ones, whose driver is the same), SSV6355 on USB (ssv6355) and SSV6158 on
SDIO (ssv6158), and AICSemi's AIC8800D80 on USB (the aic8800 package's
AIC8800D80 USB model, and cameras named aic8800u; an AIC8800D40, which its
driver takes for one, too). The pinned QEMU has them all from
ingenic-0.6.16 on; `up` stops with a message when the QEMU it uses has
no model for the chip, and `--qemu` picks one that has.
atbm6132cu-6162 is the 6132CU part paired with Bluetooth, on USB id
0x6162: a build with `BR2_PACKAGE_WIFI_ATBM6132CU_6162` gets it, a
release image of such a camera only with `--wifi-chip`, though its
driver takes either id.

thingino reads its Wi-Fi mode once, at boot, so the first `up` of a
camera that was not set up for the SSID runs `wlan configure` and reboots
it onto the access point; with `--keep` it is set up already. The camera
then scans, associates, completes the WPA2 handshake and takes a DHCP
address as it would at home. A camera with a wired port too stops its
Wi-Fi while the port has a link, so `--wifi` and `--portal` start it with
the cable out. SSH, HTTP and HTTPS are then forwarded over the Wi-Fi,
and `put` and `get` go over SSH. A wrong passphrase fails the handshake
as a real access point does.

`--portal` tests the setup portal instead: the camera keeps its first-boot
Wi-Fi mode, an access point of its own, and an emulated phone joins it.
The forwards go through the phone, so the web address `up` prints is the
portal, and SSH reaches the camera too; when SSH cannot get through the
phone, `up` says so and files go over the console. With `--wifi`, the
portal's scan lists that network and can set the camera up on it:

```sh
scripts/qemu-dev up wyze_cam3_t31x_gc2053_atbm6031 --portal --wifi thingino:thingino123 \
    -- -device image-sensor,model=gc2053,bus=i2c0
```

Saving in the portal reboots the camera; the next command logs in again,
and once the camera has joined, the forwards move onto that network.

## Commands, files and reboots

`sh` runs its command the way `ssh` does: the words after `--` are joined
and run by the camera's `/bin/sh`, so quote what the camera should see.
It exits with the command's status, 124 when `--timeout` (120 s by
default) runs out, and 255 when the camera resets under the command.

Reboot with `reboot`, which waits until the camera is back at a shell.
When the camera resets on its own, from a crash, a watchdog or a `reboot`
run through `sh`, the next command waits for the new boot and logs in
again. A session left at the U-Boot prompt says so and refuses `sh`;
`uboot -- boot` or `reboot` gets it back to Linux.

## Driving the console

Everything a person would do at the console can be done with `send`. It
types its text exactly as given (`\n` is Enter, `\xHH` any byte,
`\x03` Ctrl-C) and prints the last 40 lines the console shows after it;
the rest is in `log`. `--expect` waits for a pattern in that output and
exits 124 if it never comes, `--after` waits for one before typing, and
`--repeat` types the text again every so many seconds until `--expect`
matches.

```bash
# answer a program's questions
scripts/qemu-dev send --expect 'name\? $' -- 'printf "name? "; read x; echo "got $x"\n'
scripts/qemu-dev send --expect 'got bob' -- 'bob\n'

# thingino's failsafe mode: press f once the kernel starts
scripts/qemu-dev reboot --no-wait
scripts/qemu-dev send --after 'Starting kernel' --repeat 0.3 --expect 'Failsafe mode' --timeout 120 -- f

# stop at U-Boot by hand, then go on with uboot
scripts/qemu-dev reboot --no-wait
scripts/qemu-dev send --after 'U-Boot SPL' --repeat 0.1 --expect '(=>|#) $' -- '\x03'
scripts/qemu-dev uboot -- printenv bootcmd
```

Ctrl-C stops autoboot in U-Boot and clears a half-typed line at the shell
prompt, but it cannot stop a running command: the console is not the
shell's controlling terminal. A command started with `send` holds the
console until it ends. `sh` commands are ended by a timeout on the camera
itself, so the console always comes back. Start long-running jobs with
their output redirected (`daemon >/dev/null 2>&1 &`), or it lands in the
output of later commands.

`monitor` reaches QEMU itself: `info registers` shows where a hung guest
is, `set_link n0 off` and `set_link n0 on` pull and replug the network
cable, `stop` and `cont` pause and resume the machine, `system_reset` is
the reset button and `gdbserver` starts a gdb stub.

## Pins and the ADC

The camera's GPIO pins behave as on the silicon: an output reads back
what the camera drives, and an input reads what is driven onto it from
outside, high until a test says otherwise. `gpio` lists the pins set up
as GPIO with their mode and level, shows the pins named, or drives
inputs. A pin is `PB14` or its Linux GPIO number (`46`). Driving a pin
fires its interrupt as the hardware would, so a button press or a card
insertion reaches the camera's drivers. Pins no test has driven never
interrupt.

```bash
scripts/qemu-dev gpio                  # what the camera has set up
scripts/qemu-dev gpio PB28=0           # press a button wired to PB28 (active low) ...
scripts/qemu-dev gpio PB28=1           # ... and let go
scripts/qemu-dev gpio 50=0             # assert a card-detect pin, by GPIO number
```

`adc` does the same for the SADC's eight channels: `adc 0=150` makes
channel 0 read 150 of 4095, a dark room to a photoresistor (raptor's
`ric` reads one in its adc trigger mode). Every channel starts at 2025.

`gpio --log` lists every pin change since the session came up: when, the
pin, what it was and now is, and the guest PC that changed it (`ext` when
it was driven from outside). `--watch` goes on printing changes as they
happen, and `--vcd FILE` writes them as a waveform for PulseView or
GTKWave, where a pin in a device function reads `z`. A device function
is named from Ingenic's pinout sheet for the SoC, or its datasheet where
there is no sheet; the T20, the T10 die with other clocks, uses the T10
datasheet with the names its reference schematic adds
(`scripts/qemu-test/make-pin-tables.py` makes the tables). The T10, T21
and T30 datasheets don't number the functions. The vendor kernels and
the order the datasheets list them in fix most numbers; a name ending in
`?` has a guessed one.
Sessions log pin changes from QEMU ingenic-0.6.15 on.

```bash
scripts/qemu-dev gpio --log
#  12.041784  PA18   18  reset state -> out 1  0x80017874
#  72.061851  PB28   60  in 1 -> in 0  ext
scripts/qemu-dev gpio --vcd boot.vcd
scripts/qemu-dev gpio --serve          # http://127.0.0.1:<port>/
```

`gpio --serve` puts the same on a live page: the SoC's pins in its
layout, coloured by what each is and flashing as it changes, a timeline,
the changes as they come, the console, and for a pin its functions, its
history and buttons that drive it from outside. The page can also set an
ADC channel and pause the machine.

## Video

The emulated camera streams once its session has the camera's image
sensor: give it after `--`, and the SoC's ISP and video encoder do the
rest, so raptor streams as it does on the board. Every T-series SoC and
the T40 and T41 stream from QEMU ingenic-0.6.14 on (the T31, T40 and T41
from ingenic-0.6.12).

```bash
scripts/qemu-dev up qemu_t31x_eth -- -device image-sensor,model=gc2053,bus=i2c0
```

The test profiles' sensors:

| Profile | After `-device image-sensor,` |
| --- | --- |
| `qemu_t10n` | `model=jxh42,bus=i2c0` |
| `qemu_t20x` | `model=jxf22,bus=i2c0` |
| `qemu_t21n` | `model=sc2232h,bus=i2c0` |
| `qemu_t23n` | `model=sc2336,bus=i2c0` |
| `qemu_t30x` | `model=sc4236,bus=i2c0` |
| `qemu_t31x*` | `model=gc2053,bus=i2c0` |
| `qemu_t32nq` | `model=cv8001,bus=i2c0` |
| `qemu_t40nn*` | `model=imx307,bus=i2c1` |
| `qemu_t41nq` | `model=gc4023,bus=i2c0` |

A real camera's image takes the sensor its defconfig names
(`BR2_SENSOR_1_NAME`). From QEMU ingenic-0.6.16 the fork has a model for
the sensor of every one-sensor camera, at the I2C address its driver
probes, and its `contrib/ingenic/README.md` lists them with the sensor's
options; the imx327 of the T23, T30 and T31 drivers answers at 0x36, so
give it `address=0x36`. Give it the sensor even when video is not the
point: without one, the vendor ISP driver can oops as the streamer
starts and hold up the boot. The sensor sees colour bars that a white
stripe crosses every two seconds.

A recording and a snapshot can be fetched from any image, wired or not.
`ringdump main -i` asks for a key frame and the recording starts with
it, give or take a frame or two that the player skips; `ringdump sub`
is the second stream:

```bash
scripts/qemu-dev sh -- 'ringdump main -i; ringdump main -d -s -n 60 > /tmp/main.h264'
scripts/qemu-dev sh -- 'ringdump jpeg0 -d -s -n 1 > /tmp/snap.jpg'
scripts/qemu-dev get /tmp/main.h264 main.h264
scripts/qemu-dev get /tmp/snap.jpg snap.jpg
ffplay main.h264
```

An image with a wired interface can be watched live over RTSP: `--fwd`
forwards a camera port, and `info` shows where it went.

```bash
scripts/qemu-dev up qemu_t31x_eth --fwd 554 -- -device image-sensor,model=gc2053,bus=i2c0
scripts/qemu-dev info                  # forwards 34399 -> 554
ffplay -rtsp_transport tcp rtsp://thingino:thingino@127.0.0.1:34399/ch0
```

If rvd logs `IMP_FrameSource_EnableChn(0) failed` or exits after
`enc_create_channel`, the image keeps too little memory for video (`rmem`
on the kernel command line). Give it more and reboot:

```bash
scripts/qemu-dev sh -- 'fw_setenv osmem 64M@0x0; fw_setenv rmem 64M@0x4000000'
scripts/qemu-dev reboot
```

That is for an XBurst1 SoC with 128 MB, which test images built before
the 128 MB profiles got 64 MB of rmem need. The T40 and T41 keep 8 MB of
nmem at the top: `osmem 56M@0x0` and `rmem 64M@0x3800000`. The 64 MB T21
needs `osmem 42M@0x0` and `rmem 22M@0x2a00000` even when built today.
The encoders run on the host CPU, so a 4K stream may run below the
sensor's frame rate.

## Iterating on a package

A package change can be tried without building and booting a new image:

```bash
make GROUP=testing CAMERA=qemu_t31x_eth rebuild-thingino-raptor
scripts/qemu-dev put output/<branch>/qemu_t31x_eth-<kernel>-<libc>/target/usr/bin/rsd /usr/bin/
scripts/qemu-dev sh -- '/etc/init.d/S31raptor restart'
```

Files put on the camera live in its overlay, so they survive `reboot`, and
the next `up` without `--keep` starts clean again.

## Sessions

Each session is one QEMU process with its own flash copy, console logs,
QMP socket and SSH key, kept under `$XDG_RUNTIME_DIR/thingino-qemu-dev/`
(`QEMU_DEV_DIR` moves it), plus a small relay that holds the console open
for as long as QEMU runs: QEMU stops reading a console pty for up to a
second each time its last reader closes it, which would slow every
command. Sessions are named after the camera; `--name`
runs two of the same. With more than one session up, give the name first:
`scripts/qemu-dev sh qemu_t31x_eth -- uptime`. One command at a time uses
a session's console and another waits its turn; SSH copies run alongside.
`down` stops a session and deletes its files.

## Limits

- The `qemu_*` profiles in `configs/cameras-testing/` are built for QEMU.
  Real camera images boot as well, and stream with their sensor (see
  Video), but only the radios under Wi-Fi are emulated, and board
  details may not match.
- The emulated phone of `--portal` joins open portals only.
- The guest runs under TCG: its timing is not the hardware's.
- The emulated NAND never wears: no bitflips, no bad blocks, and its
  spare areas are blank again whenever QEMU starts.
- The console is UART1 on most cameras and UART0 on a few, and some run
  U-Boot on one and Linux on the other; `up` follows the UART the
  kernel prints its banner on.
