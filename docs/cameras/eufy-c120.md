Eufy Indoor Cam 2K C120 (T8400/T8400X)
=======================================

Model Information
-----------------

- **FCC ID:** 2AOKB-T8400
- **Model:** T8400/T8400X
- **Name:** Eufy Indoor Cam 2K C120
- **SoC:** Ingenic T31X (128MB DDR2)
- **WiFi Module:** SYN4343 / BCM4343W
- **Flash:** 16MB (usually Winbond 25Q128 or 25Q256)
- **Product Page:** [https://ca.eufy.com/products/t84001w1](https://ca.eufy.com/products/t84001w1)

Hardware Variations
-------------------

The Eufy C120 is known to have **multiple hardware variations** even within the same model number. This is the most common issue users face when flashing Thingino firmware.

### Known Sensor Variants

1. **SC3235** (2MP, 1920x1080) - Most common
2. **SC3338** (3MP, 2304x1296)
3. **SC3335** (3MP, 2304x1296)

### Known WiFi Module Variants

1. **SYN4343** (Synaptics) - Most common
2. **BCM4343W** (Broadcom) - Some units

### How to Identify Your Variant

#### Visual Inspection
1. Open camera case (usually 3-4 screws under rubber feet)
2. Locate image sensor chip (large square chip near lens)
3. Read chip marking - will be "SC3235", "SC3338", or "SC3335"
4. Note WiFi module marking if visible

#### Trial and Error Method
If you cannot open the camera, try firmware variants in this order:

1. **eufy_t8400x_t31x_sc3235_syn4343** ← Try this first (most common)
2. **eufy_t8400x_t31x_sc3338_syn4343**
3. **eufy_t8400x_t31x_sc3335_syn4343**

Available Firmware Configurations
----------------------------------

### eufy_t8400x_t31x_sc3235_syn4343
- **Image Sensor:** SC3235 (2MP)
- **WiFi Module:** SYN4343
- **Status:** ✅ Most commonly successful
- **Notes:** Works on majority of C120 units

### eufy_t8400x_t31x_sc3338_syn4343
- **Image Sensor:** SC3338 (3MP)
- **WiFi Module:** SYN4343
- **Status:** ✅ Works on some C120 units
- **Notes:** Try if SC3235 version doesn't boot

### eufy_t8400x_t31x_sc3335_syn4343
- **Image Sensor:** SC3335 (3MP)
- **WiFi Module:** SYN4343
- **Status:** ✅ Works on some C120 units
- **Notes:** Less common but some units use this sensor

Flashing Instructions
---------------------

### Recommended: Cloner Method

**Prerequisites:**
- USB cable with data lines (not power-only)
- Ingenic Cloner tool from [thingino.com/cloner](https://thingino.com/cloner)
- Firmware file from [thingino.com](https://thingino.com)

**Steps:**

1. **Download firmware** for your sensor variant
2. **Install Cloner tool** and USB drivers (Windows)
3. **Configure Cloner:**
   - Platform: `t31x`
   - Board: `t31x_sfc_nor_ddr2_writer_full.cfg`
   - Policy tab → Select firmware file
   - Click "Save", "Yes", then "Start"
4. **Enter flash mode:**
   - Connect camera to PC via USB
   - Camera should enter flash mode automatically
   - If not, see "Entering Flash Mode" below
5. **Flash firmware:**
   - Cloner will flash automatically
   - Progress shown in tool
   - Wait for completion (2-5 minutes)

### Alternative: SD Card Method

**Prerequisites:**
- MicroSD card (any size, will be formatted)
- Card reader

**Steps:**

1. **Prepare SD card:**
   ```bash
   # Format as FAT32 with MBR partition table
   sudo mkfs.vfat -F 32 /dev/sdX1
   ```
2. **Copy firmware:**
   - Rename firmware to `autoupdate-full.bin`
   - Copy to SD card root directory
3. **Flash:**
   - Power off camera
   - Insert SD card
   - Power on camera
   - Wait for automatic flash (LED will blink)
   - Camera will reboot when complete

Entering Flash Mode
--------------------

### Method 1: USB Auto-Detection (Easiest)
- Simply connect camera via USB while Cloner is running
- Most cameras enter flash mode automatically

### Method 2: Software Trigger (If Camera Boots)
If you have shell access to camera:
```bash
flash_erase /dev/mtd0
reboot -f
```

### Method 3: Hardware Method (If Camera Won't Boot)
1. Open camera case
2. Locate SPI flash chip (8-pin chip, usually Winbond 25Qxx)
3. Short pins 5 and 6 together (while connected via USB)
4. Camera enters flash mode
5. Release pins once Cloner detects camera

Troubleshooting
---------------

### Camera Won't Boot After Flashing

**Symptom:** No LED activity, no AP, camera appears dead

**Most Likely Cause:** Wrong sensor variant firmware

**Solution:**
1. Try different firmware variant (SC3235 → SC3338 → SC3335)
2. Reflash using Cloner tool
3. Wait at least 3 minutes after flashing for first boot
4. Look for THINGINO-XXXX WiFi network

### Flashing Process Fails Randomly

**Symptom:** Cloner errors out at different stages

**Common Causes:**
- Poor quality USB cable
- Insufficient power
- USB port issues
- Hardware defect on specific camera

**Solutions:**
1. **Use different USB cable** - Must have data lines
2. **Try different USB port** - Prefer USB 2.0 ports
3. **Add external power:**
   - Connect camera to 5V power adapter while flashing
   - Use USB hub with external power
4. **Try multiple times:**
   - Some cameras flash successfully after several attempts
   - Hardware timing issues can be intermittent
5. **Use programmer method** (see below)

### Camera Boots But No Video Stream

**Symptom:** AP appears, can access web UI, but no camera feed

**Cause:** Wrong sensor variant

**Solution:**
- You need different firmware with correct sensor type
- Try next variant in sequence
- Camera works otherwise, just sensor mismatch

### No AP Appears But Camera Seems to Boot

**Symptom:** Hear shutter click, LED activity, but no WiFi AP

**Possible Causes:**
1. **Wrong WiFi module driver**
   - Current firmwares use SYN4343
   - Some units may have BCM4343W (needs testing)
2. **GPIO misconfiguration**
   - WiFi power GPIO may be wrong
3. **Portal startup failure**

**Diagnostic Steps:**
1. Connect via UART to view boot logs
2. Check for WiFi driver loading errors
3. Check for "Portal started" message
4. See [troubleshooting-boot.md](troubleshooting-boot.md)

### Intermittent Flashing on One Camera

**Symptom:** Same camera that works with original firmware fails to flash Thingino consistently

**This is a known issue** with some C120 units:
- Hardware timing variations
- USB communication issues
- Power delivery problems

**Solutions:**
1. **Be persistent** - Multiple flash attempts may succeed
2. **Try programmer method** (most reliable)
3. **External power** - Use 5V adapter during flash
4. **Different PC/port** - Try different computer or USB port

Programmer Method (Most Reliable)
----------------------------------

For cameras that won't flash via USB/Cloner:

**Hardware Needed:**
- CH341A programmer (~$5-10)
- SOIC8 test clip (~$3-5)
- Or: soldering iron to desolder flash chip

**Steps:**
1. **Open camera** and locate flash chip (8-pin Winbond 25Qxx)
2. **Connect programmer:**
   - Attach SOIC8 clip to flash chip
   - Connect clip to CH341A programmer
   - Connect programmer to PC via USB
3. **Flash firmware:**
   ```bash
   # Backup original (recommended!)
   snander -r original_backup.bin
   
   # Flash Thingino
   snander -w thingino-eufy_t8400x_t31x_sc3235_syn4343.bin
   
   # Verify
   snander -v thingino-eufy_t8400x_t31x_sc3235_syn4343.bin
   ```
4. **Reassemble camera** and test

This method bypasses all USB/timing issues and works 100% of the time.

First Boot After Flashing
--------------------------

**What to expect:**

1. **Boot time:** 2-3 minutes on first boot
2. **LED activity:** Blue LED should blink/light up
3. **Shutter click:** Camera may make mechanical sound (IR filter)
4. **WiFi AP:** Network named "THINGINO-XXXX" appears
   - XXXX = last 4 hex digits of MAC address
5. **Voice announcement:** "Portal started" (if speaker works)

**If no AP after 5 minutes:**
- Camera likely failed to boot
- Wrong firmware variant most likely
- Try different sensor variant
- Check UART logs if possible

Configuration Notes
-------------------

### GPIO Mappings (from .uenv.txt)

```
gpio_button=58          # Reset button
gpio_default=25ID 26ID 61o 62o
gpio_ir850=60           # IR LED control
gpio_ircut=49 50        # IR cut filter
gpio_led_b=61O          # Blue LED
gpio_led_r=62O          # Red LED  
gpio_mmc_cd=59          # SD card detect
gpio_mmc_power=17O      # SD card power
gpio_speaker=63         # Speaker/buzzer
gpio_wlan=48O           # WiFi module power
```

### Memory Configuration

- **Total RAM:** 128MB DDR2
- **Reserved Memory (RMEM):** 44MB for ISP/encoder
- **Available for system:** ~84MB

### WiFi Module Settings

For SYN4343 module:
```
wlan_module="bcmdhd"
wlan_module_opts="gpio_wl_reg_on=48 gpio_wl_host_wake=39 firmware_path=/usr/lib/firmware/ nvram_path=/usr/lib/firmware/nv_bcm4343.txt op_mode=2"
```

Success Rate
------------

Based on community reports:

- **2 out of 3 cameras** is typical success rate with single firmware variant
- **Nearly 100% success** when trying all three sensor variants
- Most failures are wrong sensor firmware
- Genuine hardware failures are rare

If Your Camera Won't Work
--------------------------

After trying all three firmware variants and all troubleshooting steps:

1. **Verify hardware compatibility:**
   - Open camera and photograph chips
   - Post to Discord/Telegram for identification
   - May have unsupported variant

2. **Consider programmer method:**
   - Most reliable flashing method
   - Eliminates USB/timing issues
   - Requires minimal soldering skills

3. **Get community help:**
   - [Discord](https://discord.gg/xDmqS944zr)
   - [Telegram](https://t.me/thingino)
   - Include: firmware tried, UART logs, chip photos

4. **Last resort - revert to original:**
   - Flash your backed up original firmware
   - Use programmer method
   - Camera returns to stock functionality

Related Documentation
---------------------

- [Boot Troubleshooting Guide](troubleshooting-boot.md) - Detailed boot diagnostics
- [Camera Recovery Guide](camera-recovery.md) - Recovery procedures
- [Firmware Dumping Guide](firmware.md) - How to backup original firmware
- [Eufy Brand Page](brands/eufy.md) - All Eufy camera models

Community Success Stories
--------------------------

Many users have successfully flashed their C120 cameras. Common patterns:

- **Working on 2/3 cameras:** Different sensor variants
- **Intermittent flashing:** Eventually succeeds with persistence
- **Wrong firmware first try:** Correct variant works perfectly
- **Programmer method:** 100% success rate

**Don't give up!** The correct firmware variant exists for your camera.
