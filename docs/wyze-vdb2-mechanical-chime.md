# Wyze Video Doorbell v2 mechanical chime

The Wyze Video Doorbell v2 drives its mechanical-chime interface directly
with GPIOs. The stock `iCamera` binary does not use `/dev/ttyUSB*` for this
path. Thingino exposes the recovered sequence through `vdb2-chime`.

## Reverse-engineering evidence

The addresses below are virtual addresses in the stock VDB2 `iCamera` ELF:

| Function or data | Address | Observed behavior |
| --- | ---: | --- |
| GPIO descriptor table | `0x7a7a00` | GPIOs 59, 52 and 53 are outputs; GPIOs 7 and 51 are inputs |
| `local_sdk_doorbell_init` | `0x442eb8` | Initializes GPIOs 59, 52, and 53 output-low in that order, then starts input polling |
| GPIO read helper | `0x44b5b8` | Reads `/sys/class/gpio/gpio%d/value` |
| GPIO write helper | `0x44b694` | Writes GPIO through sysfs |
| energy-ready helper | `0x443028` | Returns true when GPIO 51 is high; the handler logs `battery low` when it remains low |
| `local_sdk_doorbell_power_switch_battery` | `0x442f30` | GPIO 59 high, 30 ms, then GPIO 52 high |
| `local_sdk_doorbell_power_switch_mains` | `0x442fac` | GPIO 52 low, 30 ms, then GPIO 59 low |
| `local_sdk_doorbell_dingdong_power_on` | `0x443058` | GPIO 59 high, 30 ms, GPIO 52 high, 30 ms, GPIO 53 high |
| `local_sdk_doorbell_dingdong_power_off` | `0x443104` | GPIO 53 low, 1 s, GPIO 52 low, 30 ms, GPIO 59 low |
| doorbell button handler | `0x4313d0` | Checks GPIO 51, waits 500 ms + 1 s, applies the configured pulse, then powers off |
| `init_product` | `0x439f80` | Calls doorbell GPIO initialization late, after AI, audio, alarm, and video setup |

Stock diagnostic strings identify GPIOs 59 and 52 together as the supply switch
between battery and mains. That establishes their software role but not which
transistor or controller input each pin drives, so the Thingino configuration
retains the neutral names `stage1_gpio` and `stage2_gpio`. The separate battery
and mains helpers are otherwise called only by the factory charge-cycling path;
normal chime operation inlines the same transitions in the two dingdong power
helpers.

### Stock configuration path

The chime setting is ordinary persistent application state, not a second
hardware-control channel. During startup, `sub_439b44` passes a 161-entry
default table at `0x6d4e54` to `paracfg_user_config_init`. The three relevant
entries are:

| Stored key | Item ID | Compiled default | Live global | Handler behavior |
| --- | ---: | ---: | ---: | --- |
| `dingdong_type` | `0x9d` | 1 | `0x752344` | 1 skips the chime; 2 pulses for 200 ms; 3 uses `dingdong_response_time` |
| `dingdong_status` | `0x9e` | 1 | `0x752348` | The GPIO sequence is allowed only when this is 1 |
| `dingdong_response_time` | `0x9f` | 1 | `0x75234c` | Whole seconds passed to `sleep()` for type 3 |

`dingdong_init` (`0x439edc`) reads item IDs `0x9d` through `0x9f` from
`/configs/.user_config` and copies them into those globals. The file is an INI
profile using section `[SETTING]`. All recovered JFFS2 snapshots contain
`dingdong_type=1` and `dingdong_status=1`; they omit the response-time key, so
the compiled default of 1 remains in effect. These snapshots describe the
firmware image that was extracted, not necessarily the later app selection on
a particular camera.

The remote configuration handler (`sub_420d80`) receives type, status, and
response time in packet bytes `0xac`, `0xad`, and `0xae`. It persists nonzero
changes with the three item IDs and then calls `sub_431810`, which only replaces
a live global when the corresponding argument is nonzero. A setup reset instead
sets type and status back to 1 and leaves the response time unchanged.

Consequently, selecting a chime in the Wyze application changes only pulse
policy. It does not issue a UART/I2C command, perform a separate arming
transaction, or use a device node before the recovered sysfs GPIO sequence.

References to `ch34x.ko` and `/dev/ttyUSB0` through `/dev/ttyUSB2` belong to
the stock application's generic USB extension-device support, not the
mechanical-chime implementation.

The stock PWM modules are also unrelated. `iCamera` creates and enables PWM
channel 3 during LocalSDK startup, but the stock T31 PWM platform table maps
that channel to GPIO60/PB28. Every `iCamera` consumer of the channel is named
as a night-light operation. The VDB2 profile independently identifies GPIO60
as the 940 nm night-light output, so PWM initialization is not a hidden chime
power prerequisite.

