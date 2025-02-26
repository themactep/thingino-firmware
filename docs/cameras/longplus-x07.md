LongPlus X07
============

https://longplus.com/products/longplus-b1-wi-fi-security-camera-for-home-security-2-pack-

### Hardware

- SoC: Ingenic T31N (64 MB)
- Image Sensor:
	- GC2063 (2MP)
	- JXF23 (2MP)
	- MIS2008 (2MP)
- Wi-Fi Module: RTL8189FTV (SDIO)
- Flash Chip: NOR 16MB
- Power: 5V DC microUSB

### Installation

1. Undo two screws on the back of the ball, rotate the ball face up, remove the to part of the ball.
2. Undo two screws holding the PCB to get access to the flash chip on the front side of the PCB.
3. Clip the flash chip and use a CH341A programmer to install the firmware.

### UART

UART contacts are available as 1.27mm pitch holes near the vertical motor
terminals, marked `R`, `T`, and `G`.

### Motors

Motor terminals are 1.5mm pitch JST-ZH 5-pin connectors.

### U-Boot
```
U-Boot SPL 2013.07 (Oct 26 2020 - 14:49:24)
Timer init
CLK stop
PLL init
pll_init:366
pll_cfg.pdiv = 10, pll_cfg.h2div = 5, pll_cfg.h0div = 5, pll_cfg.cdiv = 1, pll_cfg.l2div = 2
nf=118 nr = 1 od0 = 1 od1 = 2
cppcr is 07605100
CPM_CPAPCR 0750510d
nf=84 nr = 1 od0 = 1 od1 = 2
cppcr is 05405100
CPM_CPMPCR 07d0590d
nf=100 nr = 1 od0 = 1 od1 = 2
cppcr is 06405100
CPM_CPVPCR 0640510d
cppcr 0x9a773310
apll_freq 1404000000
mpll_freq 1000000000
vpll_freq = 1200000000
ddr sel mpll, cpu sel apll
ddrfreq 500000000
cclk  1404000000
l2clk 702000000
h0clk 200000000
h2clk 200000000
pclk  100000000
CLK init
SDRAM init
sdram init start
ddr_inno_phy_init ..!
phy reg = 0x00000007, CL = 0x00000007
ddr_inno_phy_init ..! 11:  00000004
ddr_inno_phy_init ..! 22:  00000006
ddr_inno_phy_init ..! 33:  00000006
REG_DDR_LMR: 00000210
REG_DDR_LMR: 00000310
REG_DDR_LMR: 00000110
REG_DDR_LMR, MR0: 00f73011
T31_0x5: 00000007
T31_0x15: 0000000c
T31_0x4: 00000000
T31_0x14: 00000002
INNO_TRAINING_CTRL 1: 00000000
INNO_TRAINING_CTRL 2: 000000a1
T31_cc: 00000003
INNO_TRAINING_CTRL 3: 000000a0
T31_118: 0000003c
T31_158: 0000003c
T31_190: 0000001f
T31_194: 0000001d
jz-04 :  0x00000051
jz-08 :  0x000000a0
jz-28 :  0x00000024
DDR PHY init OK
INNO_DQ_WIDTH   :00000003
INNO_PLL_FBDIV  :00000014
INNO_PLL_PDIV   :00000005
INNO_MEM_CFG    :00000051
INNO_PLL_CTRL   :00000018
INNO_CHANNEL_EN :0000000d
INNO_CWL        :00000006
INNO_CL         :00000007
DDR Controller init
DDRC_STATUS         0x80000001
DDRC_CFG            0x0a288a40
DDRC_CTRL           0x0000011c
DDRC_LMR            0x00400008
DDRC_DLP            0x00000000
DDRC_TIMING1        0x040e0806
DDRC_TIMING2        0x02170707
DDRC_TIMING3        0x2007051e
DDRC_TIMING4        0x1a240031
DDRC_TIMING5        0xff060405
DDRC_TIMING6        0x32170505
DDRC_REFCNT         0x00f26801
DDRC_MMAP0          0x000020fc
DDRC_MMAP1          0x00002400
DDRC_REMAP1         0x03020d0c
DDRC_REMAP2         0x07060504
DDRC_REMAP3         0x0b0a0908
DDRC_REMAP4         0x0f0e0100
DDRC_REMAP5         0x13121110
DDRC_AUTOSR_EN      0x00000000
sdram init finished
SDRAM init ok
board_init_r
image entry point: 0x80100000

U-Boot 2013.07 (Oct 26 2020 - 14:49:24)

Board: ISVP (Ingenic XBurst T31 SoC)
DRAM:  64 MiB
Top of RAM usable for U-Boot at: 84000000
Reserving 446k for U-Boot at: 83f90000
Reserving 32784k for malloc() at: 81f8c000
Reserving 32 Bytes for Board Info at: 81f8bfe0
Reserving 124 Bytes for Global Data at: 81f8bf64
Reserving 128k for boot params() at: 81f6bf64
Stack Pointer at: 81f6bf48
Now running in RAM - U-Boot at: 83f90000
MMC:   msc: 0
the manufacturer 0b
SF: Detected XT25F128B

*** Warning - bad CRC, using default environment

the manufacturer 0b
SF: Detected XT25F128B

check addr: 0x1ffffc, buf_work: WORK
check addr: 0x4ffffc, buf_work: WORK
check addr: 0xb6fffc, buf_work: WORK
*****start from Main*****
In:    serial
Out:   serial
Err:   serial
Net:   ====>PHY not found!Jz4775-9161
Hit any key to stop autoboot:  0
isvp_t31# <INTERRUPT>
```

