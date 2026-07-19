# Wyze Floodlight v2 — CH554 MCU serial protocol (ttyS2)

Reverse-engineered from the stock `iCamera` binary (Wyze product `HL_CAM3P`,
app 4.53.3.9759). Source module in the binary: `protocol.c` + `flood_light2.c`
+ `productservices/floodlight2/ttyS2/ttyS2.c`. All addresses are from the
extracted `extracted_floodlight/iCamera` (MIPSEL, T41).

The floodlight LEDs, 3-zone PIR array, and siren are managed by an external
**CH554** MCU. The SoC talks to it over **`/dev/ttyS2`**. There are **no SoC
GPIOs** for flood/PIR/siren — everything is this serial protocol.

## Physical layer (verified in `ttys2_open`/sub_457f4c)

| param | value |
|-------|-------|
| device | `/dev/ttyS2` (T41 UART2, pinmux uart2-pc) |
| open flags | `O_RDWR | O_NOCTTY | O_NONBLOCK` (0x882) |
| line | `cfmakeraw`, 8N1, no flow control |
| baud (runtime) | **115200** (`cfset{i,o}speed(0x1002)`) |
| ioctl | `TCSETSF` (0x5410), `tcflush(TCIFLUSH)` first |

Note: the CH554 has a WCH serial bootloader that renegotiates baud during an
MCU firmware update ("variable baud"); that IAP path is NOT in `iCamera`
(likely `libwyzefdk.so`/OTA). 115200 is the normal runtime rate for this FW.
Some hardware revisions may run 9600 — make the daemon's baud configurable.

## Frame format

Two byte-order-distinct preambles by direction.

### SoC → MCU (request) — built by `sub_452a7c` / `sub_452b30`
```
+------+------+------+------+--------+-----------+--------+--------+
| 0xAA | 0x55 | 0x43 | LEN  | OPCODE | DATA[...] | SUM_hi | SUM_lo |
+------+------+------+------+--------+-----------+--------+--------+
  [0]    [1]    [2]    [3]     [4]      [5..]
```
- `0xAA 0x55` preamble, `0x43` class byte ('C').
- `LEN` = number of bytes after LEN = `1 (opcode) + len(DATA) + 2 (checksum)`.
- `SUM` = 16-bit sum of **all bytes from [0] through the last DATA byte**
  (i.e. `AA+55+43+LEN+OPCODE+ΣDATA`), appended **big-endian** `hi,lo`.
  (Verified: `sub_452a7c` computes `opcode + 0x145`, where
  `0x145 = 0xAA+0x55+0x43+0x03`.)

Example — "get pir value" (opcode 0xBC, no data, LEN=3):
`AA 55 43 03 BC` → sum = 0xAA+0x55+0x43+0x03+0xBC = 0x201 → `AA 55 43 03 BC 02 01`

The byte order is confirmed directly in the stock builders: `sub_452a7c`
stores `sum >> 8` before the low byte, and `sub_452b30` does the same for the
three-data-byte brightness command.

### MCU → SoC (response/event) — parsed by `sub_4523f4` (`serial_pkg_check`)
```
+------+------+--------+------+-----------+--------+--------+
| 0x55 | 0xAA | OPCODE | LEN  | DATA[...] | SUM_hi | SUM_lo |
+------+------+--------+------+-----------+--------+--------+
  [0]    [1]     [2]     [3]
```
- Preamble `0x55 0xAA` (opposite order from the request).
- `OPCODE` = the response opcode (request opcode + 1; see table).
- `LEN` at byte [3]; total frame = `LEN + 4`.
- Trailing 2-byte checksum, same big-endian 16-bit additive scheme; the parser rejects on
  mismatch and on `LEN != payloadlen+4`.
- RX bytes are accumulated in a 256-byte reassembly buffer (`data_75fa68`,
  count `data_75fa64`) and resynced on the `55 AA` preamble.

## Command set (dispatch table `data_75fb68`, 5 entries)

Commands are enqueued by id (0x2710+) to a serial message queue; the
`serial_port_init_thread` (sub_452bd0) dequeues, calls the TX builder, and waits
for the matching response opcode.

| id | name | req op | resp op | frame |
|----|------|:------:|:-------:|-------|
| 0x2710 | get brightness | 0x44 | 0x45 | `AA 55 43 03 44 <sum>` |
| 0x2711 | **set brightness** | 0x46 | 0x47 | `AA 55 43 06 46 B0 B1 B2 <sum>` |
| 0x2712 | get software (version) | 0x3C | 0x3D | `AA 55 43 03 3C <sum>` |
| 0x2713 | stop brightness change | 0x52 | 0x53 | `AA 55 43 03 52 <sum>` |
| 0x2714 | get pir value | 0xBC | 0xBD | `AA 55 43 03 BC <sum>` |

All single-opcode commands use `sub_452a7c(opcode)`. Only **set brightness**
(`sub_452b30`) carries 3 data bytes, from `floodlight2_set_device_brightness`
(sub_4531b8):
- `B0` = target brightness  (`data_7d91c0`, arg1 — logged "to[%d]")
- `B1` = arg2 (mode/"from"; not named in logs)
- `B2` = ramp duration in ×100 ms (`data_7d91b8`, arg3 — logged "with[%d00 ms]")

## PIR / motion

- 3 zones: **left / middle / right** (`floodlight2 left/middle/right PIR`,
  JSON `"PIR":[l,m,r]`). Per-zone enable + `PIRSensitivity` are floodlight2
  user-config items (paracfg 0x9d–0xb6), pushed to the MCU.
- Motion arrives as MCU→SoC frames dispatched to callbacks registered via
  `floodlight2_pir_alarm_serial_set_callback` (sub_4536d4, list `data_7d91dc`).
  Handler `sub_454514`: event `*arg1 == 1` ⇒ set motion-active flag
  (`data_7d91c2c`) + timestamp `time()`. `get pir value` (0xBC/0xBD) is the
  polled path for raw zone values.

## Cloud/config bridge (not serial)

`sub_4583c0` parses cloud JSON `floodlightInfo` (switch, brightness,
PIRMotionFilter, PIRSensitivity, PIR[3], motionWarning, ambientlight,
sirenLightFlash) into paracfg items, which the floodlight2 loop then pushes to
the MCU via the commands above.

## Implication for thingino `floodlightd`

A userspace daemon should:
1. Open `/dev/ttyS2` @ 115200 8N1 raw (configurable baud).
2. RX loop: reassemble `55 AA …` frames, verify checksum, decode 0xBD (PIR) and
   0x47/0x45 acks; surface motion (per-zone) to thingino (mot256/MQTT/scripts).
3. TX: `set brightness` (0x46) to drive the flood LEDs, `stop brightness change`
   (0x52), `get pir value` (0xBC) to poll, `get software` (0x3C) for MCU version.
4. Map to thingino night mode using the verified SoC GPIOs: IR-cut 49/50,
   IR LED 81, status LEDs 38/39, amp 63, button 62.

DTS: UART2 is enabled in `board/ingenic/dts/wyze_floodlightv2_t41nq.dts` so
`/dev/ttyS2` exists.

_TODO / to confirm on live hardware: exact set-brightness `B1` semantics; the
async motion-event opcode & payload layout (scope `ttyS2` or capture at 0xBD);
whether any revision uses 9600 baud._
