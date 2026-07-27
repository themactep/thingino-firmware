# Thingino MediaPlayer Plugin for ESPHome

This plugin implements the ESPHome MediaPlayer interface for Thingino cameras, enabling audio playback through Home Assistant using the Ingenic Audio Daemon (IAD).

## Features

- **Home Assistant Integration** - Full ESPHome MediaPlayer entity support
- **URL-based Playback** - Stream audio from HTTP/HTTPS URLs
- **Announcement Support** - Special handling for TTS and announcements
- **Volume Control** - System volume management
- **Ingenic Audio Daemon** - Uses IAD for hardware-accelerated audio output
- **Streaming Playback** - Direct streaming from URL to IAD (no buffering)

## Architecture

```
┌──────────────────────────────┐
│     Home Assistant           │
│  (ESPHome Integration)       │
└──────────────┬───────────────┘
               │ MediaPlayerCommandRequest
               │
┌──────────────▼───────────────┐
│  ESPHome Linux Service       │
│  ┌─────────────────────────┐ │
│  │ Plugin Manager          │ │
│  │  routes message to:     │ │
│  │  ↓                      │ │
│  │ ┌─────────────────────┐│ │
│  │ │ Thingino MediaPlayer││ │
│  │ │ Plugin              ││ │
│  │ │ - Parse command     ││ │
│  │ │ - Download audio    ││ │
│  │ │ - Stream to IAD     ││ │
│  │ └─────────────────────┘│ │
│  └─────────────────────────┘ │
└──────────────┬───────────────┘
               │ Unix Socket
               │
┌──────────────▼───────────────┐
│  Ingenic Audio Daemon (IAD)  │
│  - Audio output processing   │
│  - Hardware interfacing      │
│  - PCM playback              │
└──────────────┬───────────────┘
               │
┌──────────────▼───────────────┐
│  Ingenic IMP Audio Hardware  │
│  - Speaker output            │
└──────────────────────────────┘
```

## Dependencies

### Runtime Dependencies
- **ingenic-audiodaemon** - Audio daemon must be running
- **libcurl** - For streaming audio from URLs
- **ALSA** - For volume control (amixer)
- **pthread** - For threaded playback

### Build Dependencies
- **libcurl-dev** - CURL development headers
- **pthread** - POSIX threads (usually built-in)

## Installation

### 1. Enable Required Packages

Add to your camera defconfig (`configs/cameras/<camera>/<camera>_defconfig`):

```bash
# Enable ESPHome with plugins
BR2_PACKAGE_THINGINO_ESPHOME=y
# Enable Wake Word support
BR2_PACKAGE_THINGINO_ESPHOME_WAKE_WORD=y
```

### 2. Build Firmware

```bash
make rebuild-thingino-esphome
make
```

The plugin will be automatically discovered and built by the esphome-linux build system.

### 3. Runtime Setup

Ensure IAD is running on the camera:

```bash
# Check if IAD is running
ps | grep iad

# Start IAD if not running
/etc/init.d/S96iad start

# Verify IAD sockets exist
ls -la /dev/shm/ | grep ingenic_audio
```

## Usage

### Home Assistant Configuration

Once the device is added to Home Assistant via ESPHome integration, a MediaPlayer entity will automatically appear:

```yaml
# Example Home Assistant automation
automation:
  - alias: "Announce on camera"
    trigger:
      platform: state
      entity_id: binary_sensor.front_door
      to: 'on'
    action:
      - service: media_player.play_media
        target:
          entity_id: media_player.thingino_camera_speaker
        data:
          media_content_id: "http://homeassistant.local:8123/local/doorbell.wav"
          media_content_type: "music"
          announce: true
```

### Supported Commands

| Command       | Description               | Supported |
|---------------|---------------------------|-----------|
| `PLAY`        | Resumes playback          | ⚠️ Partial (sets state, no resume) |
| `STOP`        | Stop current playback     | ✅ Yes |
| `PAUSE`       | Pause playback            | ⚠️ Partial (sets state, no resume) |
| `MUTE`        | Mute audio output         | ✅ Yes |
| `UNMUTE`      | Unmute audio output       | ✅ Yes |
| `VOLUME_UP`   | Increase volume by 10%    | ✅ Yes |
| `VOLUME_DOWN` | Decrease volume by 10%    | ✅ Yes |
| `SET_VOLUME`  | Set specific volume level | ✅ Yes |

### Supported Audio Formats

The plugin supports formats compatible with the Ingenic Audio Daemon:

| Format | Sample Rate | Channels | Bit Depth | Purpose |
|--------|-------------|----------|-----------|---------|
| WAV | 16000 Hz | 1 (mono) | 16-bit | Default |
| WAV | 48000 Hz | 1 (mono) | 16-bit | High quality |

**Note**: For best results, use 16kHz mono WAV files. Higher sample rates may work but consume more bandwidth.

### Text-to-Speech (TTS) Example

```yaml
# Home Assistant TTS configuration
tts:
  - platform: google_translate
    language: 'en'

# Automation using TTS
automation:
  - alias: "TTS Announcement"
    action:
      - service: tts.google_translate_say
        target:
          entity_id: media_player.thingino_camera_speaker
        data:
          message: "Motion detected at the front door"
```

## Technical Details

### IAD Communication Protocol

