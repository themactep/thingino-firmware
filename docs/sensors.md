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
