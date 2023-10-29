#!/bin/sh

cp /app/jz/etc/webrtc_profile.ini /tmp/

insmod /app/jz/modules/exfat.ko
insmod /app/jz/modules/audio.ko spk_gpio=-1

insmod /app/jz/modules/sinfo.ko
echo 1 > /proc/jz/sinfo/info

insmod /app/jz/modules/gv-gpio.ko

insmod /app/jz/modules/tx-isp-t21.ko
insmod /app/jz/modules/sensor_jxf37_t21.ko sensor_gpio_func=0
insmod /app/jz/modules/sensor_sc2300_t21.ko
insmod /app/jz/modules/sensor_sc2332_t21.ko sensor_gpio_func=0
insmod /app/jz/modules/sensor_sc1345_t21.ko
