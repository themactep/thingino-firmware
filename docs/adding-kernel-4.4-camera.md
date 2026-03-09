# Adding a New Camera with Kernel 4.4

This guide explains how to add support for a new camera using the Linux 4.4 kernel in the Thingino firmware project.

## Prerequisites

- Basic understanding of Device Tree (DTS) format
- Camera hardware specifications (SOC, sensor, WiFi module)
- GPIO pin mappings for the camera
- Linux kernel configuration knowledge

## Overview

Kernel 4.4 uses Device Tree (DTS) for hardware configuration instead of Kconfig options. This is a more modern and flexible approach compared to the kernel 3.10 used in older cameras.

## Step 1: Verify SOC Support

First, check if your SOC is already supported in kernel 4.4.

### Check Existing SOC Support

```bash
# List supported SOCs in kernel 4.4
ls board/ingenic/xburst*/kernel/4.4/*.generic.config

# Check if your SOC has a Kconfig entry
grep "config SOC_" overrides/ingenic-linux-4.4.94/arch/mips/xburst/Kconfig
```

### If Your SOC is NOT Supported

You'll need to add SOC support first. This involves:

1. **Add SOC to Kconfig** (`overrides/ingenic-linux-4.4.94/arch/mips/xburst/Kconfig`):

```kconfig
config SOC_TXXX
	bool "txxx"
	select IRQ_INGENIC_CPU
	select CLK_TXXX
	select INGENIC_INTC
	select PINCTRL
	select PINCTRL_INGENIC
	select CLKSRC_OF
	select CLKDEV_LOOKUP
	select CLKSRC_INGENIC_SYS_OST
	# Add select XBURST_MXUV2 only if SOC supports MXU v2
```

2. **Add to Makefile** (`overrides/ingenic-linux-4.4.94/arch/mips/xburst/Makefile`):

```makefile
obj-$(CONFIG_SOC_TXXX) += soc-txxx/
```

3. **Add to Platform** (`overrides/ingenic-linux-4.4.94/arch/mips/xburst/Platform`):

```makefile
cflags-$(CONFIG_SOC_TXXX)	+= -I$(srctree)/arch/mips/xburst/soc-txxx/include
```

4. **Copy SOC directory from SDK**:

```bash
# Copy the entire soc-txxx directory from your SOC's SDK kernel
cp -r /path/to/sdk/arch/mips/xburst/soc-txxx overrides/ingenic-linux-4.4.94/arch/mips/xburst/
```

5. **Add CLK_TXXX support** (`drivers/clk/ingenic/Kconfig`):

```kconfig
config CLK_TXXX
	bool
	depends on SOC_TXXX
	select COMMON_CLK_INGENIC
	help
	  build the ingenic txxx soc clock driver.
```

6. **Add clock driver** (`drivers/clk/ingenic/Makefile`):

```makefile
obj-$(CONFIG_SOC_TXXX)	+= clk-txxx.o
```

7. **Copy clock driver and bindings**:

```bash
# Copy clock driver
cp /path/to/sdk/drivers/clk/ingenic/clk-txxx.c overrides/ingenic-linux-4.4.94/drivers/clk/ingenic/

# Copy clock bindings header
cp /path/to/sdk/include/dt-bindings/clock/ingenic-txxx.h overrides/ingenic-linux-4.4.94/include/dt-bindings/clock/
```

8. **Add device tree Kconfig directory** (`overrides/ingenic-linux-4.4.94/arch/mips/xburst/Kconfig`):

In both device tree choice sections, add:

```kconfig
if SOC_TXXX
source "arch/mips/xburst/soc-txxx/Kconfig.DT"
endif
```

9. **Create generic kernel config**:

```bash
# Copy from SDK or similar SOC
cp board/ingenic/xburst1/kernel/4.4/similar_soc.generic.config \
   board/ingenic/xburst1/kernel/4.4/txxx.generic.config

# Edit to set CONFIG_SOC_TXXX=y and remove other SOC configs
```

