LINKINTEK
---
http://www.linkintec.cn/


| FCC | Model              | SOC      | CMOS      | RES | SPI    | ETH | WIFI       | SD | PAN | TILT | PWR    | Link                            |
|-----|--------------------|----------|-----------|-----|--------|-----|------------|----|-----|------|--------|---------------------------------|
|     | LYC20-note         | T31L     |           |     | 25Q128 | +   |            | +  |     |      | POE    |                                 |
|     | LYC21-note         | T31?     |           |     |        | +   |            | +  |     |      | POE    | http://linkintec.cn/?p=2663     |
|     | LYC40              | T31N     | JXF23     |     |        |     | RTL8188FU  | +  | +   | +    | 5V USB | http://linkintec.cn/?p=1453     |
|     | LYC60              | T31X     | MIS4001   |     | 25Q128 | +   |            | +  | +   | +    | POE    |                                 |
|     | LY-SM-YT40         | T40xp    | MIS4001*2 |     | 25N01  |     | ATBM6012BX | +  | +   | +    | 5V USB | http://www.linkintec.cn/?p=3370 |


I saw 
```
if (access("/mnt/factest.txt", 0) == 0 || sx.d(var_254) == 0)
	fprintf(stdout, "[DBG] [%s:%d] insert tmpfactory\n", "factory_main_init", 0xcf)
	sub_4794cc(1)
	char str1[0xa4]
	int32_t $v0_3
            
	if (access("/mnt/lyaging.sh", 0) == 0)
		sub_7168bc("cp /mnt/lyaging.sh /tmp/lyaging.sh; chmod +x /tmp/lyaging.sh;"
		"/tmp/lyaging.sh &")

```
in lyc60 ,but did't see this in lyc40 maybe U can run custom scripts through sdcard in some of them.
