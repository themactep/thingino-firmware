Petcube Cam (C401A)
===================

![Petcube Cam](https://petcube.com/images/sections/product-hero-cam/cam-on-the-post.png)

[Product page](https://petcube.com/cam/)

### Hardware

- SoC: Ingenic T31LC (no NNA), 64MB RAM, eFuse-locked secure boot
- Image Sensor: MIS2008 (2MP, MIPI)
- Wi-Fi Module: AltoBeam ATBM6012B (USB, VID:PID 007a:8888)
- Flash Chip: PY25Q128H SPI NOR 16MB (32K erase block)
- SD Card slot (4-bit MMC0)
- Audio: built-in speaker and microphone
- Power: 5V DC (USB-C)
- No pan/tilt motors

### GPIOs

| Function     | GPIO | Notes                          |
|-------------|------|--------------------------------|
| White LED    | 50   | Active high                    |
| IR 850nm     | 60   | Active high                    |
| IR-cut       | 52/53| Pair                           |
| Reset button | 62   |                                |
| Speaker      | 63   | Enable                         |
| SD detect    | 38   |                                |
| USB VBUS     | 39   | Active high, powers WiFi chip  |

### Secure Boot

The T31LC has eFuse-locked RSA-2048 secure boot. The thingino build uses
the `secureboop` package to generate a collision signature that passes the
boot ROM's weak verification. The RSA modulus was extracted from the stock
SPL at flash offset 0x300.

### Installation

#### SD card method (no tools required)

The stock Petcube firmware automatically runs `/mnt/mmc01/cubeclient` from
the SD card at every boot (via the `S80cubeclient` init script). This can
be used to install thingino without opening the camera or using a
programmer.

1. Download the latest `thingino-petcube_c401a_t31lc_mis2008_atbm6012b.bin`
   firmware image.
2. Format a microSD card as FAT32 (MBR partition table).
3. Copy the firmware image to the SD card root as `thingino.bin`.
4. Copy the install script below to the SD card root as `cubeclient`.
5. Make the script executable: `chmod +x cubeclient`
6. Insert the SD card into the camera and power it on.
7. The white LED turns on solid during flashing (~30 seconds).
8. The camera reboots into thingino automatically. Remove the SD card.

A backup of the stock firmware is saved to the `stock-backup` directory on
the SD card before flashing. Keep this backup in case you want to restore
the original firmware later.

**Install script** (`cubeclient`):

```sh
#!/bin/sh
# Thingino installer for Petcube C401A — runs via stock SD auto-exec.
#
# Stock BusyBox lacks dd/flashcp, so this script writes the firmware
# partition-by-partition using head -c / tail -c and /dev/mtdblock*.

SD=/mnt/mmc01
FW=$SD/thingino.bin
BACKUP=$SD/stock-backup
LED=50

log() { echo "[thingino] $*"; }

gpio_out() {
    echo "$1" > /sys/class/gpio/export 2>/dev/null
    echo out > /sys/class/gpio/gpio$1/direction
}

gpio_out $LED
led() { echo "$1" > /sys/class/gpio/gpio$LED/value; }

if [ ! -f "$FW" ]; then
    log "No firmware file at $FW, skipping."
    exit 0
fi

fw_size=$(wc -c < "$FW")
if [ "$fw_size" -ne 16777216 ]; then
    log "ERROR: firmware must be 16777216 bytes (16MB), got $fw_size"
    exit 1
fi

# Verify head -c is supported (needs CONFIG_FEATURE_FANCY_HEAD in BusyBox)
if ! echo test | head -c 2 > /dev/null 2>&1; then
    log "ERROR: head -c not supported by this BusyBox build"
    exit 1
fi

log "Starting thingino installation..."

# Backup stock firmware (one file per partition)
if [ ! -d "$BACKUP" ]; then
    log "Backing up stock firmware..."
    mkdir -p "$BACKUP"
    cat /dev/mtdblock0 > "$BACKUP/mtd0_boot.bin"
    cat /dev/mtdblock1 > "$BACKUP/mtd1_sys.bin"
    cat /dev/mtdblock2 > "$BACKUP/mtd2_app.bin"
    cat /dev/mtdblock3 > "$BACKUP/mtd3_recove.bin"
    cat /dev/mtdblock4 > "$BACKUP/mtd4_cfg.bin"
    cat /dev/mtdblock5 > "$BACKUP/mtd5_enc.bin"
    cat /dev/mtdblock6 > "$BACKUP/mtd6_sysflg.bin"
    sync
    log "Backup saved to $BACKUP/"
else
    log "Backup directory exists, skipping."
fi

# Write firmware image to flash, partition by partition.
# Stock partition offsets (7 partitions, 16MB total):
#   mtd0  0x000000  256K    mtd1  0x040000  2560K
#   mtd2  0x2C0000  7680K   mtd3  0xA40000  5120K
#   mtd4  0xF40000  640K    mtd5  0xFE0000  64K
#   mtd6  0xFF0000  64K
write_part() {
    local dev=$1 offset=$2 size=$3
    log "  $dev ($size bytes @ $offset)"
    if [ "$offset" -eq 0 ]; then
        head -c "$size" "$FW" > "$dev"
    else
        tail -c "+$((offset + 1))" "$FW" | head -c "$size" > "$dev"
    fi
}

log "Flashing thingino firmware..."
led 1

write_part /dev/mtdblock0        0   262144
write_part /dev/mtdblock1   262144  2621440
write_part /dev/mtdblock2  2883584  7864320
write_part /dev/mtdblock3 10747904  5242880
write_part /dev/mtdblock4 15990784   655360
write_part /dev/mtdblock5 16646144    65536
write_part /dev/mtdblock6 16711680    65536
sync

led 0
log "Flash complete."

mv "$SD/cubeclient" "$SD/cubeclient.done"
sync

log "Rebooting into thingino..."
reboot
```

#### Restoring stock firmware

If you kept the `stock-backup` directory from the SD card, you can restore
from the thingino shell (SSH or UART console):

```sh
cat /mnt/mmcblk0p1/stock-backup/mtd0_boot.bin > /dev/mtdblock0
cat /mnt/mmcblk0p1/stock-backup/mtd1_sys.bin > /dev/mtdblock1
cat /mnt/mmcblk0p1/stock-backup/mtd2_app.bin > /dev/mtdblock2
cat /mnt/mmcblk0p1/stock-backup/mtd3_recove.bin > /dev/mtdblock3
cat /mnt/mmcblk0p1/stock-backup/mtd4_cfg.bin > /dev/mtdblock4
cat /mnt/mmcblk0p1/stock-backup/mtd5_enc.bin > /dev/mtdblock5
cat /mnt/mmcblk0p1/stock-backup/mtd6_sysflg.bin > /dev/mtdblock6
sync
reboot
```

Alternatively, concatenate the backup files on a PC and flash with a
CH341A programmer:

```sh
cat mtd0_boot.bin mtd1_sys.bin mtd2_app.bin mtd3_recove.bin \
    mtd4_cfg.bin mtd5_enc.bin mtd6_sysflg.bin > stock-full.bin
```

#### Programmer method

1. Open the camera case (pry tabs at the base).
2. Locate the PY25Q128H SPI NOR flash chip on the PCB.
3. Use a CH341A programmer with a SOIC-8 clip to read/write the flash.
4. Flash the full 16MB firmware image.

### Stock Firmware Partition Layout

| Partition | Offset     | Size       | Description     |
|-----------|-----------|------------|-----------------|
| BOOT      | 0x000000  | 0x040000   | SPL + U-Boot    |
| sys       | 0x040000  | 0x280000   | Kernel          |
| app       | 0x2C0000  | 0x780000   | Application     |
| recove    | 0xA40000  | 0x500000   | Recovery        |
| cfg       | 0xF40000  | 0x0A0000   | Configuration   |
| enc       | 0xFE0000  | 0x010000   | Encryption keys |
| sysflg    | 0xFF0000  | 0x010000   | System flags    |