10. **Copy device tree files**:

```bash
# Copy base dtsi files from SDK
cp /path/to/sdk/arch/mips/boot/dts/ingenic/txxx*.dtsi \
   overrides/ingenic-linux-4.4.94/arch/mips/boot/dts/ingenic/
```

## Step 2: Create Camera-Specific Files

### 2.1 Create Camera Configuration Directory

```bash
# Create directory for your camera
mkdir -p configs/cameras/brand_model_soc_sensor_wifi
cd configs/cameras/brand_model_soc_sensor_wifi
```

### 2.2 Create Defconfig File

Create `brand_model_soc_sensor_wifi_defconfig`:

```bash
# NAME: Brand Model (SOC, Sensor, WiFi)
# FRAG: soc-xburst1 toolchain ccache brand rootfs kernel system target uboot ssl

# ISP Clock settings (adjust for your SOC)
BR2_ISP_CLK_200MHZ=y
BR2_ISP_CLK_SCLKA=y
BR2_ISP_CLKA_600MHZ=y
BR2_ISP_CLKA_SCLKA=y

# Device Tree selection (camera-specific)
BR2_LINUX_KERNEL_EXT_INGENIC_KOPT="CONFIG_DT_BRAND_MODEL_SOC_SENSOR_WIFI=y"

# MMC/SD Card support
BR2_PACKAGE_THINGINO_KOPT_MMC0=y
BR2_PACKAGE_THINGINO_KOPT_MMC0_PB_4BIT=y

# WiFi module
BR2_PACKAGE_WIFI=y
BR2_PACKAGE_WIFI_ATBM6012BX=y  # or your WiFi module

# Image sensor
BR2_SENSOR_1_NAME=sc2336  # your sensor

# SOC selection
BR2_SOC_INGENIC_T23N=y  # your SOC

# Hardware features
BR2_THINGINO_AUDIO=y
BR2_THINGINO_BUTTON=y
BR2_THINGINO_MOTORS=y  # if camera has motors
BR2_THINGINO_SDCARD=y

# Memory settings
BR2_THINGINO_RMEM_MB=22  # adjust for your camera

# Flash size
FLASH_SIZE_MB=8  # or 16

# Kernel version
KERNEL_VERSION_4=y
```

**Important Notes:**
- DO NOT add `BR2_THINGINO_AUDIO_GPIO` or similar GPIO configs - these go in the device tree!
- The `BR2_LINUX_KERNEL_EXT_INGENIC_KOPT` line enables your camera-specific device tree
- Keep camera-specific settings here, generic SOC settings go in the generic config

### 2.3 Create U-Boot Environment File

Create `brand_model_soc_sensor_wifi.uenv.txt`:

```bash
# Add any camera-specific U-Boot environment variables
# Usually this can be empty or minimal
```

## Step 3: Create Device Tree File

### 3.1 Add Device Tree Kconfig Entry

Edit `overrides/ingenic-linux-4.4.94/arch/mips/xburst/soc-txxx/Kconfig.DT`:

```kconfig
config DT_BRAND_MODEL_SOC_SENSOR_WIFI
	bool "Brand Model SOC Sensor WiFi"
```

### 3.2 Create DTS File

Create `overrides/ingenic-linux-4.4.94/arch/mips/boot/dts/ingenic/brand_model_soc_sensor_wifi.dts`:

