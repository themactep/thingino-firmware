# T31 Rotation Encoder Metadata Bug

## Symptoms

When `stream.rotation` is set to 90° or 270° in prudynt config, the IMP
frame source correctly rotates the output (e.g. 1024×768 crop becomes 768×1024
after 270° rotation). However, the H264 encoder SPS/PPS metadata and RTSP SDP
report the **pre-rotation** config dimensions (1024×768), not the actual
post-rotation frame size.

This causes FFprobe/VLC to report the wrong resolution. The visual output is
correct (portrait), but players that trust the SPS metadata render at the
wrong aspect ratio.

## Root Cause

The encoder's `initProfile()` in `IMPEncoder.cpp` swaps width/height for the
`chnAttr.encAttr.picWidth/picHeight` fields:

```cpp
if (stream->rotation != 0 && strcmp(stream->format, "JPEG") != 0) {
    std::swap(enc_width, enc_height);
}
chnAttr.encAttr.picWidth = enc_width;
chnAttr.encAttr.picHeight = enc_height;
```

However, `IMP_Encoder_SetDefaultParam()` is called **before** the swap with
the original `stream->width/stream->height`. SetDefaultParam computes internal
encoder state (buffer allocation, macroblock counts, etc.) from those original
dimensions. Swapping `picWidth/picHeight` afterwards doesn't fully propagate.

The patch `0002-rotation-encoder-dimensions.patch` attempts to fix this by
moving the swap before `SetDefaultParam`, computing `eff_width/eff_height`:

```cpp
int eff_width = stream->width;
int eff_height = stream->height;
if (stream->rotation != 0 && strcmp(stream->format, "JPEG") != 0) {
    std::swap(eff_width, eff_height);
}
// ... eff_width/eff_height used in SetDefaultParam and encAttr
```

## Hardware Limitation (T31)

Even with the patch correctly applied, the T31 H264 encoder hardware **clamps
the encoded resolution to square** when the post-rotation height exceeds the
width (portrait aspect). Testing shows the encoder always produces square
frames (e.g. 768×768) regardless of what `picWidth/picHeight` is set to.

This is a hardware constraint of the T31 Ingenic IMP encoder — it cannot
encode portrait (height > width) H264 frames. The T40/T41 may not have this
limitation.

## Working Resolution Constraints for 90°/270° Rotation on T31

| Constraint | Details |
|---|---|
| Both dimensions multiples of 64 | Pre-rotation width and height must be multiples of 64 |
| Max tested pre-rotation | 1024×768 |
| Post-rotation max | Recommended ≤ 1280×704 (warning only) |
| Higher resolutions | Crash (SIGSEGV) at 1088×768, 1024×1024 |
| Native portrait crop | 768×1024 crashes IMP frame source |

## Files Modified

- `package/prudynt-t/0002-rotation-encoder-dimensions.patch` — partial fix
  (swap before SetDefaultParam, remove stale `enc_height` overwrite)
- Works correctly on T40/T41 where the encoder supports portrait

## Patch Status

The patch is partially applied in the build system but needs the leftover
`chnAttr.encAttr.picHeight = enc_height;` line removed and the T31 hardware
limitation resolved before it can work end-to-end. See the discussion above.

## Workaround

For T31, use `hflip` + `vflip` (180° rotation) instead of 90°/270°.
180° doesn't swap width/height, so the encoder metadata always matches.
Alternatively, crop the sensor directly to the desired portrait aspect ratio
(but IMP on T31 may crash with portrait crop dimensions).
