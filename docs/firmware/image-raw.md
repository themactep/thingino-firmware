RAW Image
=========

Ingenic SDK Programming Guide suggests this method of dumping RAW data from sensor:

```
echo saveraw 1 > /proc/jz/isp/isp-w02 > /proc/jz/isp/isp-w02
```

The result is saved into `/tmp/snap0.raw` file in YUV420 format.

To convert the RAW image into a more convenient PNG format use the following conmmand:

```
ffmpeg -f rawvideo -pixel_format yuv420p -video_size 1920x1080 -i snap0.raw -vf fps=1 output.png
ffmpeg -f rawvideo -pixel_format nv12    -video_size 1920x1080 -i snap0.raw -vf fps=1 output.png
```

https://github.com/jdthomas/bayer2rgb

```
bayer2rgb --input snap0.raw --output=snap0.tiff --width=2560 --height=1440 --bpp=8 --first=RGGB --method=BILINEAR --tiff
```
