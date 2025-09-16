# AudioWorker Buffer Warning Fix

## Problem Description

If you're seeing repeated warning messages in your logs like this:

```
[WARN:AudioWorker.cpp]: AudioWorker buffer nearing capacity: 320/640 samples/ch (0 drops so far)
```

This indicates that the audio buffer is consistently reaching the warning threshold, causing log spam.

## Root Cause

The AudioWorker uses a frame accumulator for Opus audio encoding that collects 20ms audio frames. The warning occurs when the buffer reaches a certain threshold:

- **Default warning threshold**: 3 frames (60ms)
- **Default capacity**: 5 frames (100ms)
- **Actual issue**: The system's audio processing latency causes the buffer to consistently hit the warning threshold

## Solution

### Automatic Fix (Recommended)

Run the provided fix script:

```bash
cd /path/to/thingino-firmware
./scripts/fix-audio-buffer-warnings.sh
```

This script will:
1. Backup your current configuration
2. Update buffer thresholds to more appropriate values
3. Validate the changes

### Manual Fix

Edit `/etc/prudynt.json` and add or update the audio buffer settings:

```json
{
  "audio": {
    "buffer_warn_frames": 5,
    "buffer_cap_frames": 8
  }
}
```

Then restart prudynt:
```bash
systemctl restart prudynt
```

### Using jct (JSON Config Tool)

If you have `jct` available:

```bash
jct /etc/prudynt.json set audio.buffer_warn_frames 5
jct /etc/prudynt.json set audio.buffer_cap_frames 8
systemctl restart prudynt
```

## Configuration Details

### Buffer Settings Explained

- **`buffer_warn_frames`**: Warning threshold in 20ms frames per channel
  - Old default: 3 frames (60ms)
  - New default: 5 frames (100ms)
  - Range: 1-20 frames

- **`buffer_cap_frames`**: Hard capacity limit in 20ms frames per channel
  - Old default: 5 frames (100ms)
  - New default: 8 frames (160ms)
  - Range: 2-30 frames (must be > buffer_warn_frames)

### Rate Limiting

The updated AudioWorker code also includes rate limiting to prevent excessive warning messages:
- Warnings are limited to once every 5 seconds maximum
- This prevents log spam even if the buffer occasionally hits the threshold

## Technical Background

### Why This Happens

1. **Opus Frame Accumulation**: Prudynt accumulates audio samples to create consistent 20ms Opus frames
2. **System Latency**: Audio processing, encoding, and network transmission introduce latency
3. **Buffer Buildup**: When the system can't process frames as fast as they arrive, the buffer fills up
4. **Warning Threshold**: The original threshold (3 frames) was too aggressive for typical system latency

### Buffer Behavior

- **Normal Operation**: Buffer level fluctuates between 0-2 frames
- **High Load**: Buffer may reach 3-4 frames during CPU spikes or network congestion
- **Warning Zone**: 5+ frames indicates sustained processing delays
- **Drop Zone**: 8+ frames triggers sample dropping to prevent unbounded latency

## Monitoring

After applying the fix, monitor your system:

```bash
# Watch for AudioWorker messages
tail -f /var/log/messages | grep AudioWorker

# Check RTSP status for buffer metrics
cat /proc/rtsp_status/audio0/buffer_level_samples_per_channel
cat /proc/rtsp_status/audio0/buffer_drop_count
```

## Troubleshooting

### If Warnings Persist

If you still see warnings after increasing the thresholds:

1. **Check system load**: High CPU usage can cause audio processing delays
2. **Network issues**: Poor network conditions can cause buffer buildup
3. **Hardware limitations**: Some devices may need even higher thresholds

### Reverting Changes

If you need to revert to original settings:

```bash
# Restore from backup (created by fix script)
cp /etc/prudynt.json.backup.* /etc/prudynt.json
systemctl restart prudynt
```

Or manually set lower values:
```bash
jct /etc/prudynt.json set audio.buffer_warn_frames 3
jct /etc/prudynt.json set audio.buffer_cap_frames 5
systemctl restart prudynt
```

## Related Files

- `overrides/prudynt-t/src/AudioWorker.cpp` - Main audio processing logic
- `overrides/prudynt-t/src/Config.cpp` - Configuration handling
- `overrides/prudynt-t/res/prudynt.json` - Default configuration template
- `scripts/fix-audio-buffer-warnings.sh` - Automated fix script
