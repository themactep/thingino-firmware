WUUK Y0510
==========

- SoC: T31X (128MB RAM)
- Image Sensor:
  - SC4336P (4MP)
  - SC401Ai (4MP)
- Wi-Fi Module: SSV6158 (SDIO)
- Power: 5V DC (USB-C port)

Flashing
--------

### SD Card method

1. Download the latest firmware from the [Thingino website](https://thingino.com/).
2. Prepare an SD card (FAT32, MBR) and copy the firmware to the root directory as `v4_all.bin`.
3. Insert the SD card into the camera and power it on.
4. The camera will automatically flash the firmware and reboot.

### Cloner method

1. Download the latest firmware from the [Thingino website](https://thingino.com/).
2. Download the [Cloner Tool](https://thingino.com/cloner).
3. Extract the Cloner Tool on your computer, install included driver if you use Windows.
4. Run the Cloner Tool and configure it for the camera:
   - Platform: t31x
   - Board: t31x_sfc_nor_ddr2_writer_full.cfg
   - Switch to Policy tab, click on '...' button and select the downloaded firmware file.
   - Click "Save", "Yes", then 'Start' buttons.
5. Connect the camera to your computer via USB with a cable that has data lines in it.