The plugin communicates with IAD via Unix domain sockets:

#### Audio Output Socket
- **Path**: `@ingenic_audio_output` (abstract namespace)
- **Type**: SOCK_STREAM
- **Usage**: Streaming audio data for playback

#### Control Socket
- **Path**: `@ingenic_audio_control` (abstract namespace)
- **Type**: SOCK_STREAM
- **Protocol**: Text-based GET/SET commands

```c
// Example: Get a variable
GET sampleVariableA
→ Response: "value"

// Example: Set a variable
SET sampleVariableB 42
→ Response: "RESPONSE_OK"
```

### Audio Streaming Flow

1. **Receive Command**: Home Assistant sends `MediaPlayerCommandRequest` via ESPHome API
2. **Parse Message**: Plugin extracts command, URL, volume, announcement flag
3. **Connect to IAD**: Establish connection to audio output socket
4. **Stream Audio**:
   - Download audio from URL using CURL
   - Stream directly to IAD socket (no intermediate buffering)
   - CURL write callback sends chunks to socket
5. **Update State**: Report state changes back to Home Assistant
6. **Cleanup**: Close socket, update state to IDLE

### State Management

The plugin maintains state in `MediaPlayerContext`:

```c
typedef struct {
    MediaPlayerState state;      // Current playback state
    float volume;                // 0.0 to 1.0
    bool muted;                  // Mute state
    pthread_mutex_t lock;        // Thread safety
    int audio_sock;              // IAD socket
    pthread_t playback_thread;   // Streaming thread
    bool playback_active;        // Playback in progress
    char *current_url;           // Current media URL
    bool is_announcement;        // Announcement mode
} MediaPlayerContext;
```

State transitions:
- `IDLE` → `PLAYING` (when URL playback starts)
- `IDLE` → `ANNOUNCING` (when announcement playback starts)
- `PLAYING` → `IDLE` (when playback completes)
- `PLAYING` → `PAUSED` (when pause command received)
- Any → `IDLE` (when stop command received)

## Troubleshooting

### Audio Not Playing

1. **Check IAD Status**:
   ```bash
   /etc/init.d/S96iad status
   # If not running:
   /etc/init.d/S96iad start
   ```

2. **Verify Socket Connectivity**:
   ```bash
   # Check if sockets exist
   ls -la /proc/net/unix | grep ingenic_audio
   ```

3. **Test IAD Directly**:
   ```bash
   # Download a test WAV file
   wget http://example.com/test.wav -O /tmp/test.wav

   # Play using iac client
   iac -f /tmp/test.wav
   ```

4. **Check ESPHome Logs**:
   ```bash
   logread -f | grep -i "mediaplayer\|esphome"
   ```

### Connection Errors

1. **IAD Not Running**:
   - Error: `connect to audio output socket: Connection refused`
   - Solution: Start IAD with `/etc/init.d/S96iad start`

2. **Socket Permission Issues**:
   - Error: `connect: Permission denied`
   - Solution: Ensure esphome-linux runs as root or same user as IAD

### Playback Issues

1. **Audio Garbled/Distorted**:
   - Cause: Sample rate mismatch
   - Solution: Convert audio to 16kHz mono WAV

2. **Playback Stutters**:
   - Cause: Network bandwidth or CPU load
   - Solution: Use lower quality audio or check network

3. **URL Not Accessible**:
   - Error logged: `CURL error: Couldn't resolve host`
   - Solution: Verify camera has internet/network access

## Development

### Adding New Features

To extend the plugin:

1. **Edit Source**: Modify `thingino_media_player.c`
2. **Rebuild Plugin**: `make rebuild-thingino-esphome`
3. **Test**: Deploy and test on device

### Debug Mode

Enable verbose logging by modifying the plugin:

```c
#define DEBUG_MEDIA_PLAYER
#ifdef DEBUG_MEDIA_PLAYER
    printf("[DEBUG][MediaPlayer] Detailed info here\n");
#endif
```

Rebuild with debug symbols:
```bash
# Add to local.fragment
BR2_ENABLE_DEBUG=y
```

### Testing

Manual test using `iac`:

```bash
# Test audio playback
curl -s http://example.com/test.wav | iac -s

# Test with file
iac -f /path/to/audio.wav
```

## Limitations

1. **No Pause/Resume**: IAD doesn't support pausing, only stop
2. **No Playlist**: Single URL playback only
3. **Format Restrictions**: Limited to IAD-supported formats
4. **No Seeking**: Cannot seek within audio stream
5. **Mono Only**: Stereo audio will be downmixed by IAD

## References

- [ESPHome MediaPlayer Component](https://esphome.io/components/media_player/speaker/)
- [Ingenic Audio Daemon](https://github.com/gtxaspec/ingenic_audiodaemon)
- [ESPHome Native API](https://esphome.io/components/api.html)
- [CURL Library](https://curl.se/libcurl/)

## License

This plugin is part of the Thingino firmware project and follows the same license.

## Contributing

Contributions welcome! Please:
1. Test on actual hardware
2. Follow existing code style
3. Update documentation
4. Submit PR to Thingino firmware repository

## Support

For issues or questions:
- Discord: https://discord.gg/xDmqS944zr
- Telegram: https://t.me/thingino
- GitHub Issues: https://github.com/themactep/thingino-firmware/issues
