# Wyze Lamp Socket

The Wyze Lamp Socket (v1, model WLPS) is an E26 lamp holder with a USB-A
power output. It powers a Wyze Cam v3 through its own USB cable, and that
cable also carries a USB data link. On the camera the socket enumerates as a
CH34x USB serial device (`/dev/ttyUSBx`, `ch341` module). The camera is the
brain: the stock firmware decides when the lamp is on (motion, dark, schedule)
and sends commands over that serial link. Several sockets can pair with each
other over the socket's own radio; the camera addresses the whole group.

The socket enumerates as `1a86:7523` ("UART TO USB-V3", bcdDevice 3.63) and
talks at 9600 8N1. Right after power-up it may connect and drop once or twice
before staying attached. With a cable that carries power but not data (or a
plug that is not fully seated), the camera boots normally but the USB port
never sees a device: both data lines read low and `/dev/ttyUSB*` never
appears.

## Enabling

`BR2_PACKAGE_WYZE_ACCESSORY_LAMP_SOCKET=y` (on by default in the
`wyze_cam3_*` defconfigs) installs:

| File | Purpose |
|------|---------|
| `/usr/sbin/lamp_socket_ctl` | CLI: `on`, `off`, `toggle`, `status`, `query`, `send` |
| `/etc/init.d/S15lamp-socket` | Applies `lamp_socket.boot_state` once the device appears |
| `/var/www/config-lamp-socket.html` | Settings > Lamp Socket page |
| `/var/www/a/lamp-socket-button.js` | Lamp toggle in the control bar |
| `/var/www/x/json-lamp-socket.cgi` | JSON API behind both |

The feature is off until **Enable Lamp Socket** is switched on under
Settings > Lamp Socket (`lamp_socket.enabled`). While it is off, the Lamp
button is hidden, the web UI refuses on/off, nothing is sent at boot, and the
Home Assistant switch is not published. `lamp_socket_ctl` itself always works,
for testing from the shell.

With `thingino-ha` enabled the lamp also shows up in Home Assistant as a
`switch` (`cameras/<id>/lamp_socket/set`, entity toggle `ha.enable_lamp_socket`).

### Config (`/etc/thingino.json`)

```json
"lamp_socket": {
  "enabled": false,
  "boot_state": "last",
  "device": "",
  "last_state": ""
}
```

- `enabled`: turns the web UI, boot restore and Home Assistant switch on.
- `boot_state`: `on`, `off`, `last` (restore the last commanded state) or
  `none` (send nothing at boot).
- `device`: serial device override. Empty auto-detects the first
  `/dev/ttyUSB*`.
- `last_state`: maintained by `lamp_socket_ctl` while `boot_state` is `last`.

`status` asks the socket for its state (`2C FF`) and falls back to the last
state sent from this camera if it does not answer.

## Protocol

Same framing as the Wyze Spotlight and Floodlight v1 accessories. Like their
scripts, `lamp_socket_ctl` leaves the baud rate at the tty default and only
switches the port to raw mode:

```
AA 55 43 <len> <cmd> <payload...> <sum_hi> <sum_lo>
```

- `len` counts `cmd`, the payload and the two checksum bytes.
- The checksum is the 16-bit big-endian sum of every byte before it,
  including `AA 55`.
- Replies from the socket start with `55 AA 43` and use `cmd + 1`, with the
  same length and checksum rules.

Commands and replies verified on hardware (socket firmware 0.9.0):

| Sent | Reply | Meaning |
|------|-------|---------|
| `AA 55 43 05 2E FF 01 02 75` | `55 AA 43 0E 2F 01 "79EDB10A" FF 01 04 5D` | Lamp on (all sockets), acknowledged |
| `AA 55 43 05 2E FF 02 02 76` | `55 AA 43 0E 2F 01 "79EDB10A" FF 02 04 5E` | Lamp off, acknowledged |
| `AA 55 43 04 2C FF 02 71` | `55 AA 43 12 2D 01 "79EDB10A" 01 00 09 00 1D 01 03 87` | State: 1 socket, ID, state `01` on / `02` off |
| `AA 55 43 03 27 01 6C` | `55 AA 43 04 28 04 01 72` | Hardware type 4 (Lamp Socket) |

In the replies, `01` after the command byte is the number of sockets, and
`"79EDB10A"` is that socket's 8-character ASCII ID. In the state reply, the
byte after the ID is the lamp state; the remaining bytes (`00 09 00 1D 01`)
look like firmware version and link status but are not decoded.

### Where the codes come from

The stock Wyze Cam v3 `iCamera` (4.36.9.139) keeps one table of accessory
commands at file offset `0x1789dc`. Each 28-byte entry is:

```
u32 id; u8 send[6]; u8 recv[6]; char *name; void *build; void *parse;
```

`send[]`/`recv[]` hold one command byte per accessory type. The dispatcher
picks the column from the detected accessory type, and the build function
writes that byte into the frame. Column 1 is the Spotlight (brightness `0x16`,
matching `spotlight_ctl`), column 2 the Floodlight v1 (`0x46`, matching
`floodlight_ctl`) and column 3 the Lamp Socket, the only column with the
"Lampholders" commands.

Lamp Socket column (send / reply):

| Command | Send | Reply |
|---------|------|-------|
| ask hardware type | `27` | `28` |
| get mac address | `04` | `05` |
| get software ver | `0C` | `0D` |
| get hardware ver | `10` | `11` |
| send random | `02` | `03` |
| send upgrade | `0E` | `0F` |
| get work time | `18` | `19` |
| get Lampholders list | `2A` | `2B` |
| get Lampholders state | `2C` | `2D` |
| set Lampholders state | `2E` | `2F` |
| set upgrade message / content / end | `30` / `32` / `34` | `31` / `33` / `35` |
| set upgrade main / subsidiary | `36` / `38` | `37` / `39` |
| set Lampholders add | `3A` | `3B` |
| set Lampholders delete | `3C` | `3D` |
| get Lampholders subenr | `48` | `49` |
| set Lampholders restart | `4A` | `4B` |
| get upgradesub state | `4C` | `4D` |
| set lamp off time | `4E` | `4F` |
| get lamp off time | `50` | `51` |
| set camera info | `58` | `59` |
| get camera info | `60` | `61` |
| camera info report (socket to camera) | | `63` |

`set Lampholders state` is built as `2E FF <state>`, where `FF` addresses
every socket in the group and `<state>` is `1` on or `2` off. The stock
firmware sends `1` on its "LAMPPORT TURN ON" path and `2` on "TURN OFF".
`get Lampholders state` is `2C FF` for all sockets, or `2C <n> <8-byte ID> ...`
for specific ones.

The table puts the hardware-type reply's `04` in column 3 (types are 1-based),
which the socket confirms.

The remaining payload formats have not been decoded. `lamp_socket_ctl send`
and the Diagnostics panel on the settings page frame arbitrary commands for
experimenting.
