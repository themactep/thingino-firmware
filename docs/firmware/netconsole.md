NetConsole
==========

The U-Boot console over UDP: an interactive bootloader prompt on a camera
with no serial port attached.

Covers the U-Boot phase only. Booting the kernel halts the network, so
output stops at the handoff; kernel messages go to the serial port and need
Linux-side netconsole instead. Anything printed before the main loop (TPL,
SPL, DDR init, the U-Boot banner) is also out of reach, because the network
is not up that early.

Quick start
-----------

On a camera already carrying the shipped defaults:

    U=<output-dir>/build/uboot-2026.07
    gcc -o $U/tools/ncb $U/tools/ncb.c            # once
    $U/tools/netconsole 192.168.1.10 6666         # the board's ipaddr

Reboot the camera and keep pressing Enter until the `=>` prompt appears --
autoboot aborts on any key. Type commands; `boot` resumes, `reset` reboots,
Ctrl-T exits the client.

If the interrupt never lands, check `bootdelay`: a saved environment keeps
whatever value it already has, so a camera that only had its bootloader
reflashed may still carry the old one -- and a 1s window closes before the
link is up. Set it once (persistent):

    ssh root@<camera> fw_setenv bootdelay 5

If keystrokes never arrive, or stop arriving while output still flows,
switch to broadcast -- it needs no ARP or routing (see "Troubleshooting" for
the switch-side failure it sidesteps):

    $U/tools/netconsole 255.255.255.255 6666

With broadcast, characters may display twice -- your own keystroke loops
back to the listener on top of the board's echo -- which is cosmetic.

Enabling it
-----------

Off by default; opt in per camera. Set
`BR2_PACKAGE_THINGINO_UBOOT_NETCONSOLE=y` in the camera defconfig. The symbol
needs a wired network (U-Boot has no Wi-Fi driver) -- either the on-chip MAC
or a USB-Ethernet dongle on an OTG board, see "USB-Ethernet boards" -- and a
U-Boot version configured through Kconfig; the 2013.07 tree uses a patch
instead and is handled on the ciao branch. Cameras that do not opt in build a
stock console and keep the stock one-second bootdelay.

A pre-build hook in `package/thingino-uboot/thingino-uboot.mk` switches on the
Kconfig options:

| Symbol | Purpose |
|---|---|
| `CONFIG_NETCONSOLE` | the console-over-UDP driver |
| `CONFIG_CONSOLE_MUX` | device lists, so serial is kept alongside `nc` instead of replaced |
| `CONFIG_USE_PREBOOT` | runs the environment's `preboot` before the autoboot window, the only point early enough to redirect the console and still interrupt boot |

Costs a few KB in the boot partition and does not change the partition
layout.

Shipped defaults
----------------

Injected into the generated `uenv.txt` (`thingino-uboot.mk`), each line only
when no camera or user uenv file has set that variable already:

    preboot=setenv stdout serial,nc;setenv stderr serial,nc;setenv stdin serial,nc
    bootdelay=5
    ipaddr=192.168.1.10

`uenv.txt` is both the compiled-in default environment
(`CONFIG_ENV_DEFAULT_ENV_TEXT_FILE`) and the source of the flashed env
partition image, so a full-image flash carries these from the first boot.

- `preboot` performs the console redirect. `serial` stays first in each
  list, so an attached serial console is unaffected.
- `bootdelay` must leave usable time after the link comes up: interrupting
  autoboot over the network from a cold power-up does not work inside 1
  second, and 5 is verified sufficient. It rides with netconsole, so boards
  without it (wifi-only) keep the stock 1s.
- `ipaddr` must be non-zero or the network stack refuses to start. Output
  is broadcast so the value does not affect it; only unicast input depends
  on it.

USB-Ethernet boards
-------------------

On a board with no on-chip Ethernet but a USB OTG data port
(`BR2_PACKAGE_THINGINO_KOPT_DWC2_OTG`), netconsole runs over a USB-Ethernet
dongle instead. Nothing extra is compiled: the isvp defconfigs already set
`CONFIG_USB_DWC2`, `CONFIG_USB_HOST_ETHER` and the ASIX host drivers
(`CONFIG_USB_ETHER_ASIX`, `CONFIG_USB_ETHER_ASIX88179`). It is
`THINGINO_UBOOT_DISABLE_USB_ETH` that strips them from boards with no OTG
port -- exactly the boards this mode excludes. The only difference is one
extra command at the head of the injected preboot:

    preboot=usb start;setenv stdout serial,nc;setenv stderr serial,nc;setenv stdin serial,nc