```dts
/dts-v1/;

#include <dt-bindings/input/input.h>
#include <dt-bindings/interrupt-controller/irq.h>
#include "txxx.dtsi"
#include "txxx-pinctrl.dtsi"

/ {
	compatible = "brand,model-soc", "ingenic,txxx";
	model = "Brand Model SOC Sensor WiFi";

	memory {
		device_type = "memory";
		reg = <0x00000000 0x04000000>;  /* Adjust for your RAM size */
	};

	aliases {
		serial0 = &uart0;
		serial1 = &uart1;
	};

	chosen {
		stdout-path = "serial1:115200n8";
	};

	/* GPIO-controlled LEDs */
	gpio-leds {
		compatible = "gpio-leds";
		
		ircut1 {
			label = "ircut1";
			gpios = <&gpb 25 GPIO_ACTIVE_HIGH>;  /* Your GPIO */
			default-state = "off";
		};
		
		ircut2 {
			label = "ircut2";
			gpios = <&gpb 26 GPIO_ACTIVE_HIGH>;  /* Your GPIO */
			default-state = "off";
		};
		
		ir940 {
			label = "ir940";
			gpios = <&gpb 13 GPIO_ACTIVE_HIGH>;  /* Your GPIO */
			default-state = "off";
		};
		
		led_blue {
			label = "led:blue";
			gpios = <&gpb 8 GPIO_ACTIVE_LOW>;  /* Your GPIO */
			default-state = "off";
		};
		
		led_red {
			label = "led:red";
			gpios = <&gpb 14 GPIO_ACTIVE_LOW>;  /* Your GPIO */
			default-state = "off";
		};
	};

	/* GPIO buttons */
	gpio_keys {
		compatible = "gpio-keys";
		autorepeat;
		
		reset {
			label = "reset";
			linux,code = <KEY_RESTART>;
			gpios = <&gpb 6 GPIO_ACTIVE_LOW>;  /* Your GPIO */
		};
	};

	/* WiFi power sequence */
	wlan_pwrseq: wlan-pwrseq {
		compatible = "mmc-pwrseq-simple";
		reset-gpios = <&gpb 15 GPIO_ACTIVE_LOW>;  /* Your GPIO */
	};

	/* Audio amplifier */
	audio-amplifier {
		compatible = "simple-audio-amplifier";
		enable-gpios = <&gpb 7 GPIO_ACTIVE_LOW>;  /* Your GPIO */
	};

	/* Pan/Tilt motors (if camera has motors) */
	motor_pan: motor-pan {
		compatible = "gpio-stepper";
		gpios = <&gpb 17 GPIO_ACTIVE_HIGH>,  /* Your GPIOs */
			<&gpb 31 GPIO_ACTIVE_HIGH>,
			<&gpb 30 GPIO_ACTIVE_HIGH>,
			<&gpb 29 GPIO_ACTIVE_HIGH>;
		max-speed = <900>;
		steps = <3700>;
	};

	motor_tilt: motor-tilt {
		compatible = "gpio-stepper";
		gpios = <&gpb 20 GPIO_ACTIVE_HIGH>,  /* Your GPIOs */
			<&gpb 21 GPIO_ACTIVE_HIGH>,
			<&gpc 0 GPIO_ACTIVE_HIGH>,
			<&gpb 27 GPIO_ACTIVE_HIGH>;
		max-speed = <900>;
		steps = <1000>;
	};
};

/* UART configuration */
&uart0 {
	status = "okay";
	pinctrl-names = "default";
	pinctrl-0 = <&uart0_pb>;  /* Check your SOC's pinctrl options */
};

&uart1 {
	status = "okay";
	pinctrl-names = "default";
	pinctrl-0 = <&uart1_pb>;  /* Check your SOC's pinctrl options */
};

/* MMC/SD card */
&msc0 {
	status = "okay";
	pinctrl-names = "default";
	pinctrl-0 = <&msc0_pb>;  /* Check your SOC's pinctrl options */
	cap-sd-highspeed;
	cap-mmc-highspeed;
	max-frequency = <50000000>;
	bus-width = <4>;
	voltage-ranges = <1800 3300>;
	non-removable;
	mmc-pwrseq = <&wlan_pwrseq>;
	vmmc-supply = <&wlan_pwrseq>;
	cd-gpios = <&gpb 18 GPIO_ACTIVE_LOW>;  /* Your GPIO for card detect */
};

/* I2C and Image Sensor */
&i2c0 {
	status = "okay";
	clock-frequency = <400000>;
	pinctrl-names = "default";
	pinctrl-0 = <&i2c0_pb>;  /* Check your SOC's pinctrl options */

	sensor: sensor@30 {
		compatible = "smartsens,sc2336";  /* Your sensor */
		reg = <0x30>;  /* I2C address */
		
		reset-gpios = <&gpa 18 GPIO_ACTIVE_HIGH>;  /* Your GPIO */
		pwdn-gpios = <&gpa 19 GPIO_ACTIVE_HIGH>;   /* Your GPIO */
		
		port {
			sensor_0: endpoint {
				bus-width = <10>;  /* 8 or 10 bit */
			};
		};
	};
};

/* USB OTG */
&otg {
	status = "okay";
};

&otg_phy {
	dr_mode = "peripheral";
	status = "okay";
};
```

