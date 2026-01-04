Troubleshooting Boot Issues
============================

This guide helps diagnose and resolve boot failures when Thingino firmware doesn't start properly on your camera.

Common Symptoms
---------------

### Camera doesn't boot at all
- No LED activity
- No AP (Access Point) appears
- No voice announcement
- Camera appears "dead" after flashing

### Partial boot
- LED blinks but no AP
- Shutter click heard but no further activity
- No network connectivity

Hardware Variation Issues
-------------------------

Some camera models (like the Eufy C120 T8400X) may have hardware variations even within the same model number:

### Different Image Sensors
Cameras with the same model number may have different image sensors:
- SC3235 (2MP)
- SC3335 (3MP)
- SC3338 (3MP)

### Different WiFi Modules
- SYN4343
- BCM4343W
- ATBM6031
- Other variants

### How to Identify Your Hardware

#### Method 1: Check Original Firmware Logs
If you still have access to the original firmware:
1. Enable UART access (see [UART Connection](#uart-connection) below)
2. Boot the camera with original firmware
3. Check the boot logs for sensor and WiFi module information

#### Method 2: Visual Inspection
1. Open the camera carefully
2. Look for chip markings on:
   - Image sensor (usually marked with "SC" prefix like SC3235, SC3338)
   - WiFi module (look for BCM, SYN, ATBM markings)
   - Flash chip (usually Winbond 25Q series)

#### Method 3: Try All Available Configurations
For Eufy C120 (T8400X), try these firmware variants in order:
1. `eufy_t8400x_t31x_sc3235_syn4343` (most common, works on many units)
2. `eufy_t8400x_t31x_sc3338_syn4343` (SC3338 sensor variant)
3. `eufy_t8400x_t31x_sc3335_syn4343` (SC3335 sensor variant)

Debugging Boot Failures
------------------------

### Serial Console Access (UART)

UART access is essential for diagnosing boot issues. You'll need:
- USB to TTL/UART adapter (3.3V)
- Jumper wires
- Soldering skills (optional, depending on camera)

#### UART Connection

1. **Locate UART pins** on the camera board (usually labeled TX, RX, GND)
2. **Connect your UART adapter:**
   - Camera TX → Adapter RX
   - Camera RX → Adapter TX
   - Camera GND → Adapter GND
   - **DO NOT** connect VCC/3.3V unless needed for power
3. **Use a terminal emulator:**
   ```bash
   # Linux/Mac
   screen /dev/ttyUSB0 115200
   # or
   minicom -D /dev/ttyUSB0 -b 115200
   
   # Windows: Use PuTTY or similar
   ```

#### What to Look For in Boot Logs

**U-Boot stage (bootloader):**
```
U-Boot 2022.04-g... (Build time: ...)
CPU: Ingenic T31X
Board: ...
DRAM: 128 MiB
```

**Kernel stage:**
```
[    0.000000] Linux version ...
[    0.000000] bootconsole [early0] enabled
[    0.000000] CPU: Ingenic T31X
```

**WiFi initialization:**
```
Loading WiFi driver...
Successfully loaded wlan0
```

**Portal startup:**
```
Starting Captive Portal
Portal started at ...
```

#### Common Boot Failure Patterns

**Bootloader fails to load kernel:**
- Symptom: U-Boot loads, but kernel never starts
- Cause: Wrong U-Boot configuration or corrupted kernel
- Solution: Reflash with correct firmware variant

**Kernel panics or crashes:**
- Symptom: Kernel starts but crashes with "Kernel panic"
- Cause: Wrong memory configuration (RMEM settings)
- Solution: Try firmware with different RMEM settings

**WiFi module fails to initialize:**
- Symptom: Boot completes but no wlan0 interface
- Cause: Wrong WiFi module driver
- Solution: Try firmware variant with different WiFi module

**Portal never starts:**
- Symptom: WiFi loads but no AP appears
- Cause: GPIO misconfiguration or WiFi driver issue
- Check: UART logs for "Portal started" message

Flashing Issues
---------------

### Intermittent Flashing Failures

Some cameras may have flashing issues due to:
- Poor USB cable quality (use cable with data lines)
- Weak power supply
- Timing issues with entering flash mode
- Hardware defects

#### Cloner Method Tips

1. **Use a quality USB cable** with data lines (not power-only)
2. **Try different USB ports** (prefer USB 2.0 ports)
3. **Ensure stable power:**
   - Some cameras need external 5V power during flashing
   - USB power alone may be insufficient
4. **Enter flash mode correctly:**
   - Short pins 5 and 6 on flash chip
   - Or use software method: `flash_erase /dev/mtd0; reboot -f`
5. **Multiple attempts may be needed** if hardware is marginal

#### SD Card Method

For cameras with SD card slots:
1. Format SD card as FAT32 with MBR partition table
2. Copy firmware as `autoupdate-full.bin` to card root
3. Insert card and power on camera
4. Wait for automatic flash (LED activity indicates progress)

#### Programmer Method (Most Reliable)

For stubborn cameras:
1. Use CH341A programmer with SOIC8 clip
2. Connect directly to flash chip
3. Use `snander` tool to flash firmware
4. See [camera-recovery.md](camera-recovery.md) for details

Recovery Procedures
-------------------

### If Camera Won't Boot After Flashing

1. **Don't panic** - Camera can usually be recovered
2. **Try SD card recovery** if bootloader is intact:
   - Prepare SD card with `autoupdate-full.bin`
   - Power on camera with card inserted
3. **Try different firmware variant:**
   - You may have wrong sensor/WiFi configuration
   - Try all available variants for your model
4. **Use programmer** as last resort:
   - Direct flash chip programming always works
   - Requires opening camera and using programmer

### Reverting to Original Firmware

If you saved your original firmware dump:
1. Use programmer method to flash original firmware
2. Or use Cloner tool with original firmware file
3. See [firmware.md](firmware.md) for dump procedures

Diagnostic Tools
----------------

### thingino-diag

If camera boots but has issues:
```bash
# Run diagnostics
thingino-diag

# Save to file
thingino-diag -l /tmp/diag.log

# Use SD card method (if no shell access)
# Create .diag file on SD card root, insert and boot camera
```

### Check System Logs

```bash
# System log
dmesg

# Kernel ring buffer
cat /proc/kmsg

# Check WiFi status
ip link show wlan0
iwconfig wlan0

# Check running services
ps aux | grep -E 'wpa|portal|httpd'
```

### Check Environment Variables

```bash
# Dump U-Boot environment
fw_printenv

# Check specific variables
fw_printenv wlan_module
fw_printenv gpio_wlan
```

GPIO Configuration Issues
-------------------------

Wrong GPIO configuration can prevent boot or cause peripheral failures.

### Check GPIO Settings

Look in firmware config's `.uenv.txt` file:
```
gpio_wlan=48O        # WiFi power GPIO
gpio_led_r=62O       # Red LED
gpio_led_b=61O       # Blue LED
gpio_button=58       # Reset button
gpio_speaker=63      # Speaker/buzzer
```

### Common GPIO Issues

- **No AP/WiFi:** Wrong `gpio_wlan` setting
- **No LED:** Wrong `gpio_led_*` settings
- **No audio:** Wrong `gpio_speaker` setting

Getting Help
------------

If you can't resolve the issue:

1. **Collect information:**
   - Camera model and FCC ID
   - Firmware variant tried
   - UART boot logs (if available)
   - Photos of camera internals (chip markings)

2. **Share diagnostics:**
   - Run `thingino-diag` if camera boots
   - Save UART logs to file
   - Take photos of error messages

3. **Report on community channels:**
   - [Discord](https://discord.gg/xDmqS944zr)
   - [Telegram](https://t.me/thingino)
   - [GitHub Issues](https://github.com/themactep/thingino-firmware/issues)

4. **Be patient:**
   - Hardware variations are common
   - Community members can help identify correct firmware
   - May need to test multiple configurations

Best Practices
--------------

### Before Flashing

1. **Backup original firmware** - See [firmware.md](firmware.md)
2. **Identify hardware** - Check sensor and WiFi module
3. **Choose correct firmware** - Match SoC, sensor, and WiFi module
4. **Test with one camera** - Don't flash all cameras at once

### During Flashing

1. **Use quality cables** - Data-capable USB cables
2. **Ensure stable power** - External power if USB is weak
3. **Don't interrupt** - Let process complete fully
4. **Keep notes** - Record what worked/didn't work

### After Flashing

1. **Wait patiently** - First boot may take 2-3 minutes
2. **Look for AP** - SSID starts with "THINGINO-"
3. **Check UART logs** - If available, monitor boot process
4. **Try recovery** - If no boot after 5 minutes

Additional Resources
--------------------

- [Camera Recovery Guide](camera-recovery.md)
- [Firmware Dumping Guide](firmware.md)
- [Diagnostics Guide](diagnostics.md)
- [Supported Hardware List](supported_hardware.md)
- [Project Website](https://thingino.com/)
- [Project Wiki](https://github.com/themactep/thingino-firmware/wiki)
