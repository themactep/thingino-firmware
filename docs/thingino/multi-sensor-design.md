# Multi-Sensor Support Design Document for Prudynt

## Overview

This document describes the architecture and implementation plan for adding multi-sensor support to prudynt on T23 (and potentially other) platforms. The goal is to support cameras with multiple image sensors, providing independent streams for each sensor and optional combined/stitched views.

## Hardware Context

### Target Device
- **Platform:** T23N SoC (Ingenic)
- **Camera:** Jooan W8U (dual-sensor)
- **Sensors:** 2x SC2336 (sc2336s0, sc2336s1)
- **MIPI Switch GPIO:** 7
- **Sensor GPIOs:** sensor_1=18, sensor_2=16
- **SDK:** T23 1.3.0 multi-sensor variant (BR2_THINGINO_INGENIC_SDK_T23_1_3_0_MULTI)
- **ISP Direct Mode:** BR2_ISP_DIRECT_MODE_2=y (dual-sensor IVDC)

## SDK APIs for Multi-Sensor Support

### Initialization Sequence

From the SDK samples and headers, the multi-sensor initialization must follow this order:

```
1. IMP_ISP_Open()
2. IMP_ISP_MultiCamera_SetSwitchgpio()     // Before AddSensor, sets MIPI switch GPIO
3. IMP_ISP_SetCameraInputMode()             // Optional: configure image joint mode
4. IMP_ISP_AddSensor(&sensor0_info)         // Add first sensor (IMPVI_MAIN)
5. IMP_ISP_AddSensor(&sensor1_info)         // Add second sensor (IMPVI_SEC)
6. IMP_ISP_EnableSensor()                   // Enables all added sensors
7. IMP_System_Init()
8. IMP_ISP_EnableTuning()
```

### Key Structures

```c
// MIPI switch GPIO configuration
typedef struct {
    uint16_t enable;        // Enable user customization MIPI SWITCH control GPIO
    uint16_t sensornum;     // sensor number (2 for dual)
    union {
        IMPDoubleSensor d;  // Dual camera structure
        IMPTrebleSensor t;  // Triple camera structure
    };
} IMPUserSwitchgpio;

typedef struct {
    unsigned short switch_gpio;  // Dual camera MIPI SWITCH control GPIO
    uint16_t Msensor_gstate;     // Main camera MIPI SWITCH GPIO STATE
    uint16_t Ssensor_gstate;     // Second camera MIPI SWITCH GPIO STATE
} IMPDoubleSensor;

// Image joint/splicing modes
typedef enum {
    IMPISP_NOT_JOINT = 0,           // No splicing - separate views

    // fs0 spliced with fs3
    IMPISP_03_ON_THE_LEFT,          // Main image on left
    IMPISP_03_ON_THE_RIGHT,         // Main image on right
    IMPISP_03_ON_THE_ABOVE,         // Main image on top
    IMPISP_03_ON_THE_UNDER,         // Main image on bottom

    // fs1 spliced with fs4
    IMPISP_14_ON_THE_LEFT,
    IMPISP_14_ON_THE_RIGHT,
    IMPISP_14_ON_THE_ABOVE,
    IMPISP_14_ON_THE_UNDER,

    // Both main streams spliced (fs0+fs3 and fs1+fs4)
    IMPISP_03_14_ON_THE_LEFT = 0x15,
    IMPISP_03_14_ON_THE_RIGHT = 0x26,
    IMPISP_03_14_ON_THE_ABOVE = 0x37,
    IMPISP_03_14_ON_THE_UNDER = 0x48,
} IMPISPDualSensorSplitJoint;

typedef struct {
    IMPISPDualSensorSplitJoint joint_mode;
    uint16_t outstride[2];  // [0]: main stream f0+f3 span, [1]: sub stream f1+f4 span
} IMPISPCameraInputMode;
```

### Channel Architecture

According to SDK sample `sample-Encoder-Double-Ivdc.c`:

| Sensor | FS Channels | Encoder Groups | Purpose |
|--------|-------------|----------------|---------|
| Sensor 0 (Main)   | FS 0, 1, 2 | ENC 0, 2 | Main camera streams |
| Sensor 1 (Secondary) | FS 3, 4, 5 | ENC 1, 3 | Secondary camera streams |

**IVDC Requirement:** For T23 multi-sensor mode, encoders MUST have `bEnableIvdc = true` for main streams (ISP VPU Direct Connect bypasses frame buffer copy).

### Multi-Camera Tuning APIs