### 3.3 Add DTS to Makefile

Edit `overrides/ingenic-linux-4.4.94/arch/mips/boot/dts/ingenic/Makefile`:

```makefile
dtb-$(CONFIG_DT_BRAND_MODEL_SOC_SENSOR_WIFI)	+= brand_model_soc_sensor_wifi.dtb
```

## Step 4: GPIO Pin Mapping

### Finding GPIO Numbers

GPIOs are organized by banks (A, B, C, etc.) with 32 pins each:
- Bank A (gpa): GPIO 0-31
- Bank B (gpb): GPIO 32-63
- Bank C (gpc): GPIO 64-95
- Bank D (gpd): GPIO 96-127

**Formula:** GPIO_NUMBER = (BANK × 32) + PIN

Examples:
- GPIO 38 = Bank B, Pin 6 → `<&gpb 6>`
- GPIO 57 = Bank B, Pin 25 → `<&gpb 25>`
- GPIO 64 = Bank C, Pin 0 → `<&gpc 0>`

### GPIO Active Level

- `GPIO_ACTIVE_HIGH`: GPIO is active when HIGH (1)
- `GPIO_ACTIVE_LOW`: GPIO is active when LOW (0)

Check your hardware schematics to determine the correct active level.

### Common GPIO Mappings

Typical camera GPIOs to configure:

```
IR-CUT solenoids: 2 GPIOs (for day/night filter switching)
IR LEDs (940nm): 1 GPIO (infrared illumination)
Status LEDs: 1-2 GPIOs (blue/red indicator lights)
Reset button: 1 GPIO (hardware reset button)
WiFi enable: 1 GPIO (power/reset for WiFi module)
Audio amplifier: 1 GPIO (enable/mute speaker)
Sensor reset: 1 GPIO (image sensor reset)
Sensor power-down: 1 GPIO (image sensor power control)
MMC card detect: 1 GPIO (SD card present detection)
Motors: 4 GPIOs per motor (pan/tilt stepper motors)
```

## Step 5: Verify Pinctrl Options

Check your SOC's pinctrl file to find available pin configurations:

```bash
# View available pinctrl options
grep -E "uart|msc|i2c" overrides/ingenic-linux-4.4.94/arch/mips/boot/dts/ingenic/txxx-pinctrl.dtsi
```

Common pinctrl names:
- UART: `uart0_pb`, `uart1_pa`, `uart2_pc`
- MMC: `msc0_pb`, `msc0_pb_4bit`, `msc1_pa`
- I2C: `i2c0_pb`, `i2c1_pc`

Use the correct pinctrl names in your DTS file.

## Step 6: Build and Test

### 6.1 Clean Build

```bash
CAMERA=brand_model_soc_sensor_wifi make distclean rebuild-linux
```

### 6.2 Check for Errors

Common errors and solutions:

**Error: `Label or path xxx not found`**
- Solution: Check that you're using the correct node names from your SOC's dtsi file