The remaining generic LocalSDK GPIO descriptor table initializes GPIO39 low,
GPIO38 high, and GPIO49/GPIO50 high. Its consumers identify GPIO38/GPIO39 as
status LEDs and GPIO49/GPIO50 as the IR-cut actuator. Thingino's VDB2 profile
has the same assignments. None of these pins is referenced from the normal
dingdong worker.

The existing profile value `gpio.chime: 7` is also unrelated to chime power.
Thingino registers it through `gpio-userkeys` as the doorbell-button input
(key code 2), matching the stock table's input direction for GPIO 7.

### Stock SoC pad setup before iCamera

The stock kernel enables the internal pull-up on GPIO59 (PB27) during early
GPIO initialization. More importantly, the pull state is explicitly
reasserted later by `/system/init/app_init.sh`. After loading the detected
Wi-Fi driver and immediately before starting the application daemons, the
stock script performs these raw T31 register writes:

```sh
devmem 0x10011110 32 0x6e094800
devmem 0x10011138 32 0x300
devmem 0x10011134 32 0x200
```

`0x10011110` is the complete port-B pull-up-enable register. The stock value
enables PB11, PB14, PB16, PB19, PB25, PB26, PB27, PB29, and PB30. Thus it
explicitly enables the GPIO59/PB27 pull-up while leaving GPIO52/PB20 and
GPIO53/PB21 pull-ups disabled. The other two writes select the documented
drive-strength value for PB04 and do not address a chime GPIO.

A settled live Thingino boot instead read `0x60084800`. Compared with stock,
bits PB16, PB25, PB26, and PB27 were clear. This also explains why the earlier
diagnostic kernel was inconclusive: it enabled PB27 during early boot, but the
test captured only the early kernel message and did not verify the pull
register after the Wi-Fi driver ran. Stock deliberately reasserts the complete
value after that driver.

That value is a staging state, not the state present while stock rings. Stock
`iCamera` next exports GPIOs 59, 52, 53, 7, and 51. Each export calls the T31
kernel's `jz_gpio_request()`, which disables both internal pulls on that pin,
and the descriptor initializer then selects the declared direction. For the
four port-B chime pins, the pull-clear mask is `0x08380000`; the resulting
stock port-B pull-up value is `0x66014800`.

GPIO51/PB19 is especially important. Function 0 on PB19 belongs to UART0, and a
live Thingino boot left it in function 0 with an internal pull-up. Merely using
`gpio read 51` temporarily exported the pin but did not select input mode, so
an idle UART level could be mistaken for a valid energy-ready signal. Package
version 1.5 now reproduces the full chronology: write the stock staging value,
initialize GPIOs 59/52/53 output-low, keep GPIO51 exported as an input, clear
both pulls on all four pins, and verify the final `0x66014800` pull-up state.
`S14vdb2-chime` runs after Thingino's `S09mmc` Wi-Fi setup.

## Commands

The VDB2 profile installs `/usr/sbin/vdb2-chime`:

```sh
# Inspect the configured pins without touching hardware.
vdb2-chime --dry-run ring

# Report current input and output levels.
vdb2-chime status

# Immediately claim all three outputs and initialize them low.
vdb2-chime init

# Use the stock short-chime pulse (200 ms by default).
vdb2-chime ring

# Request another duration, capped by max_pulse_ms.
vdb2-chime ring 500

# Force the recovered shutdown sequence.
vdb2-chime off
```

By default, `ring` refuses to energize the outputs when GPIO 51 remains low
after the same 100 ms retry used by the stock firmware. `--ignore-sense` is
available for controlled bench diagnosis only. A process lock prevents two
ring operations from overlapping, and signal handling forces the stock
shutdown sequence if a ring is interrupted. The configured `arm_ms` defaults
to 1500 ms, matching the stock handler's 500 ms post-sense delay plus its 1 s
enabled-chime delay before the GPIO power-on ramp.

The utility accepts only literal 0/1 GPIO reads and reads every output back
after writing it. This is intentional because Thingino's generic `gpio` shell
wrapper exits successfully even when an inner sysfs operation fails; trusting
its exit status alone would defeat the chime utility's shutdown checks.

The `sense_gpio` configuration name is retained for compatibility, but reverse
engineering shows that GPIO 51 is an energy-storage or battery-ready gate. It
does not confirm that the remote mechanical chime moved; it only tells the
stock handler whether it may attempt the power-switch sequence.

The profile stores all pins and timing limits in `/etc/thingino.json` under
`mechanical_chime`. `max_pulse_ms` is a safety limit; `vdb2-chime` also applies
an absolute five-second ceiling to that setting.