```
isvp_t31# help
?       - alias for 'help'
base    - print or set address offset
boot    - boot default, i.e., run 'bootcmd'
boota   - boot android system
bootd   - boot default, i.e., run 'bootcmd'
bootm   - boot application image from memory
bootp   - boot image via network using BOOTP/TFTP protocol
chpart  - change active partition
cmp     - memory compare
coninfo - print console devices and information
cp      - memory copy
crc32   - checksum calculation
echo    - echo args to console
env     - environment handling commands
ethphy  - ethphy contrl
fatinfo - print information about filesystem
fatload - load binary file from a dos filesystem
fatls   - list files in a directory (default /)
gettime - get timer val elapsed,

go      - start application at address 'addr'
help    - print command description/usage
loadb   - load binary file over serial line (kermit mode)
loads   - load S-Record file over serial line
loady   - load binary file over serial line (ymodem mode)
loop    - infinite loop on address range
md      - memory display
mm      - memory modify (auto-incrementing address)
mmc     - MMC sub system
mmcinfo - display MMC info
mtdparts- define flash/nand partitions
mw      - memory write (fill)
nm      - memory modify (constant address)
ping    - send ICMP ECHO_REQUEST to network host
printenv- print environment variables
reset   - Perform RESET of the CPU
run     - run commands in an environment variable
saveenv - save environment variables to persistent storage
sdupdate- auto upgrade file from mmc to flash
setenv  - set environment variables
sf      - SPI flash sub-system
sleep   - delay execution for some time
source  - run script from memory
tftpboot- boot image via network using TFTP protocol
version - print monitor, compiler and linker version
watchdog- open or colse the watchdog
```

```
isvp_t31# printenv
baudrate=115200
bootargs=console=ttyS1,115200n8 mem=46M@0x0 rmem=18M@0x2e00000 init=/linuxrc rootfstype=squashfs root=/dev/mtdblock2 rw mtdparts=jz_sfc:256k(boot),1792k(kernel),3072k(rootfs),6592k(user),1792k(kernel2),2560k(rootfs2),256k(mtd_rw),-(factory)
bootcmd=sdupdate;sf probe;sf read 0x80600000 0x40000 0x1C0000; bootm 0x80600000
bootdelay=1
ethact=Jz4775-9161
ethaddr=00:d0:d0:00:95:27
gatewayip=193.169.4.1
ipaddr=193.169.4.81
loads_echo=1
netmask=255.255.255.0
serverip=193.169.4.2
stderr=serial
stdin=serial
stdout=serial

Environment size: 562/16380 bytes
isvp_t31#
```

Attempt to upgrade with `FIRMWARE.bin` file on the SD card failed.
Seems it requires a specific format of the file.

```
>>>>Auto upgrade start!
Interface:  MMC
  Device 0: Vendor: Man 000000 Snr 00011800 Rev: 10.11 Prod: APPSD
            Type: Removable Hard Disk
            Capacity: 60.0 MB = 0.0 GB (122880 x 512)
Filesystem: FAT16 "NO NAME    "
the manufacturer 0b
SF: Detected XT25F128B

reading FIRMWARE.bin
read FIRMWARE.bin sz 64 hdr 64
------------- hdr -------------
(Image Header Magic Number) ih_magic 0x3040506
(Image Header CRC Checksum) ih_hcrc 0x55aa5502
(Image Creation Timestamp ) ih_time 0x78aa
(Image Data Size          ) ih_size 0x3698
(Data Load Address        ) ih_load 0x0
(Entry Point Address      ) ih_ep 0x0
(Image Data CRC Checksum  ) ih_dcrc 0x0
(Operating System         ) ih_os 0x0
(CPU architecture         ) ih_arch 0x0
(Image Type               ) ih_type 0x0
(Compression Type         ) ih_comp 0x0
(Image Name               ) ih_name
-------------------------------
Image FIRMWARE.bin bad MAGIC or ARCH
*** Warning - CRC, using default environment
```

Luckily, the device has a non-locked U-Boot, so it's possible to flash a new
firmware from the U-Boot console and an SD card:

```
isvp_t31# <INTERRUPT>
isvp_t31# watchdog 0
watchdog close!
isvp_t31# setenv baseaddr 0x82000000;
isvp_t31# setenv partsize 0x1000000;
isvp_t31# mw.b ${baseaddr} 0xff ${partsize};
isvp_t31# fatload mmc 0:1 ${baseaddr} FIRMWARE.bin;
reading FIRMWARE.bin
16777216 bytes read in 1406 ms (11.4 MiB/s)
isvp_t31# sf probe 0;
the manufacturer 0b
SF: Detected XT25F128B

--->probe spend 5 ms
isvp_t31# sf erase 0x0 ${partsize};
SF: 16777216 bytes @ 0x0 Erased: OK
--->erase spend 25859 ms
isvp_t31# sf write ${baseaddr} 0x0 ${filesize};
SF: 16777216 bytes @ 0x0 Written: OK
--->write spend 13026 ms
isvp_t31# reset
```
