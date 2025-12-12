Streamer
========

Video Privacy FIFO
-------------------

Prudynt now exposes `/run/prudynt/video_ctrl` for coarse privacy control. Each
newline-delimited command toggles a full-frame OSD cover on one of the encoder
channels, forcing RTSP, MP4 recordings, and JPEG taps to see a solid black
stream while the ISP and exposure pipelines keep running.

```
printf 'PRIVACY ch=0 value=on\n' > /run/prudynt/video_ctrl
printf 'PRIVACY ch=0 value=off\n' > /run/prudynt/video_ctrl
```

- `ch=` selects the encoder. Omitting it (or using `ch=all`) toggles every encoder; set `ch=0`, `ch=1`, etc. to target a single stream.
- `value=`/`state=` accepts `on|off`, `true|false`, or `1|0`.
- Commands are idempotent; repeating the same state is a no-op.
- When the worker is not yet running the request is latched and applied as
	soon as the stream boots.

Internally the privacy state uses a hardware OSD cover layer, so frame cadence
and timestamps remain monotonic and decoders see legal access units (bitrates
typically collapse to a few hundred bits/s while muted).

### Privacy indicator overlay

Each encoder can expose an optional banner while privacy mode is active so the
black frame looks intentional. The feature is enabled per stream through the
`streamX.osd.privacy.*` keys inside `prudynt.json`:

```
"stream0": {
	"osd": {
		"privacy": {
			"enabled": true,
			"text": "PRIVACY ENABLED",
			"position": "0,-120",
			"font_size": 16384,
			"stroke_size": 2,
			"fill_color": "#FF4C4CFF",
			"stroke_color": "#000000FF",
			"rotation": 0,
			"layer": 16,
			"opacity": 255,
			"image_path": "",
			"image_width": 0,
			"image_height": 0
		}
	}
}
```

- Leave `image_path` empty (default) to render the configured `text` using the
	stream's OSD font. Auto font size (`16384`) scales with the stream width.
- Provide a BGRA asset (plus `image_width`/`image_height`) to swap the text for
	a static graphic.
- Positions use the same `x,y` syntax as the other OSD elements; `0` centers an
	axis, negative values offset from the far edge.
- `layer` and `opacity` control how the banner stacks over the black cover
	(layer 16, alpha 255 by default).

The indicator rides on top of the cover and toggles in lock-step with the
`PRIVACY` FIFO command, so viewers always see an explicit "privacy enabled"
marker instead of a plain black feed.

Each standard overlay (time, uptime, user text, brightness, logo) is now
grouped beneath `streamX.osd.<element>` with shared keys like `enabled`,
`format`, `position`, `rotation`, and the per-element font colors. Existing
flat keys continue to function, but saving the config emits the structured form
so it's easy to copy a whole block or keep overrides scoped to a single item.

Manual rate-control overrides
-----------------------------

Advanced encoders (T31/T40/T41/C100 families and legacy T2x/T30) accept custom
quantizer and bitrate limits via `prudynt.json`. Set the new keys under each
`streamX` block to gently steer IMP's RC logic without recompiling firmware:

```
"stream0": {
	"mode": "VBR",
	"qp_init": 30,
	"qp_min": 28,
	"qp_max": 45,
	"ip_delta": -2,
	"pb_delta": -1,
	"max_bitrate": 4200000
}
```

- `qp_init` seeds the first GOP; `qp_min`/`qp_max` clamp RC swing. Use `-1` to
	defer to the SDK defaults (same as leaving the key out).
- `ip_delta` and `pb_delta` bias P/B frames relative to I frames on platforms
	that expose IMP's delta knobs. Keep them between `-20..20`, or `-1` for the
	vendor default.
- `max_bitrate` caps the encoder in `VBR`, `CAPPED_VBR`, or `CAPPED_QUALITY`
	modes. Set `0` (default) to make IMP compute the ceiling from `bitrate`.

The overrides are optional; HAL simply skips any field that stays at the
default sentinel value. This makes it safe to stage changes on one stream at a
time or ship a universal config that works across SoC families.

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
