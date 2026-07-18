H3C
---
https://www.h3c.com/


| FCC | Model              | SOC    | CMOS   | RES | SPI    | ETH | WIFI       | SD | PAN | TILT | PWR    | Link                                                                                                             |
|-----|--------------------|--------|--------|-----|--------|-----|------------|----|-----|------|--------|------------------------------------------------------------------------------------------------------------------|
|     | C2041              | T31X   | JXK04  | 4M  | 25Q128 | +   | RTL8188FTV | +  | 360 | 136  | 5V USB | https://www.h3c.com/cn/Products_And_Solution/IntelligentTerminalProducts/Star_Products/Home_Security/C2041/      |
|     | TC2100             | T31N   | JXQ03  | 3M  | 25Q128 | +   | SSV6155    | +  | 360 | 136  | 5V USB | https://www.h3c.com/cn/Products_And_Solution/IntelligentTerminalProducts/Star_Products/Home_Security/H3C_TC2100/ |
|     | TC2100(<=2021/09?) | SSC337 | SC3335 | 3M  | 25Q128 | +   | RTL8188FU  | +  | 360 | 136  | 5V USB | https://www.h3c.com/cn/Products_And_Solution/IntelligentTerminalProducts/Star_Products/Home_Security/H3C_TC2100/ |
|     | TC2101             | SSC337 | JXQ03  | 3M  | 25Q128 | +   | RTL8188FU  | +  | 360 | 136  | 5V USB |                                                                                                                  |
|     | TC3110             | SSC33? |        | 3M  |        | +   |            | +  |     |      | POE    | https://www.h3c.com/cn/Products_And_Solution/IntelligentTerminalProducts/Star_Products/Home_Security/H3C_C3110/  |
|     | TC3110(newer?)     | T31?   | JXQ03  | 3M  |        | +   |            | +  |     |      | POE    | https://www.h3c.com/cn/Products_And_Solution/IntelligentTerminalProducts/Star_Products/Home_Security/H3C_C3110/  |
|     | C3141              | T31?   |        | 4M  |        | +   |            | +  |     |      | POE    | https://www.h3c.com/cn/Products_And_Solution/IntelligentTerminalProducts/Star_Products/Home_Security/C3141/      |


You might have a goodluck if you
```
mkdir -p $YOUR_SD_CARD/update/fireware/h3c_product_type/
echo "busybox telnetd -l /bin/sh &" >> $YOUR_SD_CARD/update/fireware/update.sh
```
