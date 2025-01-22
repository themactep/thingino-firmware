Streamer
========

OSD
---

### Creating a logo image

It's probably best to make the logo transparent, so the source image
should have an alpha channel. Then, the image should be in PNG format.

```
convert logo-100x30-alpha.png -depth 8 bgra:logo.bgra
```

### Viewing a logo image

You'll need to know the dimensions of the image to open the logo file.
You can view it using the `display` tool from `ImageMagick`.

```
display -depth 8 -size 100x30 logo.rgba
```
If you're not sure about the actual image dimensions, you can try
estimating them based on the file size using this formula:

`width * height = file size / 4`.

###
```
curl -v -X DESCRIBE rtsp://thingino:thingino@192.168.1.10:554/ch1
```

### Saving RTSP stream to file

```
ffmpeg -i rtsp://thingino:thingino@192.168.1.10:554/ch1 -map 0 -c copy -f mpegts record.ts
```

### Reading metadata from a saved RTSP stream

```
ffmpeg -i record.ts -map 0:2 -c copy -f data data.txt
```

### Checking the stream for latency

Low-latency RTSP mode is a feature of mpv that reduces latency by disabling
features that increase latency.

To configure `mpv` for low-latency RTSP mode, use with the following command:

```
mpv rtsp://thingino:thingino@192.168.1.10:554/ch0 --profile=low-latency --no-cache --cache-secs=0 --demuxer-readahead-secs=0 --cache-pause=no
```

Adding `--untimed` will disable synchronization to play the video feed as fast
as possible but could break audio, while `--no-correct-pts` will use fixed
timesteps and seems to break audio.

Resources
---------

- https://www.rfc-editor.org/rfc/rfc7826
