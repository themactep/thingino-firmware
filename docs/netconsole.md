NetConsole
==========

The U-Boot console over UDP: an interactive bootloader prompt on a camera with
no serial port attached.

Covers the U-Boot phase only. `bootm` calls `eth_halt()` before starting the
kernel, so output stops at the handoff; kernel messages go to the serial port
and need Linux-side netconsole instead. Anything printed before `main_loop`
(SPL, DDR init, the U-Boot banner) is also out of reach, because the network is
not up that early.

Quick start
-----------

On a camera already carrying the shipped defaults:

    U=output/<branch>/<camera>-<kernel>-<libc>/build/uboot-2013.07
    gcc -o $U/tools/ncb $U/tools/ncb.c            # once
    $U/tools/netconsole 192.168.1.10 6666         # the board's ipaddr

Reboot the camera and hold Ctrl-C until `isvp_t31#` appears. Type commands;
`boot` resumes, `reset` reboots, Ctrl-T exits the client.

If Ctrl-C never lands, check `bootdelay`: a saved environment keeps whatever
value it already has, so an existing install that only had its bootloader
reflashed still carries the old one -- and the stock 1s window closes before
the link is up. Set it once (persistent):

    ssh root@<camera> fw_setenv bootdelay 5

If keystrokes never arrive, or stop arriving while output still flows, switch
to broadcast -- it needs no ARP or routing (see "Troubleshooting" for the
switch-side failure it sidesteps):

    $U/tools/netconsole 255.255.255.255 6666

With broadcast, characters may display twice -- your own keystroke loops back
to the listener on top of the board's echo -- which is cosmetic.

Enabling it
-----------

Off by default; opt in per camera. Set
`BR2_PACKAGE_THINGINO_UBOOT_NETCONSOLE=y` in the camera defconfig (it depends
on wired Ethernet and the 2013.07 U-Boot). That passes `CONFIG_NETCONSOLE=y`
into the U-Boot build and injects the environment below; every camera that
does not opt in builds a byte-identical stock bootloader with the stock 1s
bootdelay.
`package/all-patches/uboot/2013.07/0006-isvp-enable-NetConsole-behind-a-build-system-guard.patch`
carries the U-Boot side, guarded by that flag; the driver and its hooks were
already in the tree.

| Symbol | Purpose |
|---|---|
| `CONFIG_NETCONSOLE` | the driver; from the build system, never defined in the header |
| `CONFIG_CONSOLE_MUX` | device lists, so serial is kept alongside `nc` instead of replaced |
| `CONFIG_PREBOOT` | empty default; allows redirecting the console before the autoboot abort window |

Costs a few KB in the boot partition and does not change the partition layout.

Shipped defaults
----------------

Injected into the generated `uenv.txt` when netconsole is enabled
(`thingino-uboot.mk`), each line only when no camera or user uenv file has
set that variable already:

    preboot=setenv stdout serial,nc;setenv stderr serial,nc;setenv stdin serial,nc
    bootdelay=5

Without these in the flashed environment netconsole is compiled in but
unreachable. The compiled-in `CONFIG_*` values are no substitute: U-Boot uses
`default_environment` only when the saved environment is blank or CRC-invalid.

`ipaddr` is not injected: `isvp_common.h` already defines
`CONFIG_IPADDR 192.168.1.10`, which `env_default.h` emits into the default
environment.

- `preboot` runs before the autoboot abort window, the only point early enough to
  redirect the console and still interrupt boot. From `bootcmd` it is too late.
  `serial` stays first in each list, so an attached serial console is unaffected.
- `bootdelay` must leave usable time after the link comes up: interrupting
  autoboot over the network from a cold power-up does not work inside the
  stock 1 second, and 5 is verified sufficient. It rides with netconsole, so
  boards without it (wifi-only) keep the stock 1s and boot as fast as before.
- `ipaddr` must be non-zero or `NetLoop` refuses the protocol; `CONFIG_IPADDR`
  supplies it. Output is broadcast so the value does not affect it; only
  unicast input depends on it.

Security
--------

Netconsole has no authentication. With `ncip` unset the board runs in
broadcast mode and accepts console **input from any host on the L2
segment** -- `nc_input_packet()` rejects a packet only when it is neither
from `nc_ip` nor broadcast, and in broadcast mode that test never fires. So
while autoboot is counting down, anyone on the subnet can send Ctrl-C and
drop the board to an interactive U-Boot prompt: full access to flash, the
environment, and boot.

This is inherent to how netconsole reaches a board with no fixed client. It
is why the build option is off by default and opt-in per camera -- enable it
only on trusted networks. To narrow it, pin one client:

    fw_setenv ncip <host-ip>

With `ncip` set, the board only accepts input from that host (and sends its
output there as unicast rather than broadcasting). That is address-based,
not real authentication, but it keeps a casual host on the segment from
reaching the prompt.

Using it
--------

Use `ncb`, not netcat -- netcat cannot listen to broadcast. `tools/netconsole`
drives both directions and needs `ncb` beside it or in `PATH`.

The abort key is Ctrl-C alone (`\x3`, `CONFIG_AUTOBOOT_STOP_STR`), not any
key; the client passes it through to the board.

Expect to abort blind on a cold boot: the `KEY: ###### Press Ctrl-C ...`
prompt is printed once, before the link is up, and may not reach the network.
Start sending Ctrl-C as soon as you trigger the reboot; any one landing inside
the window wins.

Reaching the board for input
----------------------------

Output is broadcast and always arrives. Input can be sent two ways:

- **Unicast** (send to `ipaddr`, the quick start default): requires your host
  to address that IP on the wire -- same subnet, or a seeded neighbour entry
  (below).