**Error: `CONFIG_DT_XXX not defined`**
- Solution: Verify the Kconfig.DT entry and defconfig BR2_LINUX_KERNEL_EXT_INGENIC_KOPT line

**Error: `undefined reference to get_current_cp2`**
- Solution: Already fixed in prom.c with stub function

**Error: `implicit declaration of function DIV_SPECIAL`**
- Solution: Already added to clk.h

**Error: `pinctrl reference not found`**
- Solution: Check txxx-pinctrl.dtsi for available options

### 6.3 Verify Build Output

```bash
# Check if kernel was built
ls -lh output-stable/brand_model_soc_sensor_wifi/images/uImage

# Check device tree blob
ls -lh output-stable/brand_model_soc_sensor_wifi/build/linux-custom/arch/mips/boot/dts/ingenic/*.dtb
```

## Step 7: Testing on Hardware

1. Flash the firmware to the camera
2. Boot and check kernel log:
   ```bash
   dmesg | grep -i "device tree\|gpio\|sensor"
   ```
3. Verify GPIO exports:
   ```bash
   ls /sys/class/gpio/
   ls /sys/class/leds/
   ```
4. Test hardware features:
   - LEDs, IR-cut, buttons, WiFi, sensor, motors

## Common Issues and Solutions

### Issue: Wrong GPIO Bank

**Symptom:** Hardware doesn't respond
**Solution:** Double-check GPIO number calculation and bank assignment

### Issue: Incorrect Active Level

**Symptom:** Hardware works inverted (LED off when should be on)
**Solution:** Switch between GPIO_ACTIVE_HIGH and GPIO_ACTIVE_LOW

### Issue: I2C Sensor Not Detected

**Symptom:** `i2cdetect` doesn't show sensor
**Solution:** 
- Verify I2C address (usually 0x30 or 0x3c)
- Check I2C pinctrl configuration
- Verify sensor power and reset GPIOs

### Issue: Kernel Doesn't Boot

**Symptom:** No serial output after U-Boot
**Solution:**
- Check memory size in DTS matches actual RAM
- Verify UART pinctrl is correct
- Check stdout-path in chosen node

## Tips and Best Practices

1. **Start Simple**: Begin with minimal DTS (just UART and memory), then add features incrementally
2. **Compare with Similar Cameras**: Look at DTS files from cameras with the same SOC
3. **Document GPIO Mappings**: Keep a separate document with your GPIO mappings
4. **Test Each Feature**: Add and test one hardware feature at a time
5. **Use Descriptive Labels**: Name GPIOs clearly (ircut1, led_blue, etc.)
6. **Version Control**: Commit working configurations before making changes
7. **Check SOC Documentation**: Refer to Ingenic SOC datasheets for GPIO capabilities

## Reference Files

Key files to understand:
- `overrides/ingenic-linux-4.4.94/arch/mips/boot/dts/ingenic/cinnado_d1_t23n_sc2336_atbm6012bx.dts` - Complete example
- `overrides/ingenic-linux-4.4.94/arch/mips/xburst/Kconfig` - SOC configuration
- `board/ingenic/xburst1/kernel/4.4/t23.generic.config` - Generic kernel config
- Device tree bindings documentation in kernel source

## Additional Resources

- [Device Tree Specification](https://www.devicetree.org/)
- [Linux GPIO Subsystem Documentation](https://www.kernel.org/doc/html/latest/driver-api/gpio/)
- Ingenic SOC datasheets (contact manufacturer)
- Thingino project wiki and forums

## Conclusion

Adding kernel 4.4 camera support requires:
1. SOC support in kernel (if not already present)
2. Camera-specific defconfig with device tree selection
3. Complete device tree file with all GPIO mappings
4. Proper pinctrl configuration for peripherals

The device tree approach is more maintainable than Kconfig and allows better hardware description. Take time to get GPIO mappings correct - this is the most critical step.
