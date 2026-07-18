ZTE
---
https://www.zte.com.cn


| FCC | Model              | SOC      | CMOS   | RES | SPI    | ETH | WIFI       | SD | PAN | TILT | PWR    | Link                                                                                                 |
|-----|--------------------|----------|--------|-----|--------|-----|------------|----|-----|------|--------|------------------------------------------------------------------------------------------------------|
|     | K540               | T31X     | sc4336 | 4M  | 25Q128 | +   | atbm6032   | +  | +   | +    | 5V USB | https://www.zte.com.cn/china/product_index/secure_office_videoconferencing/set/camera/zxhn_k540.html |
|     | K540               | SSC337   |        |     | 25Q128 | +   | mt7601un   | +  | +   | +    | 5V USB | https://www.zte.com.cn/china/product_index/secure_office_videoconferencing/set/camera/zxhn_k540.html |
|     | K540v2             | T31X     | sc4336 | 4M  | 25Q128 | +   | atbm6032   | +  | +   | +    | 5V USB | https://www.zte.com.cn/china/product_index/secure_office_videoconferencing/set/camera/zxhn_k540.html |
|     | K543               | SSC337   |        |     |        | +   |            | +  | +   | +    | 5V USB |                                                                                                      |
|     | K545               | T31?     |        |     |        | +   |            | +  | +   | +    | 5V USB |                                                                                                      |



I saw 
```
if [ -f /mnt/sd/fact_test.conf ]
then
        nfac=`nvram get data fac`
        fac=${nfac#*=}
        MODE=`grep "MODE" /mnt/sd/fact_test.conf| awk -F= '{print $2}'`
        if [ $MODE == "factmode" ]
        then
                nvram set data fac 1
                nvram commit
        elif [ "$fac" == "1" ]
        then
                factory.sh
        fi
fi
```
in k540v2 usr/bin/facttool.sh, it Seem to enable telnet. But it has a password.
```
root:$5$lUKTaQA8Obnc0K5A$AmqD9pXrIi5m5KMBTl3N1iozYVgyJns98ghTK88E55B:10933:0:99999:7:::
```
also, in etc/init.d/hotplug.sh
```
detect_upgrade()
{
        if [ -e /mnt/sd/sd_upgrade.bin ]; then
                /usr/bin/upgrade_fw  /mnt/sd/sd_upgrade.bin > /dev/console 2>&1
        fi
}
```
