#!/bin/ruby
#
# Convert Thingino firmware binary image
# into a magic file supported by WUUK cameras.
#
# 1. Run this script on a fresh Thingino firmware file
#    for WUUK camera to convert it to a supported image.
# 2. Place the image on an SD card, put the card in your 
#    WUUK camera still with the stock firmware,
#    and reboot it.
# 3. Wait for an IR cut filter click (about 3 minutes),
#    then go searching for THINGINO-xxxx wireless network,
#    connect to it, and set up wireless access.
#
# 2024, Paul Philippov, paul@themactep.com
#

if ARGV.empty?
	puts "Usage: $0 <firmware file> [<output file>]"
	exit 1
end

fw_file = ARGV[0]
wrapped_file = ARGV[1] || "T31_0510.bin"

puts "Converting #{fw_file} into #{wrapped_file}"

IO.binwrite wrapped_file, "1.0.47\u000a"
IO.binwrite wrapped_file, "849a9016e83d29e2bf1d597c99786f86", 0x20
IO.binwrite wrapped_file, File.read(fw_file), 0x400

puts "Done"
exit 0
