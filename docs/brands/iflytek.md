IFLYTEK
---
http://tvoice.iflytek.com


| FCC | Model              | SOC      | CMOS   | RES | SPI    | ETH | WIFI       | SD | PAN | TILT | PWR    | Link                                                |
|-----|--------------------|----------|--------|-----|--------|-----|------------|----|-----|------|--------|-----------------------------------------------------|
|     | XFP301-M           | T31X     | JXQ03  | 3M  | 25Q128 |     | RTL8188FTV | +  | 360 | 136  | 5V USB | http://tvoice.iflytek.com/product/house/ptz-camera/ |
|     | XFP301-M           | T31X     | JXQ03  | 3M  | 25Q128 |     | SSV6155    | +  | 360 | 136  | 5V USB | http://tvoice.iflytek.com/product/house/ptz-camera/ |
|     | XFP300-M           | RTS3916E |        | 3M  | 25Q256 | +   | USB?       | +  | +   | +    | 5V USB | http://tvoice.iflytek.com/product/house/ptz-camera/ |


I saw 
```
if [ -f "/mnt/sd_card/flash.sh" ];then
/mnt/sd_card/flash.sh
fi
```
in boot.sh, maybe U can run custom scripts through sdcard.
