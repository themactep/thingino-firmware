# Thingino FFmpeg Package

This package provides FFmpeg binaries specifically configured for Thingino devices with three focused use case configurations.

## Configuration Options

The package supports three main configuration variants:

### IPC (IP Camera) - `BR2_PACKAGE_THINGINO_FFMPEG_IPC`
**Minimal configuration optimized for IP camera use cases:**
- **Primary use**: RTSP streaming to MP4 recording
- **Video**: H.264 copy (no re-encoding, minimal CPU usage)
- **Audio**: OPUS to AAC conversion
- **Container**: MP4 output
- **Size**: Optimized for minimal binary size
- **Performance**: Fast, low resource usage

### NVR (Network Video Recorder) - `BR2_PACKAGE_THINGINO_FFMPEG_NVR`
**Extended configuration for advanced recording scenarios:**
- **Codecs**: H.264, H.265, AAC, OPUS support
- **Containers**: MP4, OPUS formats
- **Features**: More demuxers and protocols
- **Size**: Larger binary but more functionality
- **Use cases**: Multi-format recording, transcoding

### DEV (Development/Maximum Features) - `BR2_PACKAGE_THINGINO_FFMPEG_DEV`
**Development configuration with maximum features enabled:**
- **Codecs**: All available encoders and decoders
- **Containers**: All supported formats and protocols
- **Features**: All filters, hardware acceleration, debugging tools
- **Libraries**: Shared libraries enabled, additional tools (ffplay, ffprobe)
- **Size**: Largest binary with maximum functionality
- **Use cases**: Development, testing, maximum compatibility

## Usage Examples

### IPC Configuration (Default)
```
BR2_PACKAGE_THINGINO_FFMPEG=y
BR2_PACKAGE_THINGINO_FFMPEG_IPC=y
```

**Perfect for:**
```bash
# Record RTSP stream to MP4 (most common use case)
ffmpeg -i rtsp://camera/stream -c:v copy -c:a aac output.mp4
```

### NVR Configuration
```
BR2_PACKAGE_THINGINO_FFMPEG=y
BR2_PACKAGE_THINGINO_FFMPEG_NVR=y
```

**Supports additional scenarios:**
```bash
# Multiple codec support
ffmpeg -i input.mov -c:v copy -c:a aac output.mp4
ffmpeg -i rtsp://camera/stream -c:v copy -c:a opus output.opus
```

### DEV Configuration
```
BR2_PACKAGE_THINGINO_FFMPEG=y
BR2_PACKAGE_THINGINO_FFMPEG_DEV=y
```

**Supports maximum functionality:**
```bash
# All codecs and formats available
ffmpeg -i input.mkv -c:v libx264 -c:a aac output.mp4
ffmpeg -i rtsp://camera/stream -vf scale=1280:720 -c:v libx264 -c:a aac output.mp4

# Hardware acceleration (where supported)
ffmpeg -hwaccel auto -i input.mp4 -c:v copy output.mp4

# Advanced filtering and processing
ffmpeg -i input.mp4 -vf "scale=640:480,fps=30" -c:v libx264 -preset fast output.mp4

# Development tools
ffprobe -v quiet -print_format json -show_format -show_streams input.mp4
ffplay rtsp://camera/stream
```

## How It Works

The configuration system works by:

1. **Base Configuration**: All variants start with a minimal FFmpeg build with `--disable-everything`
2. **Conditional Enablement**: Based on selected codec options, the build system adds specific `--enable-parser`, `--enable-demuxer`, `--enable-muxer`, `--enable-encoder`, and `--enable-decoder` flags
3. **LightNVR Override**: When `BR2_PACKAGE_THINGINO_FFMPEG_LIGHTNVR` is enabled, additional features like shared libraries, extra encoders (png, mjpeg), and filters are enabled

## Build System Details

The makefile uses conditional logic to build appropriate FFmpeg configure options:

- **Parsers**: Enabled based on codec selections (h264, hevc, aac, opus)
- **Demuxers**: Enabled based on format selections (mov for MP4, m4a for AAC, etc.)
- **Muxers**: Enabled based on format selections (mp4, opus)
- **Encoders**: Enabled based on codec selections (h264, hevc, aac - all internal encoders)
- **Decoders**: Enabled based on codec selections (h264, hevc, aac, opus - all internal decoders)
- **Build Size**: Automatically disables `--enable-small` when H.264/H.265 encoding is selected (required for internal encoders)
- **Swresample**: Automatically enabled when OPUS is selected (required dependency)
- **Bitstream Filters**: Only enabled in lightnvr mode for format conversion
- **MIPS Optimizations**: Includes MIPS FPU and DSP R2 optimizations for Ingenic T31X performance

## Size Optimization

The granular configuration allows for significant size reduction by only including needed codecs:

- **Minimal**: Only enable codecs you actually use
- **Targeted**: Different configurations for different use cases
- **Efficient**: Avoid bloat from unused codec support

## Testing

Run the included test script to verify configuration:
```bash
python3 test_config.py
```

This tests various codec combinations and validates the makefile syntax.
