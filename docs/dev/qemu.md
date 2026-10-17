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

## Commands

| Command | What it does |
| --- | --- |
| `images` | the built images under the output root, with their SoCs |
| `up CAMERA\|IMAGE` | boot an image; returns at a root shell (about a minute) |
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
| `adc [NAME] [CH[=SAMPLE] ...]` | the samples the ADC channels convert, or set one |
| `console [NAME]` | attach your terminal to the console; Ctrl-] detaches |
| `info [NAME]`, `ls`, `down [NAME\|--all]` | show, list and stop sessions |

`NAME` can be left out while only one session runs. `images`, `ls`, `info`
and `up` print JSON with `--json`. `scripts/qemu-dev <command> --help`
lists every option.

## Booting

`up` takes a camera name, meaning its newest build under the output root
(`THINGINO_OUTPUT_ROOT_DIR` and `THINGINO_OUTPUT_DIR` are honoured, as they
are by make), or the path to any image, release images included. The SoC
comes from the build's `.config`, or else from the SoC in the camera name;
`--soc` overrides both. The QEMU machine and SoC variant follow from it.

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
- `--uboot` stops at the U-Boot prompt instead of booting Linux.
- `--no-wait` returns as soon as QEMU runs; `wait` logs in later.
- Anything after `--` goes to QEMU as it is.

A SPI NAND image (its boot header says so) boots on the T40, T41 and A1
with a 128 MiB GigaDevice GD5F1GQ5UE for its flash, a chip the SPL,
U-Boot and Linux of a NAND build all know. The flash copy is padded to the
whole chip, erased, for the UBI volumes to grow into. NAND needs a
qemu-ingenic release newer than ingenic-0.6.11.

## Getting in

Commands run on the serial console, as they would over a board's UART: on
every image, during failsafe, and with the network down or being
reconfigured. Standard output and standard error arrive together, and a
kernel message printed meanwhile lands in the output too.

When the image has a wired interface, the camera's SSH, HTTP and HTTPS are
also forwarded to ports on 127.0.0.1, and `put` and `get` use SSH with a
key the session installs, which is far faster than the console. `info`
prints the ports, the web UI address with its login, and an ssh command
line for your own use. Images without a wired interface, Wi-Fi cameras
among them, cannot be reached from the host (a Wi-Fi test image has a
simulated radio inside, but nothing outside it), so files go over the
console too: a few seconds per 100 KB instead of well under a second,
still binary-safe and checked with md5sum.

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

Both need a qemu-ingenic release newer than ingenic-0.6.11; with that
one they say so and stop.

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
  Real camera images boot as well, but nothing emulates their sensor or
  radio, and board details such as an SD card-detect pin may not match.
- The guest runs under TCG: its timing is not the hardware's.
- The emulated NAND never wears: no bitflips, no bad blocks, and its
  spare areas are blank again whenever QEMU starts.
- The console is UART1 on most cameras and UART0 on a few; `up` takes
  whichever speaks first.
