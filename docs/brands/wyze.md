Wyze
----
- https://www.wyze.com/

also [Hualai](hualai.md), [ATOM](atom.md)

Cloud:
- https://www.hualai.com/
- [TUTK/ThroughTek](https://www.tutk.com/)

### Models

| FCC            | Model                                 | SOC   | CMOS   | RES            | SPI    | WIFI       | Link                                   |
|----------------|---------------------------------------|-------|--------|----------------|--------|------------|----------------------------------------|
| 2ANJHNSCAMUS1  | Neos Smart Cam                        | T10?  |        |                |        | RTL8189FTV |                                        |
| 2ANJHWVOD1     | Wyze Cam Outdoor                      | T20X  |        |                |        | RTL8189FTV |                                        |
| 2ANJHWYZEC02   | Wyze Cam V2                           | T20   | JX-F22 | 1920x1080 @ 60 |        | RTL8189FTV |                                        |
| 2ANJHWYZEC02   | Wyze Cam V2                           | T20   | JX-F23 | 1920x1080 @ 30 |        | RTL8189FTV |                                        |
| 2ANJHWYZEC1    | Wyze Cam V1                           | SN97  |        |                |        | USB?       |                                        |
| 2ANJHWYZEC2    | Wyze Cam V2                           | T20?  |        |                |        |            |                                        |
| 2ANJHWYZECP1   | Wyze Cam Pan V1                       | T20X  |        |                |        | RTL8189FTV |                                        |
| 2AUIUWDB1A     |                                       |       |        |                |        |            |                                        |
| 2AUIUWVDB1     |                                       |       |        |                |        |            |                                        |
| 2AUIUWVDB1A    | Wyze DoorBell                         | T31ZX |        |                | 25Q128 | RTL8189FTV |                                        |
| 2AUIUWVDWDV2   |                                       |       |        |                |        |            |                                        |
| 2AUIUWVOD2     | Wyze Cam Outdoor V2                   | T20?  |        |                |        | RTL8189FTV |                                        |
| 2AUIUWWDPCA    |                                       |       |        |                |        |            |                                        |
| 2AUIUWWVDP     |                                       |       |        |                |        |            |                                        |
| 2AUIUWYZEC3    |                                       |       |        |                |        |            |                                        |
| 2AUIUWYZEC3A   | Wyze Cam V3                           | T31X  | GC2053 |                | 25Q128 | RTL8189FTV | https://www.wyze.com/products/wyze-cam |
| 2AUIUWYZEC3B   | Wyze Cam V3                           | T31ZX | GC2053 |                | 25Q128 | RTL8189FTV | https://www.wyze.com/products/wyze-cam |
| 2AUIUWYZEC3C   | Wyze Cam V3                           | T31ZX | GC2053 |                | 25Q128 | RTL8189FTV | https://www.wyze.com/products/wyze-cam |
| 2AUIUWYZEC3F   | Wyze Cam V3                           | T31A  | GC2053 |                | 25Q128 | ATBM6031   | https://www.wyze.com/products/wyze-cam |
| 2AUIUWYZEC3P   | Wyze Cam v3 Pro                       |       |        |                |        |            |                                        |
| 2AUIUWYZECFL2  |                                       |       |        |                |        |            |                                        |
| 2AUIUWYZECFLP  |                                       |       |        |                |        |            |                                        |
| 2AUIUWYZECGS   | Wyze Cam OG, Wyze Cam OG Telephoto 3x |       |        |                |        |            |                                        |
| 2AUIUWYZECOP   | Wyze Battery Cam Pro                  |       |        |                |        |            |                                        |
| 2AUIUWYZECP2   | Wyze Cam Pan v2                       |       |        |                |        |            |                                        |
| 2AUIUWYZECP2A  | Wyze Cam Pan v2                       | T20?  |        |                |        |            |                                        |
| 2AUIUWYZECPAN3 | Wyze Cam Pam V3                       | T31X  | GC2053 |                | 25Q128 | ATBM6031   | https://www.wyze.com/products/wyze-cam |

JX-F22 
JX-F23

### Modifications

| MODEL     | PCB VER                         | SoC      | Wi-Fi                |
|-----------|---------------------------------|----------|----------------------|
| WVOD2     | ISC5C1-MCUP01 V1.9 ISC5C B01    | T20X     | SDIO Realtek 8189FTV |
| WYZEC3    | WYZEV3_T31GC2053 V1.2_20200715  | T31X     | SDIO RTL8189FTV      |
| WYZEC3    | WYZEV3_T31GC2053 V2.02_20210523 | T31ZX    | SDIO ATBM6031        |
| WYZEC3    | WYZEV3_T31GC2053 V2.03_20211206 | T31X     | SDIO ATBM6031        |
| WYZEC3    | WYZEV3_T31GC2053 V2.02_20210523 | T31ZX    | SDIO RTL8189FTV      |
| WYZEC3    | WYZEV3_T31GC2053 V2.03_20211206 | T31X     | SDIO RTL8189FTV      |
| WYZEC3    | WYZEV3_T31GC2053 V1.4_20201010  | T31ZX    | SDIO RTL8189FTV      |
| WYZEC3    | WYZEV3_T31GC2053 V1.4_20201010  | T31ZX    | SDIO RTL8189FTV      |
| WYZEC3    | WYZEV3_T31GC2053 V1.4_20201010  | T31X     | SDIO RTL8189FTV      |
| WYZEC3    | WYZEV3_T31AGC2053 V3.2_20210714 | T31A BGA | SDIO ATBM6031        |
| WYZECPAN3 | WYZE PAN V3 MB V1.3             | T31X     | SDIO ATBM6031        |
| WVDB1A    | WYZEDB_T31_V3                   | T31ZX    | SDIO RTL8189FTV      |

#### Resources

- Communities
    - [Wyze forum](https://forums.wyze.com/)
    - [WyzeCam subreddit](https://www.reddit.com/r/wyzecam/)
- Research
    - [Wyze API RE](https://github.com/nblavoie/wyzecam-api)
    - [Wyze streaming library](https://github.com/kroo/wyzecam)
    - [Wyze Node API](https://github.com/noelportugal/wyze-node)
    - [Python Wyze SDK](https://github.com/shauntarves/wyze-sdk)
    - [WyzeUpdater](https://github.com/HclX/WyzeUpdater)
    - [WyzeHacks](https://github.com/HclX/WyzeHacks)
- Utilities
    - [Wyze Bridge](https://github.com/mrlt8/docker-wyze-bridge)
    - [HomeAssistant Integration](https://github.com/SecKatie/ha-wyzeapi)
    - [Homebridge Integration](https://github.com/misenhower/homebridge-wyze-connected-home)

http://mobilemodding.info/wyze-cam-v2/
http://mobilemodding.info/wyze-cam-pan-v3-teardown/

#### Password hashes

```
root:$6$wyzecampanv3$XYNa9HBlTpHg878e3GAckLngvkbs1ndm6YXlTqfxjchAvh2zpzyjtbg4BSvd2cM/dgGx7.FwQEcCbxAg9ODGf1:0:0:99999:7:::
root:$6$1RvTcQLM$1K7XwU1HABg1rQQyB99kdHceeqiEsnGfWN3FecCgmc7vnpAL8wxdAzsbLVbLSCXsBRuwVVSnWnVqKDu2a.rw7/:17942:0:99999:7:::
```
