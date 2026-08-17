Image Sensor
============

Image sensor is one of the crucial components of any video camera.
It is an array of sensors that register light and transform it into a
form of electrical waves.

### Resources

- https://image-sensors-world.blogspot.com/
- https://www.gophotonics.com/search/cmos-image-sensors
- http://www.f4news.com/

### Simulate a sensor with ffmpeg

https://discord.com/channels/1086012062649565286/1209383244710027284/1230713521654993028

```
ffmpeg -i video.mp4 -c:v rawvideo -pix_fmt nv12 -f rawvideo /tmp/ffmpegpipe
```

### Valid sensor resolutions aligned by 64-pixel increments

**16:9 aspect ratio**

- 640×360 (nHD)
- 1024×576 (WSVGA)
- 1280×720 (HD / 720p)
- 1600×900 (HD+)
- 1920×1080 (Full HD / 1080p)
- 2560×1440 (QHD / 1440p)
- 3200×1800 (QHD+)
- 3840×2160 (4K UHD)
- 5120×2880 (5K)
- 7680×4320 (8K UHD)

**4:3 aspect ratio**

- 640×480
- 800×600
- 960×720
- 1024×768
- 1280×960
- 1440×1080
- 1600×1200
- 1920×1440
- 2048×1536
- 2880×2160 (4K 4:3)
