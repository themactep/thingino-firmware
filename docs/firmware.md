Firmware
========

Dumping the original firmware
-----------------------------

IP camera firmware resides in a flash chip on the camera board. It can be dumped
in several ways, depending on the camera model and the access level to the
camera's hardware and software.

### Reading firmware with a programmer, off-board

Prerequisites:
- Soldering iron and soldering skills
- CH341A programmer
- 208-mil SOIC8 test adapter
- snander utility

Unsolder the flash chip from the camera board and place it in a socket adapter
connected to the CH341A programmer. Insert the programmer into a USB port on
your computer. Run the `snander` utility to dump the firmware. Repeat the
process twice and compare file hashes to ensure the dump is correct.

```bash
snander -r firmware1.bin
snander -r firmware2.bin
md5sum firmware1.bin firmware2.bin
```

### Reading firmware with a programmer, in-circuit

Prerequisites:
- CH341A programmer
- SOIC8 test clip or pogo-pin jig
- snander utility

Connect the CH341A programmer to the flash chip on the camera board with a
programming clip or a pogo-pin jig.

```bash
snander -r firmware1.bin
snander -r firmware2.bin
md5sum firmware1.bin firmware2.bin
```

### Dumping the firmware via SD card from Linux

Prerequisites:
- Access to the system shell
- SD card slot on the camera

In some cases, when you have access to the operating system, the firmware can be
dumped via an SD card. Copy each firmware partition to the SD card.

```bash
cp /dev/mtd0 /mnt/mmcblk0p1/mtd0.bin
cp /dev/mtd1 /mnt/mmcblk0p1/mtd1.bin
cp /dev/mtd2 /mnt/mmcblk0p1/mtd2.bin
cp /dev/mtd3 /mnt/mmcblk0p1/mtd3.bin
...
cp /dev/mtdN /mnt/mmcblk0p1/mtdN.bin
```
then combine these files on your computer

```bash
cat mtd0.bin mtd1.bin mtd2.bin mtd3.bin ... mtdN.bin > firmware.bin
```

### Dumping the firmware via SD card from U-Boot

Prerequisites:
- UART connection
- Access to the U-Boot shell
- SD card slot on the camera

If you have access to the U-Boot shell, you can dump the firmware directly to an
SD card. In the U-Boot shell, run the following commands to dump a 16MB flash:

```bash
watchdog 0;
setenv baseaddr 0x82000000;
mmc dev 0;
mmc erase 0x10 0x8000;
setenv flashsize 0x1000000;
mw.b ${baseaddr} ff ${flashsize};
sf probe 0; sf read ${baseaddr} 0x0 ${flashsize};
mmc write ${baseaddr} 0x10 0x8000
```

Then, insert the SD card into your computer and copy the firmware dump to a file
on your computer.

```bash
sudo dd bs=512 skip=16 count=32768 if=/dev/sdb of=./fulldump.bin
```
(Replace `/dev/sdb` with the correct device name of your SD card.)

Note: Adjust the flash size value in the U-Boot command for cameras with flash
sizes different from 16MB. Also, update the size parameters in the `mmc write`
and `dd` commands accordingly.

### Dumping the firmware via TFTP

Prerequisites:
- UART connection
- Access to the U-Boot shell
- Ethernet connection
- TFTP server
- Support for TFTP in the U-Boot shell

If you have access to the U-Boot shell, the camera has an Ethernet connection,
and the U-Boot shell has TFTP support, you can dump the firmware via TFTP.
In the U-Boot shell, run the following commands to dump a 16MB flash:

```bash
watchdog 0;
setenv ipaddr 192.168.1.10;
setenv netmask 255.255.255.0;
setenv gatewayip 192.168.1.1;
setenv serverip 192.168.1.254;
setenv baseaddr 0x82000000;
setenv flashsize 0x1000000;
mw.b ${baseaddr} 0xff ${flashsize};
sf probe 0; sf read ${baseaddr} 0x0 ${flashsize};
tftpput ${baseaddr} ${flashsize} firmware.bin
```

Note: Use IP addresses that are appropriate for your network configuration.
Adjust the flash size value in the U-Boot command for cameras with flash
sizes different from 16MB.

### Dumping the firmware via UART log from U-Boot

Prerequisites:
- UART connection
- Access to the U-Boot shell

If you have access to the U-Boot shell, you can dump the firmware via the UART
log. So you need to connect the camera to your computer via UART and log the
output to a file. Use a terminal emulator like `screen` with parameters to log
the output to a file.

```bash
screen -L -Logfile session.log /dev/ttyUSB0 115200
```

In the U-Boot shell, run the following commands to dump a 16MB flash:

```bash
watchdog 0;
setenv baseaddr 0x82000000;
setenv flashsize 0x1000000
mw.b ${baseaddr} 0xff ${flashsize};
sf probe 0; sf read ${baseaddr} 0x0 ${flashsize};
md.b ${baseaddr} ${flashsize}
```
The reading process will take a long time (hours). Disconnect from the terminal
session to avoid accidental keystrokes.

Press `Ctrl-a` then `d` to disconnect the session from the active terminal.

Run `screen -r` when you need to reconnect it later, after the size of the log
file has stopped growing. Reading of a 16MB flash memory should result in about
80MB log file.

When the reading process is complete, convert the hex dump into a binary
firmware file with the following commands:

```bash
cat session.log | sed -E "s/^[0-9a-f]{8}\b: //i" | \
	sed -E "s/ {4}.{16}\r?$//" > firmware.hex
xxd -revert -plain firmware.hex firmware.bin
```
