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