`usb start` enumerates the dongle and registers it as an Ethernet device.

No `ethact` selection is needed on this tree, unlike the 2013.07 one. Two
reasons: `THINGINO_UBOOT_DISABLE_WIRED_ETH` drops the on-chip MAC driver on
the same `!BR2_ETHERNET` condition, so the dongle is the only `UCLASS_ETH`
device; and under `CONFIG_DM_ETH` `eth_init()` only consults `ethact` when
`ethrotate=no`, otherwise taking the current device and rotating on failure.
Note also that the driver-model device names are `asix_eth` and
`ax88179_eth` (the `U_BOOT_DRIVER` names), not the `asx0`/`axg0` of the
legacy stack -- so a hand-written `setenv ethact asx0` would find nothing.

Because `usb start` runs inside preboot, enumeration and link-up finish
before the autoboot countdown begins, so `bootdelay` only has to overlap a
keypress from the client and needs no extra margin for USB.

Cable the dongle to the same segment as the host running `tools/netconsole`;
from there it behaves exactly like a wired board. To confirm which device
carried the traffic, `printenv ethact` at the prompt reports the dongle.

Reaching the board for input
----------------------------

Output is broadcast and always arrives. Input can be sent two ways:

- **Unicast** (send to `ipaddr`, the quick start default): requires your
  host to address that IP on the wire -- same subnet, or a seeded neighbour
  entry (`ip neigh replace <ipaddr> lladdr <ethaddr> dev <iface>`).
- **Broadcast** (send to `255.255.255.255`): needs no ARP entry and works
  regardless of whether `ipaddr` is on your subnet.

Use `ncb`, not netcat, for receiving -- netcat cannot listen to broadcast.
`tools/netconsole` drives both directions and needs `ncb` beside it or in
`PATH`.

Troubleshooting
---------------

- **Nothing arrives.** Using netcat instead of `ncb`? It cannot receive
  broadcast.
- **`Connection refused`.** ICMP port-unreachable: the board is in Linux,
  where nothing listens on UDP 6666. You missed the window.
- **Output stops when the kernel boots.** By design; the network is halted
  at the OS handoff.
- **Commands abort on their own.** A key sender is still running.
- **Different L2 segment.** Broadcast does not cross routers.
- **Unicast input freezes; output keeps flowing.** Seen with a MikroTik
  CRS112 (QCA-8511): the switch's dynamic unicast FDB entry for the quiet
  board evaporates and unicast stops reaching the port, while broadcast
  still arrives -- and any transmit from the board revives it. The
  mechanism is entirely switch-side, so any board idling at the prompt is
  exposed. Remedies, best first:
  1. Send input to 255.255.255.255 (the broadcast alternative in the quick
     start). Immune by construction.
  2. Pin the board's MAC on the switch. On RouterOS:
     `/interface ethernet switch unicast-fdb add mac-address=<ethaddr> port=<port> svl=yes`
  3. Ad hoc: anything broadcast that makes the board transmit. A freshly
     started `arping <ipaddr>` punches through (its first probe is
     broadcast), but goes deaf once it switches to unicast probes.
     `ping -b 255.255.255.255` keeps working, because every probe stays
     broadcast.

Security
--------

NetConsole has no authentication. With `ncip` unset the board runs in
broadcast mode and accepts console input from any host on the L2 segment, so
while autoboot counts down anyone on the subnet can interrupt boot and reach
an interactive U-Boot prompt: full access to flash, the environment, and boot.

That is why the build option is off by default and opt-in per camera. To
narrow it, pin one client with `fw_setenv ncip <host-ip>`; the board then only
accepts input from that host, and sends its output there as unicast rather
than broadcasting. That is address-based, not real authentication.

Removing it
-----------

The redirect cannot persist. `CONFIG_SYS_CONSOLE_IS_IN_ENV` is unset, so
the console is rebuilt from the real devices every boot; no environment
change can lock you out.

    fw_setenv preboot        # back to stock behaviour
    fw_setenv bootdelay 1
