# SEI — Supplemental Enhancement Information

A reference for the H.264 (AVC) and H.265 (HEVC) SEI payload types used
in Thingino firmware and encountered in the wild.

## What is SEI?

SEI messages are NAL units embedded in the video bitstream that carry
auxiliary data — timing, HDR color volume, frame packing for 3D, user
defined metadata, and more.  Decoders are not required to act on them;
the spec allows silent discard.

| Codec | SEI NAL unit type |
|-------|-------------------|
| H.264 | 6 |
| H.265 | 39 (PREFIX_SEI) / 40 (SUFFIX_SEI) |

## Sources of truth

| Resource | Link |
|----------|------|
| ITU-T H.264 (free PDF, Annex D = SEI) | <https://www.itu.int/rec/T-REC-H.264> |
| ITU-T H.265 (free PDF, Annex D = SEI) | <https://www.itu.int/rec/T-REC-H.265> |
| FFmpeg `h264_sei.c` (readable mapping) | <https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/h264_sei.c> |
| FFmpeg `hevc_sei.c` | <https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/hevc_sei.c> |
| Wikipedia overview | <https://en.wikipedia.org/wiki/Supplemental_enhancement_information> |
| Registered UUIDs (type-4 user data) | <https://www.itu.int/en/ITU-T/studygroups/2017-2020/16/Pages/video/uuid.aspx> |

## H.264 notable SEI payload types

| Type | Name | Used for |
|------|------|----------|
| 0 | Buffering period | HRD / VBV buffer model |
| 1 | Pic timing | PTS, DTS, clock drift on raw streams |
| 2 | Pan-scan rect | Crop region for display |
| 3 | Filler payload | Byte alignment padding |
| 4 | User data **registered** | ISO-recognized UUID (ATSC, DVB, SMPTE) |
| 5 | User data **unregistered** | Arbitrary UUID — **used by Thingino** |
| 6 | Recovery point | Random-access hints (IDR distance, exact match flag) |
| 9 | Scene info | Scene-cut flag, scene identifier |
| 19 | Film grain characteristics | Modelling params for decoder-side grain synthesis |
| 22 | Post-filter hint | Suggested deblocking/deringing |
| 23 | Tone mapping information | HDR-to-SDR tone mapping curves |
| 45 | Frame packing arrangement | 3D / stereo layout (side-by-side, top-bottom, etc.) |
| 47 | Display orientation | EXIF-like rotation (0/90/180/270) and flip |
| 56 | Green metadata | Energy-efficient encoding hints (ETSI) |
| 128 | Structure of pictures info | Decoding-order metadata (H.241) |
| 129 | Active parameter sets | Which SPS/PPS are in play (H.241) |
| 137 | Mastering display color volume | HDR: SMPTE ST 2086 primaries + luminance |
| 144 | Content light level information | HDR: MaxFALL, MaxCLL |
| 147 | Alternative transfer characteristics | Preferred EOTF when multiple available |

## H.265 notable SEI payload types

Many types mirror H.264 (some with different numbers).  Commonly seen:

| Type | Name | Notes |
|------|------|-------|
| 0 | Buffering period | |
| 1 | Pic timing | |
| 4 | User data registered (ITU-T T.35) | Country-code + payload |
| 5 | User data unregistered | UUID-based, same model as H.264 |
| 6 | Recovery point | |
| 9 | Scene information | |
| 19 | Film grain characteristics | |
| 23 | Tone mapping information | |
| 45 | Frame packing arrangement | |
| 47 | Display orientation | |
| 132 | Decoded picture hash | Checksums for error/authenticity checks |
| 137 | Mastering display color volume | |
| 144 | Content light level info | |
| 147 | Alternative transfer characteristics | |

## SEI on the wire

### Annex B (start-code delimited)

```
00 00 00 01  [  NAL header  ]  [ … SEI payload … ]  [ 80 ]  — trailing bits
            └── 06 (H.264) or 27 / 28 (H.265, hex 0x27/0x28)
```

The SEI payload consists of one or more **SEI messages**. Each message:

```
[ payload_type (varint) ]  [ payload_size (varint) ]  [ payload bytes ]
```

A type-5 (user data unregistered) message adds a 16-byte UUID before the
user data:

```
05  [size-varint]  [UUID 16 bytes]  [user-data bytes]
```

### avcC / hvcC (MP4 / Matroska)

Length-prefixed NAL units instead of start codes.  The SEI NAL itself is
unchanged; only the framing differs.

## Inspecting SEI with FFmpeg

```bash
# List every NAL unit type in a stream
ffmpeg -v trace -i INPUT -c:v copy -f null /dev/null 2>&1 | grep nal_unit_type

# Dump raw annex B H.264 and scan for SEI type 6
ffmpeg -i INPUT -c:v copy -bsf:v h264_mp4toannexb -f h264 - | \
  grep -obUaP '\x00\x00\x00\x01\x06'  # or \x00\x00\x01\x06

# Show SEI side data decoded by libavcodec (HDR, display orientation, etc.)
ffprobe -v error -show_entries frame=side_data_list INPUT
```

## Thingino SEI

Thingino embeds OSD overlay metadata in H.264 SEI type 5 (user data
unregistered) with UUID `a1b2c3d4-e5f6-4780-abcd-ef1234567890`.

See [`osd-sei-metadata-plan.md`](osd-sei-metadata-plan.md) for the JSON
schema, HTTP API, and web UI rendering details.