- **Broadcast** (send to `255.255.255.255`): needs no ARP entry and works
  regardless of whether `ipaddr` is on your subnet.

If `ipaddr` is not on your subnet, pick one:

- Add an address on that subnet to your host:
  `sudo ip addr add 192.168.1.222/24 dev <iface>`. Put it on the bridge, not on
  an enslaved bridge port, where it is inert.
- Point `ipaddr` at your own subnet with `fw_setenv`.
- Or fall back to broadcast, which the board accepts regardless of `ipaddr`:

        python3 -c "
        import socket,time
        s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1)
        while True:
            s.sendto(b'\x03',('255.255.255.255',6666)); time.sleep(0.1)
        "

  Run `ncb 6666` separately for output. Useful when the board is looping.

U-Boot answers ARP only inside a `NetLoop`, so unicast input can fail until your
neighbour table is populated. An SSH session usually does that; otherwise seed it
with the MAC from `fw_printenv ethaddr`:

    sudo ip neigh replace <ipaddr> lladdr <ethaddr> dev <iface>
    sudo ip neigh del <ipaddr> dev <iface>          # when done

Delete it if the camera's Linux answers on the same address with a different MAC,
or the stale entry will break SSH. Compare `cat /sys/class/net/eth0/address` with
`fw_printenv ethaddr`.

Check the link first
--------------------

The boot log reports the negotiated link and the advertisement words it was
resolved from:

    ETH:   link 100M/full  (adv 0x01e1, partner 0xd141, common 0x0141)

`adv` is what the board offered, `partner` what the far end offered, `common`
the intersection the speed was taken from. A link coming up slower than
expected names its reason here: a partner word with only 10M bits set is a
restricted switch port, not a board fault. If the board answers nothing
despite a sane link line, check the peer with `ethtool` -- and do not force
`autoneg off` there; a half-applied `ethtool -s` leaves an interface
advertising nothing and linkless.

Troubleshooting
---------------

- **Nothing arrives.** Using netcat instead of `ncb`? It cannot receive broadcast.
- **`*** ERROR: 'ipaddr' not set`.** `NetLoop` refuses the protocol with a zero IP.
- **`Ncat: Connection refused`.** ICMP port-unreachable: the board is in Linux,
  where nothing listens on UDP 6666. You missed the window.
- **Output stops at `bootm`.** By design, `eth_halt()` in `common/cmd_bootm.c`.
- **No `KEY:` prompt but `bootcmd` output arrives.** Expected on a cold boot.
- **Commands abort on their own.** A Ctrl-C sender is still running.
- **Different L2 segment.** Broadcast does not cross routers.
- **`error may happen, need reload`, once.** A transmit timed out; the driver
  reset the transmit path and retried, so nothing was lost. Repeated lines mean
  the link is not passing traffic at all -- read the `ETH: link` line.
- **Unicast input freezes; output keeps flowing.** Seen with a MikroTik
  CRS112 (QCA-8511): the switch's dynamic unicast FDB entry for the quiet
  board evaporates and unicast stops reaching the port, while broadcast still
  arrives -- so a client sending to the board's IP goes deaf seconds after the
  prompt idles, and any transmit from the board (a serial keypress echo, an
  answered broadcast ARP) revives it. The board itself is fine: its filter,
  ring and PHY were verified healthy mid-freeze, and it answers every frame
  actually delivered. Remedies, best first:
  1. Send input to 255.255.255.255 (the broadcast alternative in the quick
     start). Immune by construction.
  2. Pin the board's MAC on the switch. On RouterOS:
     `/interface ethernet switch unicast-fdb add mac-address=<ethaddr> port=<port> svl=yes`
     (fails with "already have such entry" while the dynamic entry exists;
     retry when frozen, or briefly unplug the board).
  3. Ad hoc: anything broadcast that makes the board transmit. A freshly
     started `arping <ipaddr>` punches through (its first probe is broadcast)
     and the board's reply revives unicast -- but a long-running arping goes
     deaf with the freeze, since it switches to unicast probes after the first
     reply. `ping -b 255.255.255.255` works the same way and keeps working,
     because every probe stays broadcast.

Removing it
-----------

The redirect cannot persist. `CONFIG_SYS_CONSOLE_IS_IN_ENV` is unset, so
`console_init_r` rewrites `stdin`/`stdout`/`stderr` from the real devices every
boot; no environment change can lock you out.

    fw_setenv preboot        # back to stock behaviour
    fw_setenv bootdelay 1

Flashing notes
--------------

`make ota-uboot` erases and rewrites the **environment** partition as well as the
boot partition. Back it up first: `fw_printenv > env-backup.txt`.

To flash the bootloader alone and keep the environment, drive the flasher
directly -- its environment argument is optional:

    scp -O $IMG/u-boot-lzo-with-spl.bin root@<camera>:/tmp/boot.bin
    scp -O package/thingino-sysupgrade/files/flash-ota root@<camera>:/tmp/flash-ota.sh
    ssh root@<camera> 'chmod +x /tmp/flash-ota.sh && /tmp/flash-ota.sh boot /tmp/boot.bin'

No padding needed -- `flashcp -A` erases the whole partition. Do not append
`&& reboot`; `flash-ota` reboots itself.

Never write this build's environment onto a camera carrying a different build's
kernel, rootfs and data. The environment holds `mtdparts`, `data_addr` and
`data_size`: the partition map for the images built with it. Against a foreign
rootfs the kernel cannot mount root and the camera reboot-loops silently.
Recover by aborting into netconsole or serial and restoring those three
variables.

See also
--------

- [Bootloader](bootloader.md), [Camera recovery](camera-recovery.md)
- `doc/README.NetConsole` in the U-Boot source tree
