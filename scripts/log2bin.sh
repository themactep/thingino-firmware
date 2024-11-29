#!/bin/sh
#
# In the terminal program you use to connect to the UART port,
# enable saving the session log files.
#
#   screen -L -Logfile fulldump.log /dev/ttyUSB0 115200
#
# Set flash memory size. Use this command for an 8MB flash chip
#
#   setenv flashsize 0x800000
#
# or this one for a 16MB flash chip
#
#   setenv flashsize 0x1000000
#
# then dump the memory contents to the console
#
#   setenv baseaddr 0x82000000;
#   mw.b ${baseaddr} 0xff ${flashsize};
#   sf probe 0; sf read ${baseaddr} 0x0 ${flashsize};
#   md.b ${baseaddr} ${flashsize}
#
# Since the reading process will take a considerable amount of time
# (literally hours), you may want to disconnect from the terminal session
# to prevent accidental keystrokes from contaminating the output.
#
# Press Ctrl-a then d to disconnect the session from the active terminal.
# Run screen -r when you need to reconnect it later, after the size of the
# log file has stopped growing.
#
# Reading of an 8 MB flash memory should result in about 40 MB log file,
# and for a 16 MB chip the file should be twice that size.
#
# Convert the hex dump into a binary firmware file running this script.
#
# 2023 Paul Philippov, paul@themactep.com

rawlog=$1
hexlog=${rawlog}.hex
binfile=${rawlog}.bin

cat $rawlog | sed -E "s/^[0-9a-f]{8}\b: //i" | \
	sed -E "s/ {4}.{16}\r?$//" > $hexlog

xxd -revert -plain $hexlog $binfile

exit 0