## Bench validation

Before connecting a household chime or transformer:

1. Run `vdb2-chime --dry-run ring` and confirm the intended sequence.
2. Verify GPIOs 59, 52, 53, and 51 at the board with no mains or transformer
   voltage connected.
3. Identify what GPIOs 59 and 52 enable and measure GPIO 53's pulse.
4. Check GPIO 51 both with and without a valid chime circuit attached.
5. Start with the default 200 ms pulse and monitor voltage, current, and
   temperature on an isolated, current-limited test circuit.
6. Only after those checks, wire the doorbell event hook to
   `vdb2-chime ring`.

Automatic button-event integration is deliberately deferred until this bench
validation is complete.

Package version 1.2 changed the idle initializer to follow the stock descriptor
order exactly: GPIO59 low, GPIO52 low, then GPIO53 low. After that change also
failed on the bench, a timing audit found that the utility still invoked
Thingino's generic `gpio` shell wrapper for every edge. That wrapper rewrites
the direction before the value and adds a process launch to each read and
write. Version 1.3 uses direct sysfs value reads and writes once S14 has
initialized the pins, retaining the wrapper only as an unexported-pin fallback.
This more closely matches stock `iCamera` and preserves the recovered 30 ms
ramp intervals without removing output readback or the emergency shutdown.

Version 1.4 adds the later stock `app_init.sh` port-B pull-up write and readback.
This is distinct from merely adding the kernel's early PB27 pull-table entry:
the stock userspace write occurs after Wi-Fi initialization and restores the
complete port-B value immediately before `iCamera` starts.

Version 1.5 corrects the second half of that startup sequence. It explicitly
selects GPIO input mode for GPIO51/PB19 and reproduces the pull clears performed
by stock's GPIO exports instead of leaving the pre-iCamera staging value active
during a ring.

`speaker_ctl.ko` is another independent path. Its command 3 drives GPIO58/PB26
low for 1.2 ms and then emits four 5 microsecond edges ending high. GPIO58 is
the camera speaker-amplifier enable, which Thingino's audio driver also owns.
Reproducing that waveform immediately before the recovered 200 ms chime pulse
caused only a local camera power/audio sound during the mandatory reboot; it
did not move the mechanical chime.

## Observed Thingino bench results

Tests on the VDB2 at `192.168.50.96` established the following:

- A normal Thingino boot left GPIOs 51, 52, 53, and 59 unexported. Bank-B GPIO
  registers showed 52 and 53 still in function 0 and GPIO59 as an input.
- Initializing GPIO53, GPIO52, and GPIO59 output-low changed them to genuine GPIO
  outputs. A reboot with `S14vdb2-chime` installed reproduced that state by 26
  seconds uptime.
- Sampling `/sys/class/gpio/gpio*/value` during a one-second ring observed the
  exact recovered rise and fall order at the physical-input register: 59, 52,
  53 high; then 53, 52, 59 low with the configured delays.
- Neither that one-second pulse nor a later 200 ms pulse after boot-time low
  initialization moved the mechanical chime. GPIO51 was high, the utility
  returned success, the outputs returned low, and neither `dmesg` nor `logread`
  gained an error.
- The boot-time run used an earlier initializer that set all three outputs low
  in shutdown order (53, 52, 59). Package version 1.2 corrected this to the
  stock order (59, 52, 53). A cold boot with v1.2 followed by a 200 ms pulse
  still produced no audible chime. A second 200 ms pulse after 4.5 minutes of
  uninterrupted power also remained silent; GPIO51 stayed high throughout.
- The v1.2 pulse took 3.23 seconds end to end, versus approximately 2.79 seconds
  of explicit delays in the recovered stock path. The remaining overhead came
  from invoking the generic `gpio` wrapper and performing a separate process
  for every write and readback. Version 1.3 removed that timing difference for
  initialized pins. Its cold-boot 200 ms test completed in 2.99 seconds, with
  GPIO51 high and all three outputs returning low, but it also produced no
  audible chime. `dmesg`, `logread`, and `logcat` were unchanged by the pulse.
- A diagnostic kernel restored the stock Swan PB27 early-boot pull-up and
  logged that configuration. Two 200 ms pulses and one stock type-3 1000 ms
  pulse still produced no audible chime. The original Thingino kernel was then
  restored and its flashed partition verified. Later inspection showed that
  these tests had not verified PB27 after Wi-Fi initialization, so they did not
  reproduce the separate late stock `app_init.sh` register write.
