Pesita X09
==========

https://www.amazon.ca/dp/B0B6J5TZJB

### Hardware

- SoC: Ingenic T31N (64 MB)
- Image Sensor:
	- JXF23 (2MP)
- Wi-Fi Module: Realtek RTL8189FTV (SDIO)
- Flash Chip: NOR 16MB (NOR 25Q128)
- Power: 5V DC (microUSB port)

### Installation

#### Programmer method

1. Rotate the ball all the way face down, remove rubber plug and undo a single screw on the back of the ball.
2. Slightly squeeze the ball from sides and use a guitar pick to split the ball open.
3. Undo two screws holding the PCB to get access to the flash chip on the front side of the PCB.
3. Clip the flash chip and use a CH341A programmer to install the firmware.

#### UART + SD card method

1. Download a firmware image from the [Thingino website](https://thingino.com/).
2. Copy the image to a FAT32 formatted SD card as `thingino.bin`.
3. Connect the UART contacts to a USB to TTL adapter.
4. Power the device and interrupt the boot process to get to the U-Boot prompt.
5. Run the following commands line by line to flash the firmware.
   ```
   setenv baseaddr 0x82000000;
   setenv partsize 0x1000000;
   mw.b ${baseaddr} 0xff ${partsize};
   fatload mmc 0:1 ${baseaddr} thingino.bin;
   sf probe 0;
   sf erase 0x0 ${partsize};
   sf write ${baseaddr} 0x0 ${filesize};
   reset
   ```

### UART

UART contacts are available as 1.27mm pitch holes near the vertical motor
terminals, marked `R`, `T`, and `G`.

### Motors

Motor terminals are 1.5mm pitch JST-ZH 5-pin connectors.

### Notes

My unit had a low quality soldering. Both motor terminals came off the PCB when
I tried to unplugged them. I had to re-solder them back.


### Stock boot log

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
T31_190: 00000020
T31_194: 0000001e
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
DDRC_REFCNT         0x00f26a01
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
the manufacturer 20
SF: Detected XM25QH128C

*** Warning - bad CRC, using default environment

the manufacturer 20
SF: Detected XM25QH128C

check addr: 0x1ffffc, buf_work: WORK
check addr: 0x4ffffc, buf_work: WORK
check addr: 0xb6fffc, buf_work: WORK
*****start from Main*****
In:    serial
Out:   serial
Err:   serial
Net:   ====>PHY not found!Jz4775-9161
Hit any key to stop autoboot:  1  0
>>>>Auto upgrade start!
Card did not respond to voltage select!
sdupdate - auto upgrade file from mmc to flash

Usage:
sdupdate LOAD_ID ADDR_START ADDR_END
LOAD_ID: 0-->u-boot
	 1-->kernel
	 2-->rootfs
    3-->FIRMWARE.bin
ex:
	sdupdate   (update all)
or
	sdupdate 0 0x0 0x40000
the manufacturer 20
SF: Detected XM25QH128C

--->probe spend 4 ms
SF: 1835008 bytes @ 0x40000 Read: OK
--->read spend 591 ms
## Booting kernel from Legacy Image at 80600000 ...
   Image Name:   Linux-3.10.14__isvp_swan_1.0__
   Image Type:   MIPS Linux Kernel Image (lzma compressed)
   Data Size:    1774534 Bytes = 1.7 MiB
   Load Address: 80010000
   Entry Point:  803d6290
   Verifying Checksum ... OK
   Uncompressing Kernel Image ... OK

Starting kernel ...

[    0.000000] Initializing cgroup subsys cpu
[    0.000000] Initializing cgroup subsys cpuacct
[    0.000000] Linux version 3.10.14__isvp_swan_1.0__ (root@ubuntu) (gcc version 4.7.2 (Ingenic r2.3.3 2016.12) ) #2 PREEMPT Tue Jun 15 02:43:38 PDT 2021
[    0.000000] bootconsole [early0] enabled
[    0.000000] CPU0 RESET ERROR PC:86300115
[    0.000000] CPU0 revision is: 00d00100 (Ingenic Xburst)
[    0.000000] FPU revision is: 00b70000
[    0.000000] CCLK:1404MHz L2CLK:702Mhz H0CLK:250MHz H2CLK:250Mhz PCLK:125Mhz
[    0.000000] Determined physical RAM map:
[    0.000000]  memory: 00507000 @ 00010000 (usable)
[    0.000000]  memory: 00039000 @ 00517000 (usable after init)
[    0.000000] User-defined physical RAM map:
[    0.000000]  memory: 02e00000 @ 00000000 (usable)
[    0.000000] Zone ranges:
[    0.000000]   Normal   [mem 0x00000000-0x02dfffff]
[    0.000000] Movable zone start for each node
[    0.000000] Early memory node ranges
[    0.000000]   node   0: [mem 0x00000000-0x02dfffff]
[    0.000000] Primary instruction cache 32kB, 8-way, VIPT, linesize 32 bytes.
[    0.000000] Primary data cache 32kB, 8-way, VIPT, no aliases, linesize 32 bytes
[    0.000000] pls check processor_id[0x00d00100],sc_jz not support!
[    0.000000] MIPS secondary cache 128kB, 8-way, linesize 32 bytes.
[    0.000000] Built 1 zonelists in Zone order, mobility grouping off.  Total pages: 11684
[    0.000000] Kernel command line: console=ttyS1,115200n8 mem=46M@0x0 rmem=18M@0x2e00000 init=/linuxrc rootfstype=squashfs root=/dev/mtdblock2 rw mtdparts=jz_sfc:256k(boot),1792k(kernel),3072k(rootfs),6592k(user),1792k(kernel2),2560k(rootfs2),256k(mtd_rw),-(factory)
[    0.000000] PID hash table entries: 256 (order: -2, 1024 bytes)
[    0.000000] Dentry cache hash table entries: 8192 (order: 3, 32768 bytes)
[    0.000000] Inode-cache hash table entries: 4096 (order: 2, 16384 bytes)
[    0.000000] Memory: 40660k/47104k available (3900k kernel code, 6444k reserved, 1243k data, 228k init, 0k highmem)
[    0.000000] SLUB: HWalign=32, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
[    0.000000] Preemptible hierarchical RCU implementation.
[    0.000000] NR_IRQS:358
[    0.000000] clockevents_config_and_register success.
[    0.000015] Calibrating delay loop... 1397.55 BogoMIPS (lpj=6987776)
[    0.037792] pid_max: default: 32768 minimum: 301
[    0.042648] Mount-cache hash table entries: 512
[    0.047581] Initializing cgroup subsys debug
[    0.051838] Initializing cgroup subsys freezer
[    0.058106] regulator-dummy: no parameters
[    0.062295] NET: Registered protocol family 16
[    0.077161] bio: create slab <bio-0> at 0
[    0.082640] jz-dma jz-dma: JZ SoC DMA initialized
[    0.087597] usbcore: registered new interface driver usbfs
[    0.093109] usbcore: registered new interface driver hub
[    0.098590] usbcore: registered new device driver usb
[    0.103751]  (null): set:311  hold:312 dev=125000000 h=625 l=625
[    0.109877] media: Linux media interface: v0.10
[    0.114424] Linux video capture interface: v2.00
[    0.119261] Advanced Linux Sound Architecture Driver Initialized.
[    0.126658] Switching to clocksource jz_clocksource
[    0.131992] jz-dwc2 jz-dwc2: cgu clk gate get error
[    0.136950] cfg80211: Calling CRDA to update world regulatory domain
[    0.143375] DWC IN DEVICE ONLY MODE
[    0.147480] dwc2 dwc2: Keep PHY ON
[    0.150844] dwc2 dwc2: Using Buffer DMA mode
[    0.155193] dwc2 dwc2: Core Release: 3.00a
[    0.159550] dwc2 dwc2: enter dwc2_gadget_plug_change:2589: plugin = 1 pullup_on = 0 suspend = 0
[    0.168454] NET: Registered protocol family 2
[    0.173221] TCP established hash table entries: 512 (order: 0, 4096 bytes)
[    0.180130] TCP bind hash table entries: 512 (order: -1, 2048 bytes)
[    0.186610] TCP: Hash tables configured (established 512 bind 512)
[    0.192894] TCP: reno registered
[    0.196104] UDP hash table entries: 256 (order: 0, 4096 bytes)
[    0.202048] UDP-Lite hash table entries: 256 (order: 0, 4096 bytes)
[    0.208563] NET: Registered protocol family 1
[    0.213177] RPC: Registered named UNIX socket transport module.
[    0.219105] RPC: Registered udp transport module.
[    0.223924] RPC: Registered tcp transport module.
[    0.228640] RPC: Registered tcp NFSv4.1 backchannel transport module.
[    0.235485] freq_udelay_jiffys[0].max_num = 10
[    0.239908] cpufreq 	udelay 	loops_per_jiffy
[    0.244358] 12000	 59724	 59724
[    0.247591] 24000	 119449	 119449
[    0.251034] 60000	 298622	 298622
[    0.254486] 120000	 597245	 597245
[    0.258009] 200000	 995409	 995409
[    0.261578] 300000	 1493114	 1493114
[    0.265249] 600000	 2986229	 2986229
[    0.268957] 792000	 3941822	 3941822
[    0.272676] 1008000	 5016864	 5016864
[    0.276462] 1200000	 5972458	 5972458
[    0.284002] squashfs: version 4.0 (2009/01/31) Phillip Lougher
[    0.290512] jffs2: version 2.2. © 2001-2006 Red Hat, Inc.
[    0.296348] msgmni has been set to 79
[    0.301062] io scheduler noop registered
[    0.305076] io scheduler cfq registered (default)
[    0.310847] jz-uart.1: ttyS1 at MMIO 0x10031000 (irq = 58) is a uart1
[    0.318446] console [ttyS1] enabled, bootconsole disabled
[    0.318446] console [ttyS1] enabled, bootconsole disabled
[    0.332309] brd: module loaded
[    0.336810] loop: module loaded
[    0.340476] zram: Created 2 device(s) ...
[    0.344788] logger: created 256K log 'log_main'
[    0.349878] jz SADC driver registeres over!
[    0.355084] jz TCU driver register completed
[    0.359833] the id code = 204018, the flash name is XM25QH128C
[    0.365915] JZ SFC Controller for SFC channel 0 driver register
[    0.372061] 8 cmdlinepart partitions found on MTD device jz_sfc
[    0.378178] Creating 8 MTD partitions on "jz_sfc":
[    0.383156] 0x000000000000-0x000000040000 : "boot"
[    0.388504] 0x000000040000-0x000000200000 : "kernel"
[    0.394034] 0x000000200000-0x000000500000 : "rootfs"
[    0.399505] 0x000000500000-0x000000b70000 : "user"
[    0.404890] 0x000000b70000-0x000000d30000 : "kernel2"
[    0.410476] 0x000000d30000-0x000000fb0000 : "rootfs2"
[    0.416117] 0x000000fb0000-0x000000ff0000 : "mtd_rw"
[    0.421669] 0x000000ff0000-0x000001000000 : "factory"
[    0.427262] SPI NOR MTD LOAD OK
[    0.430563] tun: Universal TUN/TAP device driver, 1.6
[    0.435826] tun: (C) 1999-2004 Max Krasnyansky <maxk@qualcomm.com>
[    0.442326] usbcore: registered new interface driver zd1201
[    0.448300] <<<<<<<<<<<<<<jzmmc 20210315 mmc driver
[    0.453411] jzmmc_v1.2 jzmmc_v1.2.0: vmmc regulator missing
[    0.459423] jzmmc_v1.2 jzmmc_v1.2.0: register success!
[    0.464828] <<<<<<<<<<<<<<jzmmc 20210315 mmc driver
[    0.469898] jzmmc_v1.2 jzmmc_v1.2.1: vmmc regulator missing
[    0.475820] jzmmc_v1.2 jzmmc_v1.2.1: register success!
[    0.482116] usbcore: registered new interface driver snd-usb-audio
[    0.488708] TCP: cubic registered
[    0.492184] NET: Registered protocol family 17
[    0.497398] input: gpio-keys as /devices/platform/gpio-keys/input/input0
[    0.504535] drivers/rtc/hctosys.c: unable to open rtc device (rtc0)
[    0.511069] ALSA device list:
[    0.514165]   #0: Dummy 1
[    0.519964] VFS: Mounted root (squashfs filesystem) readonly on device 31:2.
[    0.527720] Freeing unused kernel memory: 228K (80517000 - 80550000)
mdev is ok......
## No Need to do Update ##
[    1.321308] @@@@ tx-isp-probe ok(version H20210407a), compiler date=Apr  7 2021 @@@@@
[    1.374534] jz_codec_register: probe() successful!
[    1.781810] dma dma0chan24: Channel 24 have been requested.(phy id 7,type 0x06 desc a1952000)
[    1.791002] dma dma0chan25: Channel 25 have been requested.(phy id 6,type 0x06 desc a181d000)
[    1.800587] dma dma0chan26: Channel 26 have been requested.(phy id 5,type 0x04 desc a181c000)
[    2.189591] wlan power on
[    2.257413] mmc1: card claims to support voltages below the defined range. These will be ignored.
[    2.286753] mmc1: new SDIO card at address 0001
Welcome to Addx!
rm: can't remove '/system_rw/sensor/*': No such file or directory


Ingenic-uc1_1 login: 1970-01-01 08:00:03.816 [[0;00;37mDEBUG[0;00;00m] CAM_InitErrorReport(): CAM_InitErrorReport Ent
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:27]malloc 64 ok, total malloc 64
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:38]malloc 96 ok, total malloc 160
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 252
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 344
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 436
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 528
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 620
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 712
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 804
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 896
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 988
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 1080
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 1172
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 1264
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 1356
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 1448
1970-01-01 08:00:03.817 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 1540
1970-01-01 08:00:03.818 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 1632
1970-01-01 08:00:03.818 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 1724
1970-01-01 08:00:03.818 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 1816
1970-01-01 08:00:03.818 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 1908
1970-01-01 08:00:03.818 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 92 ok, total malloc 2000
1970-01-01 08:00:03.818 [[0;00;32mINFO [0;00;00m] main(): Init ErrorReport...
1970-01-01 08:00:03.818 [[0;00;32mINFO [0;00;00m] main(): Init SystemParam...
1970-01-01 08:00:03.819 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:model]=CB320
1970-01-01 08:00:03.819 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:platform]=T31N
1970-01-01 08:00:03.819 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:wifi_mod]=rtl8189
1970-01-01 08:00:03.819 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:sensor]=jxf23
1970-01-01 08:00:03.819 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:flash]=16M
1970-01-01 08:00:03.819 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:led_pin]=10
1970-01-01 08:00:03.819 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:irled_pin]=9
1970-01-01 08:00:03.819 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:ircut_n]=48
1970-01-01 08:00:03.819 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:ircut_p]=47
1970-01-01 08:00:03.820 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:adc_night]=1400
1970-01-01 08:00:03.820 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:adc_day]=800
1970-01-01 08:00:03.820 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:motor_model]=32
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:mute_pin]=0
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:ir_model]=0
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:soft_ircut_type]=256
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:mirrorflip]=1
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:hmaxstep]=4180
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:vmaxstep]=1300
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:hmidstep]=2090
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:vmidstep]=950
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:uvc]=1
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:ptz]=1
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:gsensor]=0
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:bluetooth]=0
1970-01-01 08:00:04.152 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:wired]=0
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:onvif]=0
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:rtsp]=1
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:p2p]=0
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_model]=
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_mode]=0
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_irq_pin]=0
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_csn_pin]=0
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_mosi_pin]=0
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_sclk_pin]=0
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_rst_pin]=0
1970-01-01 08:00:04.153 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[server]:env]=staging
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[wifi]:ssid]=addx
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[wifi]:key]=addx-beijing
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[bind]:bindflag]=0
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[bind]:userid]=0
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[bind]:audioplay]=1
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[detect]:enable]=0
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[detect]:sensitivity]=0
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[detect]:reclen]=-1
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[alarm]:duration]=0
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[nightvision]:enable]=0
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[nightvision]:mode]=0
1970-01-01 08:00:04.154 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:language]=en
1970-01-01 08:00:04.155 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:timezone]=480
1970-01-01 08:00:04.485 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:dst]=0
1970-01-01 08:00:04.485 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:networkmtu]=1480
1970-01-01 08:00:04.485 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:debugreport]=0
1970-01-01 08:00:04.485 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[motiontrack]:enable]=0
1970-01-01 08:00:04.506 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[motiontrack]:type]=0
1970-01-01 08:00:04.506 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[common]:antiflicker]=60
1970-01-01 08:00:04.506 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[common]:mirrorflip]=0
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[common]:alarmenable]=0
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[reclamp]:enable]=1
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:voiceswitch]=1
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:voicevol]=50
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:alarmvol]=90
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:voicereminder]=1
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[motor]:speed]=50
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[devicestatus]:reportstatusinterval]=30
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[video]:mainformat]=0
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[video]:subformat]=0
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[keepwatch]:enable]=0
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[keepwatch]:xstep]=0
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[keepwatch]:ystep]=0
1970-01-01 08:00:04.507 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[recovery]:enable]=1
1970-01-01 08:00:04.508 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[recovery]:xstep]=2090
1970-01-01 08:00:04.508 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[recovery]:ystep]=950
1970-01-01 08:00:04.508 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[model]:origin_model]=CB320
1970-01-01 08:00:04.508 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[model]:product_model]=CB320-JS
1970-01-01 08:00:04.508 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[model]:custom_model]=X09
1970-01-01 08:00:04.508 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:default_dns1]=
1970-01-01 08:00:04.508 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:default_dns2]=
1970-01-01 08:00:04.508 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:cloud_dns1]=
1970-01-01 08:00:04.508 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:cloud_dns2]=
1970-01-01 08:00:04.509 [[0;00;32mINFO [0;00;00m] main(): Device Config init...
2021-08-20 00:00:00.000 [[0;00;32mINFO [0;00;00m] main(): mqtt_certificate_time init...
accept fd:5
2021-08-20 00:00:00.000 [[0;00;32mINFO [0;00;00m] main(): Init LocalSocketClient...
2021-08-20 00:00:00.000 [[0;00;32mINFO [0;00;00m] main(): Init LocalSocket_Thr...
2021-08-20 00:00:00.000 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:27]malloc 64 ok, total malloc 2064
2021-08-20 00:00:00.000 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:38]malloc 36 ok, total malloc 2100
2021-08-20 00:00:00.000 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 2396
2021-08-20 00:00:00.000 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 2692
2021-08-20 00:00:00.000 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 2988
2021-08-20 00:00:00.332 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 3284
2021-08-20 00:00:00.332 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 3580
2021-08-20 00:00:00.332 [[0;00;32mINFO [0;00;00m] main(): Start StatemngMsgQueue...
2021-08-20 00:00:00.366 [[0;00;32mINFO [0;00;00m] main(): Start MQTTPubReqBufInit...
2021-08-20 00:00:00.366 [[0;00;32mINFO [0;00;00m] main(): Start NTPC...
2021-08-20 00:00:00.366 [[0;00;32mINFO [0;00;00m] main(): Start EventQuery...
2021-08-20 00:00:00.367 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [AudioPlay_AudioTalkInit:345]malloc 131088 ok, total malloc 134668
2021-08-20 00:00:00.367 [[0;00;32mINFO [0;00;00m] main():
*********
 4180-1300-2090-950
*********
Enter CAM_STATEMNG_INIT
2021-08-20 00:00:00.374 [[0;00;37mDEBUG[0;00;00m] Cam_LedCtl_SetMode(): LedCtl Scene is 1.
2021-08-20 00:00:00.374 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): Led init...
2021-08-20 00:00:00.374 [[0;00;37mDEBUG[0;00;00m] StateMng_EnterInit(): the sensor is jxf23
sensor_info.name is jxf23
[    5.832038] -----jxf23_detect: 1374 ret = 0, v = 0x0f
[    5.837772] -----jxf23_detect: 1382 ret = 0, v = 0x23
[    5.843319] jxf23 chip found @ 0x40 (i2c0)
[    5.847605] sensor driver version H20200408a
[    6.296561] jxf23 stream on
---- FPGA board is ready ----
  Board UID : 30AB6E51
  Board HW ID : 72000460
  Board rev.  : 5DE5A975
  Board date  : 20190326
-----------------------------
2021-08-20 00:00:01.859 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): System init...
2021-08-20 00:00:01.909 [[0;00;37mDEBUG[0;00;00m] Cam_Ircut_Init(): hard ware ir!
2021-08-20 00:00:01.942 [[0;00;37mDEBUG[0;00;00m] ipc_ircut_switch_mode(): IMP_ISP_Tuning_SetSensorFPS mode Day, fps 15
2021-08-20 00:00:02.027 [[0;00;37mDEBUG[0;00;00m] Audio_Hardware_Mute_Enable(): mute enable 1
[    7.001608] codec_set_device: set device: MIC...
ERROR: no aec_version this parameter in /etc/webrtc_profile.ini file
ERROR: no set_suppression_mode this parameter in /etc/webrtc_profile.ini file
ERROR: no set_far_pow_thd this parameter in /etc/webrtc_profile.ini file
[    7.311555] codec_set_device: set device: speaker...
======apm_audiotest_register_external_opts, pfdatachannel_send=59464cx
2021-08-20 00:00:02.806 [[0;00;32mINFO [0;00;00m] Ipc_Ivs_Register_RecordCallback(): [ivs] record callback set success.
2021-08-20 00:00:02.806 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): Media init...
2021-08-20 00:00:02.806 [[0;01;31mERROR[0;00;00m] AudioPlay_SetState(): setaplay state:1->14
2021-08-20 00:00:02.806 [[0;00;37mDEBUG[0;00;00m] Audio_Hardware_Mute_Enable(): mute enable 0
2021-08-20 00:00:02.807 [[0;00;37mDEBUG[0;00;00m] Audio_SetAoVol(): ###### Audio_SetAoVol:48 ######
2021-08-20 00:00:02.807 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [AudioPlay_VoiceFile:486]malloc 144 ok, total malloc 134812
2021-08-20 00:00:03.236 [[0;00;37mDEBUG[0;00;00m] AudioPlay_VoiceFile(): Play VoiceFile:/usr/notify/common/poweron.aac End
2021-08-20 00:00:03.807 [[0;00;32mINFO [0;00;00m] Ipc_Motor_Init(): [app motor] motor ctl init start...
2021-08-20 00:00:03.807 [[0;00;32mINFO [0;00;00m] Ipc_Motor_Param_init(): [app motor] correct steps, max(4180, 1300), mid(2090, 950)
2021-08-20 00:00:03.807 [[0;00;32mINFO [0;00;00m] Ipc_Motor_Param_init(): [app motor] nModel[32] nSpeed[50]
2021-08-20 00:00:03.808 [[0;00;32mINFO [0;00;00m] Ipc_Motor_Init(): [app motor] motor ctl init finished.
2021-08-20 00:00:03.808 [[0;00;32mINFO [0;00;00m] Ipc_MotorCtl_Reset(): [app motor] motor event -> reset start...
2021-08-20 00:00:05.356 [[0;00;37mDEBUG[0;00;00m] _mem_free(): [AudioPlay_VoiceFile:486]free 144 ok, total malloc 134668
2021-08-20 00:00:05.357 [[0;01;31mERROR[0;00;00m] AudioPlay_SetState(): setaplay state:0->0
2021-08-20 00:00:05.357 [[0;00;37mDEBUG[0;00;00m] Audio_Hardware_Mute_Enable(): mute enable 1
2021-08-20 00:00:26.796 [[0;00;32mINFO [0;00;00m] Ipc_MotorCtl_Reset(): [app motor] motor event -> reset end.
2021-08-20 00:00:26.796 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): motor reset finished.
2021-08-20 00:00:26.796 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): Start cJSON Init...
2021-08-20 00:00:26.796 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): Start SDCard Check...
2021-08-20 00:00:26.797 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): Start ResetKey...
create device_status_monitor_thr_fun success!
2021-08-20 00:00:26.797 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): Start dev_status_monitor...
2021-08-20 00:00:26.797 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): Start SleepPlan...
2021-08-20 00:00:26.797 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:27]malloc 64 ok, total malloc 134732
2021-08-20 00:00:26.797 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:38]malloc 36 ok, total malloc 134768
2021-08-20 00:00:26.797 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 135064
2021-08-20 00:00:26.797 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 135360
2021-08-20 00:00:26.797 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 135656
2021-08-20 00:00:26.797 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 135952
2021-08-20 00:00:26.797 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 136248
2021-08-20 00:00:26.797 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): Start Network...
2021-08-20 00:00:26.797 [[0;00;37mDEBUG[0;00;00m] CAM_InitEventPush(): CAM_InitEventPush Ent
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:27]malloc 64 ok, total malloc 136312
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:38]malloc 56 ok, total malloc 136368
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 136664
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 136960
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 137256
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 137552
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 137848
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 138144
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 138440
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 138736
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 139032
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 139328
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] CAM_InitRecord(): CAM_InitRecord Ent
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:27]malloc 64 ok, total malloc 139392
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:38]malloc 36 ok, total malloc 139428
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 139724
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 140020
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 140316
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 140612
2021-08-20 00:00:26.798 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 140908
2021-08-20 00:00:27.129 [[0;00;37mDEBUG[0;00;00m] CAM_InitPlayBack(): CAM_InitPlayBack Ent
2021-08-20 00:00:27.129 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:27]malloc 64 ok, total malloc 294588
2021-08-20 00:00:27.129 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:38]malloc 36 ok, total malloc 294624
2021-08-20 00:00:27.129 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 294920
2021-08-20 00:00:27.129 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 295216
2021-08-20 00:00:27.129 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 295512
2021-08-20 00:00:27.129 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 295808
2021-08-20 00:00:27.129 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [CAM_QUEUE_Create:40]malloc 296 ok, total malloc 296104
2021-08-20 00:00:27.130 [[0;00;32mINFO [0;00;00m] Ipc_Ivs_Instance_Init(): [ivs] ipc ivs instance init...
2021-08-20 00:00:27.131 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [EventPushProcThread:100]malloc 153616 ok, total malloc 294524
2021-08-20 00:00:27.131 [[0;00;37mDEBUG[0;00;00m] NetWorkConfigReset(): the bindflag is 0
2021-08-20 00:00:27.134 [[0;00;32mINFO [0;00;00m] Ipc_Ivs_Move_Det_Init(): [ivs] mov det init successed.
2021-08-20 00:00:27.134 [[0;00;32mINFO [0;00;00m] Ipc_Ivs_Instance_Init(): [ivs] ipc ivs instance init finished.
2021-08-20 00:00:27.134 [[0;00;32mINFO [0;00;00m] StateMng_EnterInit(): Start Ivs...
2021-08-20 00:00:27.134 [[0;00;32mINFO [0;00;00m] Ipc_Ivs_MovDet_Thread(): [ivs] thread Ipc_Ivs_MovDet_Thread start...
2021-08-20 00:00:27.196 [[0;00;32mINFO [0;00;00m] NetWorkConfigReset(): [app motor] network reset, clear keepwatch position
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:model]=CB320
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:platform]=T31N
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:wifi_mod]=rtl8189
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:sensor]=jxf23
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:flash]=16M
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:led_pin]=10
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:irled_pin]=9
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:ircut_n]=48
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:ircut_p]=47
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:adc_night]=1400
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:adc_day]=800
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:motor_model]=32
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:mute_pin]=0
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:ir_model]=0
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:soft_ircut_type]=256
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:mirrorflip]=1
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:hmaxstep]=4180
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:vmaxstep]=1300
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:hmidstep]=2090
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:vmidstep]=950
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:uvc]=1
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:ptz]=1
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:gsensor]=0
2021-08-20 00:00:27.206 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:bluetooth]=0
2021-08-20 00:00:27.207 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:wired]=0
2021-08-20 00:00:27.207 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:onvif]=0
2021-08-20 00:00:27.207 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:rtsp]=1
2021-08-20 00:00:27.539 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:p2p]=0
2021-08-20 00:00:27.539 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_model]=
2021-08-20 00:00:27.539 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_mode]=0
2021-08-20 00:00:27.539 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_irq_pin]=0
2021-08-20 00:00:27.539 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_csn_pin]=0
2021-08-20 00:00:27.539 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_mosi_pin]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_sclk_pin]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_rst_pin]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[server]:env]=staging
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[wifi]:ssid]=addx
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[wifi]:key]=addx-beijing
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[bind]:bindflag]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[bind]:userid]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[bind]:audioplay]=1
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[detect]:enable]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[detect]:sensitivity]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[detect]:reclen]=-1
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[alarm]:duration]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[nightvision]:enable]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[nightvision]:mode]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:language]=en
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:timezone]=480
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:dst]=0
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:networkmtu]=1480
2021-08-20 00:00:27.540 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:debugreport]=0
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[motiontrack]:enable]=0
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[motiontrack]:type]=0
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[common]:antiflicker]=60
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[common]:mirrorflip]=0
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[common]:alarmenable]=0
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[reclamp]:enable]=1
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:voiceswitch]=1
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:voicevol]=50
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:alarmvol]=90
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:voicereminder]=1
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[motor]:speed]=50
2021-08-20 00:00:27.541 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[devicestatus]:reportstatusinterval]=30
2021-08-20 00:00:27.872 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[video]:mainformat]=0
2021-08-20 00:00:27.872 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[video]:subformat]=0
2021-08-20 00:00:27.872 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[keepwatch]:enable]=0
2021-08-20 00:00:27.872 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[keepwatch]:xstep]=0
2021-08-20 00:00:27.872 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[keepwatch]:ystep]=0
2021-08-20 00:00:27.872 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[recovery]:enable]=1
2021-08-20 00:00:27.872 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[recovery]:xstep]=2090
2021-08-20 00:00:27.873 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[recovery]:ystep]=950
2021-08-20 00:00:27.873 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[model]:origin_model]=CB320
2021-08-20 00:00:27.873 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[model]:product_model]=CB320-JS
2021-08-20 00:00:27.873 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[model]:custom_model]=X09
2021-08-20 00:00:27.873 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:default_dns1]=
2021-08-20 00:00:27.873 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:default_dns2]=
2021-08-20 00:00:27.873 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:cloud_dns1]=
2021-08-20 00:00:27.873 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:cloud_dns2]=
2021-08-20 00:00:27.889 [[0;00;37mDEBUG[0;00;00m] NetWorkProcThread(): CAM_NETWORK_START_BIND
2021-08-20 00:00:27.889 [[0;00;37mDEBUG[0;00;00m] NetWorkProcThread(): sleepPlan suspend for network start bind
2021-08-20 00:00:27.889 [[0;00;37mDEBUG[0;00;00m] SleepPlan_Suspend(): nSuspend is 1
2021-08-20 00:00:27.889 [[0;00;37mDEBUG[0;00;00m] SleepPlan_Suspend(): Suspend SleepPlan
2021-08-20 00:00:27.892 [[0;00;37mDEBUG[0;00;00m] NetWorkProcThread(): MQTT not inited...
2021-08-20 00:00:27.892 [[0;00;37mDEBUG[0;00;00m] NetWorkConfigReset(): the bindflag is 0
2021-08-20 00:00:27.914 [[0;00;32mINFO [0;00;00m] NetWorkConfigReset(): [app motor] network reset, clear keepwatch position
2021-08-20 00:00:27.914 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:model]=CB320
2021-08-20 00:00:27.914 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:platform]=T31N
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:wifi_mod]=rtl8189
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:sensor]=jxf23
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:flash]=16M
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:led_pin]=10
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:irled_pin]=9
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:ircut_n]=48
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:ircut_p]=47
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:adc_night]=1400
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:adc_day]=800
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:motor_model]=32
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:mute_pin]=0
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:ir_model]=0
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[hardware]:soft_ircut_type]=256
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:mirrorflip]=1
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:hmaxstep]=4180
2021-08-20 00:00:27.915 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:vmaxstep]=1300
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:hmidstep]=2090
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[software]:vmidstep]=950
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:uvc]=1
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:ptz]=1
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:gsensor]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:bluetooth]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:wired]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:onvif]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:rtsp]=1
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[support]:p2p]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_model]=
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_mode]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_irq_pin]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_csn_pin]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_mosi_pin]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_sclk_pin]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[ble]:ble_rst_pin]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[server]:env]=staging
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[wifi]:ssid]=addx
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[wifi]:key]=addx-beijing
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[bind]:bindflag]=0
2021-08-20 00:00:28.247 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[bind]:userid]=0
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[bind]:audioplay]=1
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[detect]:enable]=0
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[detect]:sensitivity]=0
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[detect]:reclen]=-1
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[alarm]:duration]=0
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[nightvision]:enable]=0
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[nightvision]:mode]=0
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:language]=en
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:timezone]=480
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:dst]=0
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:networkmtu]=1480
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[advance]:debugreport]=0
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[motiontrack]:enable]=0
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[motiontrack]:type]=0
2021-08-20 00:00:28.248 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[common]:antiflicker]=60
2021-08-20 00:00:28.579 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[common]:mirrorflip]=0
2021-08-20 00:00:28.579 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[common]:alarmenable]=0
2021-08-20 00:00:28.579 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[reclamp]:enable]=1
2021-08-20 00:00:28.579 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:voiceswitch]=1
2021-08-20 00:00:28.579 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:voicevol]=50
2021-08-20 00:00:28.579 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:alarmvol]=90
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[audio]:voicereminder]=1
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[motor]:speed]=50
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[devicestatus]:reportstatusinterval]=30
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[video]:mainformat]=0
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[video]:subformat]=0
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[keepwatch]:enable]=0
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[keepwatch]:xstep]=0
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[keepwatch]:ystep]=0
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[recovery]:enable]=1
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[recovery]:xstep]=2090
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[recovery]:ystep]=950
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[model]:origin_model]=CB320
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[model]:product_model]=CB320-JS
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[model]:custom_model]=X09
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:default_dns1]=
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:default_dns2]=
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:cloud_dns1]=
2021-08-20 00:00:28.580 [[0;00;37mDEBUG[0;00;00m] DEVCONFIG_LoadTableConfig(): [[dns]:cloud_dns2]=
2021-08-20 00:00:28.581 [[0;00;32mINFO [0;00;00m] webrtc_stop(): webrtc_stop
2021-08-20 00:00:28.605 [[0;00;32mINFO [0;00;00m] addxWebrtcUninit(): KVS WebRTC deinit done
2021-08-20 00:00:28.605 [[0;00;32mINFO [0;00;00m] webrtc_stop(): webrtc_stop done
2021-08-20 00:00:28.605 [[0;00;37mDEBUG[0;00;00m] Cam_LedCtl_SetMode(): LedCtl Scene is 2.
2021-08-20 00:00:28.605 [[0;00;32mINFO [0;00;00m] qrscan_thr_init(): Start Bind...
2021-08-20 00:00:28.605 [[0;00;37mDEBUG[0;00;00m] qrscan_thr_init(): g_ipcenv_args.qrscan_state is 1
2021-08-20 00:00:28.605 [[0;00;37mDEBUG[0;00;00m] network_ble_start(): the eMode is 0
2021-08-20 00:00:28.606 [[0;00;37mDEBUG[0;00;00m] Ipc_Ivs_Set_Enable(): The ivs nEnable is 0
util_complete
2021-08-20 00:00:28.656 [[0;01;31mERROR[0;00;00m] AudioPlay_SetState(): setaplay state:1->1
2021-08-20 00:00:28.665 [[0;00;37mDEBUG[0;00;00m] Audio_Hardware_Mute_Enable(): mute enable 0
2021-08-20 00:00:28.665 [[0;00;37mDEBUG[0;00;00m] Audio_SetAoVol(): ###### Audio_SetAoVol:48 ######
2021-08-20 00:00:28.665 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [AudioPlay_VoiceFile:486]malloc 144 ok, total malloc 296248
2021-08-20 00:00:29.081 [[0;00;37mDEBUG[0;00;00m] AudioPlay_VoiceFile(): Play VoiceFile:/usr/notify/common/startNetConfig.aac End
2021-08-20 00:00:31.122 [[0;00;37mDEBUG[0;00;00m] _mem_free(): [AudioPlay_VoiceFile:486]free 144 ok, total malloc 296104
2021-08-20 00:00:31.122 [[0;01;31mERROR[0;00;00m] AudioPlay_SetState(): setaplay state:0->0
2021-08-20 00:00:31.122 [[0;00;37mDEBUG[0;00;00m] Audio_Hardware_Mute_Enable(): mute enable 1
2021-08-20 00:00:38.686 [[0;01;31mERROR[0;00;00m] AudioPlay_SetState(): setaplay state:1->1
2021-08-20 00:00:38.696 [[0;00;37mDEBUG[0;00;00m] Audio_Hardware_Mute_Enable(): mute enable 0
2021-08-20 00:00:38.696 [[0;00;37mDEBUG[0;00;00m] Audio_SetAoVol(): ###### Audio_SetAoVol:48 ######
2021-08-20 00:00:38.696 [[0;00;37mDEBUG[0;00;00m] _mem_malloc(): [AudioPlay_VoiceFile:486]malloc 144 ok, total malloc 296248
2021-08-20 00:00:39.026 [[0;00;37mDEBUG[0;00;00m] AudioPlay_VoiceFile(): Play VoiceFile:/usr/notify/common/startNetConfig.aac End
2021-08-20 00:00:41.090 [[0;00;37mDEBUG[0;00;00m] _mem_free(): [AudioPlay_VoiceFile:486]free 144 ok, total malloc 296104
2021-08-20 00:00:41.090 [[0;01;31mERROR[0;00;00m] AudioPlay_SetState(): setaplay state:0->0
2021-08-20 00:00:41.090 [[0;00;37mDEBUG[0;00;00m] Audio_Hardware_Mute_Enable(): mute enable 1
 ```

### U-Boot shell

```
Hit any key to stop autoboot:  0
isvp_t31# <INTERRUPT>
isvp_t31# watchdog 0
watchdog close!
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

### Stock U-Boot environment

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
```