The SDK provides sensor-specific tuning APIs that take `IMPVI_NUM` parameter:
- `IMP_ISP_MultiCamera_Tuning_SetSensorFPS(num, fps_num, fps_den)`
- `IMP_ISP_MultiCamera_Tuning_SetBrightness(num, bright)`
- `IMP_ISP_MultiCamera_Tuning_SetContrast(num, contrast)`
- `IMP_ISP_MultiCamera_Tuning_SetSaturation(num, sat)`
- `IMP_ISP_MultiCamera_Tuning_SetSharpness(num, sharp)`
- `IMP_ISP_MultiCamera_Tuning_SetHVFlip(num, hflip, vflip)`
- `IMP_ISP_MultiCamera_Tuning_AwbSync(num, sync_flag)` // AWB alignment between sensors

## Proposed Architecture

### Configuration Schema Changes

Extend `sensor` section in config:

```json
{
  "sensor": {
    "model": "sc2336",
    "multi_sensor": {
      "enabled": true,
      "count": 2,
      "mipi_switch_gpio": 7,
      "joint_mode": "none",
      "sensors": [
        {
          "index": 0,
          "model": "sc2336s0",
          "i2c_address": "0x30",
          "gpio_reset": 18
        },
        {
          "index": 1,
          "model": "sc2336s1",
          "i2c_address": "0x30",
          "gpio_reset": 16
        }
      ]
    }
  }
}
```

Joint mode options: `"none"`, `"side_by_side"`, `"stacked"`, `"left"`, `"right"`, `"above"`, `"below"`

### Stream Endpoint Design

**Single-Sensor Mode (current):**
- `/stream0` - Main stream (1080p)
- `/stream1` - Sub stream (480p/360p)
- `/stream2` - JPEG stream

**Multi-Sensor Mode (proposed):**

Option A - Separate Endpoints:
- `/stream0` - Sensor 0 main stream
- `/stream1` - Sensor 0 sub stream
- `/stream2` - Sensor 1 main stream
- `/stream3` - Sensor 1 sub stream
- `/combined` - Optional stitched view

Option B - Sensor Prefix (cleaner for >2 sensors):
- `/sensor0/main` - Sensor 0 main
- `/sensor0/sub` - Sensor 0 sub
- `/sensor1/main` - Sensor 1 main
- `/sensor1/sub` - Sensor 1 sub
- `/combined` - Stitched view

**Recommendation:** Use Option A for backward compatibility, with stream0/1 remaining primary camera.

### Class Structure Changes

#### New: IMPMultiSensor Class

```cpp
class IMPMultiSensor {
public:
    static IMPMultiSensor* createNew();

    int init();
    int destroy();

    // Configure MIPI switch
    int setMipiSwitch(int gpio, int main_state, int sec_state);

    // Configure joint mode
    int setJointMode(IMPISPDualSensorSplitJoint mode);

    // Add sensors
    int addSensor(int index, IMPSensorInfo* info);

    // Get sensor count
    int getSensorCount() const { return sensor_count_; }

    // Per-sensor tuning wrappers
    int setSensorFPS(IMPVI_NUM num, int fps_num, int fps_den);
    int setSensorBrightness(IMPVI_NUM num, unsigned char val);
    // ... etc

private:
    int sensor_count_ = 0;
    IMPSensorInfo sensors_[3];  // Up to 3 sensors
    IMPUserSwitchgpio switch_gpio_;
};
```

#### Modified: IMPSystem

```cpp
class IMPSystem {
public:
    // New method for multi-sensor init
    int initMultiSensor();

private:
    IMPMultiSensor* multi_sensor_ = nullptr;
    bool is_multi_sensor_ = false;
};
```

#### Modified: IMPEncoder

Already has `bEnableIvdc` support added. Additional changes:

```cpp
class IMPEncoder {
public:
    // Constructor with sensor index
    IMPEncoder(int sensor_index, int channel, ...);

    // Map sensor index to encoder group
    static int getEncoderGroup(int sensor_index, int stream_type);

private:
    int sensor_index_ = 0;
};
```

#### Modified: IMPFramesource

```cpp
class IMPFramesource {
public:
    // Constructor with sensor-aware channel mapping
    static int getChannelForSensor(int sensor_index, int channel_type);
    // sensor_index=0, channel_type=0 -> FS 0
    // sensor_index=0, channel_type=1 -> FS 1
    // sensor_index=1, channel_type=0 -> FS 3
    // sensor_index=1, channel_type=1 -> FS 4

private:
    int sensor_index_ = 0;
};
```

### IPC Commands for Runtime Control

New commands for multi-sensor control:

```
# Switch active view (for single-output mode)
prudyntctl switch_sensor <0|1>

# Set joint mode at runtime
prudyntctl set_joint_mode <none|side_by_side|stacked>

# Per-sensor image adjustments
prudyntctl sensor <0|1> brightness <value>
prudyntctl sensor <0|1> flip <h|v|both|none>

# AWB sync between sensors
prudyntctl awb_sync <on|off>
```

## Implementation Phases

### Phase 1: Foundation (Required for Basic Operation)
1. **IMPSystem multi-sensor init path**
   - Detect multi-sensor config
   - Call `IMP_ISP_MultiCamera_SetSwitchgpio()`
   - Call `IMP_ISP_AddSensor()` for each sensor
   - Update `IMP_ISP_EnableSensor()` flow

2. **Config schema extension**
   - Add `multi_sensor` config section
   - Parse sensor array
   - Validate against platform capabilities

3. **Channel mapping abstraction**
   - Map sensor_index + stream_type to FS channel
   - Map sensor_index + stream_type to encoder group

### Phase 2: Independent Streams
1. **VideoWorker per sensor**
   - Instantiate VideoWorker for each sensor's FS channels
   - Configure encoder with correct group mapping

2. **RTSP endpoint expansion**
   - Create endpoints for each sensor's streams
   - Maintain backward compat: `/stream0` = sensor 0 main
   - Audio track associated with main sensor (sensor 0) streams only

3. **JPEG endpoint**
   - Shared JPEG endpoint with sensor parameter: `/jpeg?sensor=0` or `/jpeg?sensor=1`
   - Default to sensor 0 when parameter omitted (backward compat)

### Phase 3: Combined Views
1. **Joint mode support**
   - Implement `IMP_ISP_SetCameraInputMode()`
   - Create combined stream endpoint
   - Handle resolution doubling (side-by-side: 2x width)

2. **Runtime switching**
   - IPC commands for mode changes
   - Handle encoder reinit on mode change

### Phase 4: Per-Sensor Tuning
1. **Image controls per sensor**
   - Extend image config with sensor index
   - Use `IMP_ISP_MultiCamera_Tuning_*` APIs

2. **Day/night per sensor**
   - Independent day/night state per sensor
   - Or synchronized mode with AWB sync

### Phase 5: OSD and Recording
1. **OSD per sensor stream**
   - Independent OSD regions per stream
   - Sensor identifier overlay option

2. **Recording**
   - Select which sensor(s) to record
   - Combined view recording option

## Memory Considerations

Multi-sensor operation significantly increases memory usage:

| Component | Single Sensor | Dual Sensor |
|-----------|---------------|-------------|
| FS Buffers | 3 channels | 6 channels |
| Encoder Buffers | 2 groups | 4 groups |
| OSD Pools | 1 set | 2 sets |

**Mitigation:**
- Reduce buffer counts per channel (use `buffers: 2`)
- Limit max resolution per sensor
- Cap encoder buffer size (already implemented: 1.5MB max)
- Disable unused streams

## Risk Analysis

| Risk | Mitigation |
|------|------------|
| SDK API instability | Test thoroughly on target hardware |
| Memory exhaustion | Conservative buffer sizing, monitoring |
| MIPI timing issues | Follow SDK sample timing precisely |
| OSD region conflicts | Isolate region IDs per sensor |
| Backward compatibility | Feature-flag multi-sensor code paths |

## Testing Strategy

1. **Unit Tests**
   - Channel mapping functions
   - Config parsing

2. **Integration Tests**
   - Single sensor still works (regression)
   - Dual sensor init sequence
   - Stream independence

3. **Hardware Tests**
   - Jooan W8U specific testing
   - Frame rate parity between sensors
   - Long-running stability

## Design Decisions

1. **JPEG handling:** Shared endpoint with sensor parameter (`/jpeg?sensor=N`), defaults to sensor 0
2. **Motion detection:** Main sensor (sensor 0) only - microphone is on main sensor assembly
3. **Privacy mask:** Per sensor (independent masks for each view)
4. **Audio association:** Main sensor (sensor 0) streams only - hardware mic is on main sensor assembly

## References

- SDK samples: `sdk/t23/1.3.0/software/board/Ingenic-SDK-T23/media/en/samples/libimp-samples/`
  - `sample-Encoder-Double-Ivdc.c`
  - `sample-Encoder-Treble-Ivdc.c`
- SDK headers: `sdk/t23/1.3.0/software/board/Ingenic-SDK-T23/media/en/include/imp/`
  - `imp_isp.h` (lines 8030-8139 for multi-camera APIs)
  - `imp_encoder.h` (bEnableIvdc)