- On the restored kernel, the settled Thingino PB pull-up register was
  `0x60084800`. Version 1.4 changed and verified it as the exact stock
  `0x6e094800` while every output remained low and the camera stayed reachable.
  A following 200 ms pulse returned success, preserved the stock register, and
  returned GPIOs 59, 52, and 53 low. `dmesg` and `logcat` were byte-identical;
  `logread` gained only the expected SSH connection records. The mandatory
  reboot completed on the original kernel with all three outputs verified low.
  The user reported no audible chime. Subsequent kernel disassembly showed why
  this did not yet match stock runtime: `iCamera` clears the four GPIO pulls
  after the `0x6e094800` write and explicitly changes GPIO51 from UART0 function
  0 to GPIO input.
- A v1.5 initialization-only smoke test then validated that correction without
  sending a ring pulse. Before initialization, GPIO51 was unexported and the
  boot-time bank-B state left PB19 in UART0 function 0. The v1.5 `init` command
  completed successfully, left GPIOs 59, 52, and 53 output-low, retained GPIO51
  as an input reading high, and changed the bank-B mux registers exactly as
  expected for PB19 GPIO input: `MSK` changed from `0xfe7680c0` to
  `0xfe7e80c0`, and `PAT1` from `0xe0000000` to `0xe0080000`. The pull-up
  register reached the recovered stock runtime value `0x66014800`; none of the
  four chime pins had a pull-down enabled. The required post-smoke reboot
  completed at 16 seconds uptime and again verified all three outputs low.
- The same transformer, controller, and chime wiring actuate under stock
  firmware, so wiring alone does not explain the difference.
- A later v1.5 stock-runtime 200 ms pulse again matched the recovered mux,
  pull, sense, and output states but remained silent. Two raw GPIO58
  `speaker_ctl` waveform trials followed by the same 200 ms chime pulse were
  also silent at the chime. The user heard only a sound local to the camera
  during reboot, confirming GPIO58 as the speaker-amplifier path rather than a
  missing chime rail.
- The post-reboot GPIO-B electrical registers retained the default 4 mA drive
  on GPIO51/52/53/59, zero slew-rate bits for those pins, zero Schmitt bits for
  those pins, and a zero I/O-domain-control register. Static analysis of the
  stock kernel found no chime-pin drive-strength override, and the profile uses
  the exact stock SPL, reducing the remaining untested software surface to
  U-Boot/kernel state outside the normal `iCamera` call graph.

The earlier boot-initialized capture is stored under
`logs/20260816-173818-boot-init-200ms`. The v1.2 exact-order and warmed captures
are under `logs/20260816-191547-v1.2-exact-init-200ms` and
`logs/20260816-192050-v1.2-warm-200ms`. The v1.3 direct-sysfs capture is under
`logs/20260816-192944-v1.3-direct-sysfs-200ms`. The diagnostic-kernel captures
are under `logs/20260816-193355-v1.3-pb27-pullup-200ms`,
`logs/20260816-193537-v1.3-pb27-repeat-200ms`, and
`logs/20260816-193803-v1.3-pb27-type3-1000ms`. The v1.4 late-stock-pad test is
under `logs/20260816-235500-v1.4-stock-pad-200ms`. The v1.5 initialization-only
validation is under `logs/20260817-v1.5-gpio51-input-init`.
The later exact v1.5 pulse is under
`logs/20260816-v1.5-stock-runtime-200ms`. The two GPIO58 exclusions are under
`logs/20260816-v1.6b-stock-pa58-raw-200ms` and
`logs/20260816-v1.6c-stock-pa58-repeat-200ms`.

For the final firmware-versus-board split, the diagnostic
`vdb2-stock-chime-direct` bypasses sysfs and shell timing. It configures the
four stock GPIO-B pins through `/dev/mem`, verifies mux/pull state, records the
domain, drive, slew, and Schmitt registers, and performs the exact stock pulse
and shutdown ordering. It is not installed in production and its `ring`
command requires `VDB2_CHIME_LIVE=I_UNDERSTAND`. A failure on the current board
followed by success on an otherwise fresh VDB2 would identify a downstream
board fault; failure on both boards would justify returning to boot-state
comparison rather than changing the recovered `iCamera` sequence.

## Staged device smoke tests

For development images, `tests/device-smoke` can be staged alongside the
utility and profile configuration in `/opt`. Its normal tests never access
GPIOs:

```sh
/opt/vdb2-chime-smoke preflight
/opt/vdb2-chime-smoke dry-run
/opt/vdb2-chime-smoke capture
```

The later live test is deliberately locked behind an explicit environment
value:

```sh
VDB2_CHIME_LIVE=I_UNDERSTAND /opt/vdb2-chime-smoke live 200
```

Do not use `live` or `off` until the isolated test circuit is connected and
the four GPIO roles have been verified at the board.
