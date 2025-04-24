Wyze Video Doorbell (WVDB1)
===========================

Camera
------

- SoC: T31(Z)X (128MB)
- Image Sensor: SC4236 (4MP)
- Flash Chip: 16MB (25Q128)
- Wi-Fi Module: Realtek RTL8189 (SDIO)
- Power: 16-24V AC or 5V DC (microUSB)
- FCC ID: 2ANJHWVDB1

Chime (WDBC1)
-------------

- Power: 100-240V AC
- FCC ID: 2ANJHWDBC1


### Flashing Firmware

All you need to flash Thingino is a USB cable and an OTG adapter.

1. Download the latest firmware from the [Thingino website](https://thingino.com/).
2. Download the [Cloner Tool](https://thingino.com/cloner).
3. Extract the Cloner Tool on your computer, install included driver if you use Windows.
4. Run the Cloner Tool and configure it for the camera:
	- Platform: t31x
	- Board: t31x_sfc_nor_ddr2_writer_full.cfg
	- Switch to Policy tab, click on '...' button and select the downloaded firmware file.
	- Click "Save", "Yes", then 'Start' buttons.
5. Connect the camera to your computer with a USB-C cable and an OTG microUSB adapter.

After the Cloner indicator turns all green, disconnect the camera.

### Configuring the camera

Switch to a regular microUSB cable and let the camera boot up. Configure the
camera following the [Initial Configuration](../thingino/01-configuration.md)
guide.

### Pairing the Chime

Look at the back side of the Chime and write down its MAC address (XX:XX:XX:XX).

1. Plug in the Chime into an outlet and press and hold its button for 5 seconds
   to activate the pairing mode. You should see blue LED blinking fast.
2. On the camera, run the following command in the SSH terminal:
   ```
   doorbell_ctrl -p 00:11:22:33
   ```
   where `00:11:22:33` is the MAC address of the Chime. You should here a sound
   from the Chime and the LED should turn solid blue.

### Home Assistant Integration
