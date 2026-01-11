#!/bin/haserl --upload-limit=1024 --upload-dir=/tmp
<%in _common.cgi %>
<%
page_title="Camera preview"
which motors > /dev/null && has_motors="true"

motors_domain="motors"
motors_config_file="/etc/motors.json"
motors_temp_config_file="/tmp/$motors_domain.json"

motors_defaults() {
  default_for homing "true"
  default_for gpio_invert "false"
  default_for gpio_switch "false"
  default_for speed_pan "900"
  default_for speed_tilt "900"
}

motors_set_value() {
  [ -f "$motors_temp_config_file" ] || echo '{}' > "$motors_temp_config_file"
  jct "$motors_temp_config_file" set "$motors_domain.$1" "$2" >/dev/null 2>&1
}

motors_get_value() {
  jct "$motors_config_file" get "$motors_domain.$1" 2>/dev/null
}

motors_read_config() {
  [ -f "$motors_config_file" ] || return

  gpio_pan=$(motors_get_value gpio_pan)
  gpio_tilt=$(motors_get_value gpio_tilt)
  gpio_switch=$(motors_get_value gpio_switch)
  gpio_invert=$(motors_get_value gpio_invert)
  homing=$(motors_get_value homing)
  is_spi=$(motors_get_value is_spi)
  pos_0=$(motors_get_value pos_0)
  speed_pan=$(motors_get_value speed_pan)
  speed_tilt=$(motors_get_value speed_tilt)
  steps_pan=$(motors_get_value steps_pan)
  steps_tilt=$(motors_get_value steps_tilt)
}

motors_read_config

# normalize
gpio_pan_1=$(echo $gpio_pan | awk '{print $1}')
gpio_pan_2=$(echo $gpio_pan | awk '{print $2}')
gpio_pan_3=$(echo $gpio_pan | awk '{print $3}')
gpio_pan_4=$(echo $gpio_pan | awk '{print $4}')
gpio_tilt_1=$(echo $gpio_tilt | awk '{print $1}')
gpio_tilt_2=$(echo $gpio_tilt | awk '{print $2}')
gpio_tilt_3=$(echo $gpio_tilt | awk '{print $3}')
gpio_tilt_4=$(echo $gpio_tilt | awk '{print $4}')
pos_0_x=$(echo $pos_0 | awk -F',' '{print $1}')
pos_0_y=$(echo $pos_0 | awk -F',' '{print $2}')

motors_defaults

# Read daynight configuration from prudynt.json
daynight_config_file="/etc/prudynt.json"

daynight_get_value() {
  jct "$daynight_config_file" get "daynight.$1" 2>/dev/null
}

daynight_read_config() {
  [ -f "$daynight_config_file" ] || return

  daynight_enabled="$(daynight_get_value enabled)"
  daynight_total_gain_night_threshold="$(daynight_get_value total_gain_night_threshold)"
  daynight_total_gain_day_threshold="$(daynight_get_value total_gain_day_threshold)"
  daynight_controls_color="$(daynight_get_value controls.color)"
  daynight_controls_ir850="$(daynight_get_value controls.ir850)"
  daynight_controls_ir940="$(daynight_get_value controls.ir940)"
  daynight_controls_ircut="$(daynight_get_value controls.ircut)"
  daynight_controls_white="$(daynight_get_value controls.white)"
}

daynight_read_config

OSD_FONT_PATH="/usr/share/fonts"
SENSOR_IQ_PATH="/etc/sensor"
SENSOR_IQ_UPLOAD_PATH="/opt/sensor"
SENSOR_IQ_FILE="${SENSOR}-$(fw_printenv -n soc).bin"
UPLOADED_SENSOR_IQ_FILE="${SENSOR_IQ_UPLOAD_PATH}/uploaded.bin"

if [ "POST" = "$REQUEST_METHOD" ]; then
  case "$POST_form" in
    font)
      error=""
      if [ -z "$HASERL_fontfile_path" ]; then
        set_error_flag "File upload failed. No font selected?"
      elif [ $(stat -c%s $HASERL_fontfile_path) -eq 0 ]; then
        set_error_flag "File upload failed. Empty file?"
      else
        mv "$HASERL_fontfile_path" "$OSD_FONT_PATH/uploaded.ttf"
      fi
      redirect_to $SCRIPT_NAME
      ;;
    sensor)
      error=""
      if [ -n "$HASERL_sensorfile_path" ]; then
        if [ $(stat -c%s $HASERL_sensorfile_path) -eq 0 ]; then
          set_error_flag "File upload failed. Empty file?"
        else
          mkdir -p "$SENSOR_IQ_UPLOAD_PATH"
          mv "$HASERL_sensorfile_path" "$UPLOADED_SENSOR_IQ_FILE"
          ln -sf "$UPLOADED_SENSOR_IQ_FILE" "${SENSOR_IQ_PATH}/${SENSOR_IQ_FILE}"
          service restart prudynt >/dev/null &
          redirect_to $SCRIPT_NAME "success" "Custom sensor IQ file installed"
        fi
      fi
      redirect_to $SCRIPT_NAME
      ;;
    motors)
      error=""
      gpio_pan_1=$POST_gpio_pan_1
      gpio_pan_2=$POST_gpio_pan_2
      gpio_pan_3=$POST_gpio_pan_3
      gpio_pan_4=$POST_gpio_pan_4
      gpio_tilt_1=$POST_gpio_tilt_1
      gpio_tilt_2=$POST_gpio_tilt_2
      gpio_tilt_3=$POST_gpio_tilt_3
      gpio_tilt_4=$POST_gpio_tilt_4
      homing=$POST_homing
      pos_0_x=$POST_pos_0_x
      pos_0_y=$POST_pos_0_y
      speed_pan=$POST_speed_pan
      speed_tilt=$POST_speed_tilt
      steps_pan=$POST_steps_pan
      steps_tilt=$POST_steps_tilt

      motors_defaults

      if [ "true" != "$is_spi" ]; then
        if [ -z "$gpio_pan_1" ] || [ -z "$gpio_pan_2" ] || [ -z "$gpio_pan_3" ] || [ -z "$gpio_pan_4" ] || \
           [ -z "$gpio_tilt_1" ] || [ -z "$gpio_tilt_2" ] || [ -z "$gpio_tilt_3" ] || [ -z "$gpio_tilt_4" ]; then
          set_error_flag "All pins are required"
        fi
      fi

      if [ "0$steps_pan" -le 0 ] || [ "0$steps_tilt" -le 0 ]; then
        set_error_flag "Motor max steps aren't set"
      fi

      if [ -z "$error" ]; then
        gpio_pan="$gpio_pan_1 $gpio_pan_2 $gpio_pan_3 $gpio_pan_4"
        gpio_tilt="$gpio_tilt_1 $gpio_tilt_2 $gpio_tilt_3 $gpio_tilt_4"

        if [ -n "$pos_0_x" ] && [ -n "$pos_0_y" ]; then
          pos_0="$pos_0_x,$pos_0_y"
        else
          pos_0=""
        fi

        tmpfile="$(mktemp -u).json"
        echo '{}' > $tmpfile
        motors_set_value gpio_pan "$gpio_pan"
        motors_set_value gpio_tilt "$gpio_tilt"
        motors_set_value steps_pan "$steps_pan"
        motors_set_value steps_tilt "$steps_tilt"
        motors_set_value speed_pan "$speed_pan"
        motors_set_value speed_tilt "$speed_tilt"
        motors_set_value gpio_switch "$gpio_switch"
        motors_set_value gpio_invert "$gpio_invert"
        motors_set_value homing "$homing"
        motors_set_value pos_0 "$pos_0"

        jct "$motors_config_file" import "$motors_temp_config_file"
        rm "$motors_temp_config_file"

        redirect_to $SCRIPT_NAME "success" "Motor settings updated."
      else
        redirect_to $SCRIPT_NAME "danger" "Error: $error"
      fi
      ;;
    *)
      redirect_to $SCRIPT_NAME
      ;;
  esac
fi

AUDIO_FORMATS="AAC G711A G711U G726 OPUS PCM"
AUDIO_SAMPLING="8000,12000,16000,24000,48000"
AUDIO_BITRATES=$(seq 6 2 256)

if [ "t30" = "$soc_family" ] || [ "t31" = "$soc_family" -a "t31lc" != "$soc_model" ]; then
  FORMATS="H264,H265"
else
  FORMATS="H264"
fi

modes="CBR VBR FIXQP"
case "$soc_family" in
t31) modes="$modes CAPPED_VBR CAPPED_QUALITY" ;;
*) modes="$modes SMART" ;;
esac

SENSOR_FPS_MAX=$(cat /proc/jz/sensor/max_fps)
SENSOR_FPS_MIN=$(cat /proc/jz/sensor/min_fps)

FONTS=$(ls -1 $OSD_FONT_PATH)
%>
<%in _header.cgi %>

<div class="mb-2">
  <button type="button" class="btn btn-outline-secondary btn-sm" id="toggle-tabs">
    <i class="bi bi-layout-sidebar"></i> Toggle Configuration Tabs
  </button>
</div>

<div class="row preview">
  <div class="col" id="preview-col">
    <div id="frame" class="position-relative mb-2">
      <img id="preview" src="/a/nostream.webp" class="img-fluid" alt="Image: Preview"
        data-bs-toggle="modal" data-bs-target="#mdPreview" style="cursor: zoom-in;" tabindex="-1">
<% if [ "true" = "$has_motors" ]; then %>
      <div class="position-absolute top-50 start-50 translate-middle">
        <%in _motors.cgi %>
      </div>
<% fi %>
    </div>
  </div>

  <div class="col-12 col-lg-7 d-none" id="tabs-col">
    <div class="d-flex gap-1 mb-3">
      <button type="button" id="export-config" class="btn btn-secondary" title="Download the active configuration from prudynt's memory as JSON">
        <i class="bi bi-download" title="Export JSON"></i>
      </button>

      <button type="button" id="save-config" class="btn btn-secondary" title="Write the active configuration to /etc/prudynt.json on the camera">
        <i class="bi bi-floppy" title="Save"></i>
      </button>

      <button type="button" id="restart-prudynt" class="btn btn-danger">
        <i class="bi bi-arrow-clockwise" title="Restart Prudynt"></i>
      </button>

      <select class="form-select ms-2" id="tab-selector" aria-label="Select tab">
<% if [ "true" = "$has_motors" ]; then %>
        <option value="ptz">Pan/Tilt Motors</option>
<% fi %>
        <option value="iq">Image Quality</option>
        <option value="streamer">RTSP Main stream</option>
        <option value="osd0">Main stream OSD</option>
        <option value="substream">RTSP Substream</option>
        <option value="osd1">Substream OSD</option>
        <option value="audio">Audio Settings</option>
        <option value="sensor">Sensor IQ File</option>
        <option value="photosensing">Photosensing</option>
      </select>
    </div>

    <div class="tab-content">

<% if [ "true" = "$has_motors" ]; then %>
      <div class="tab-pane" id="ptz" role="tabpanel" aria-labelledby="ptz-tab" tabindex="0">
        <form action="<%= $SCRIPT_NAME %>" method="post" class="mb-0">
          <input type="hidden" name="form" value="motors">

          <h6>Pan motor</h6>
          <div class="row align-items-end g-1 mb-3">
<% if [ "true" != "$is_spi" ]; then %>
            <div class="col"><% field_number "gpio_pan_1" "pin 1" %></div>
            <div class="col"><% field_number "gpio_pan_2" "pin 2" %></div>
            <div class="col"><% field_number "gpio_pan_3" "pin 3" %></div>
            <div class="col"><% field_number "gpio_pan_4" "pin 4" %></div>
            <div class="col">
              <button type="button" class="btn btn-outline-secondary mb-2 flip_motor"
                data-direction="pan" title="Flip pan motion direction">
                <i class="bi bi-arrow-down-up"></i>
              </button>
            </div>
<% fi %>
            <div class="col"><% field_number "steps_pan" "Steps" %></div>
            <div class="col"><% field_number "speed_pan" "Speed" %></div>
          </div>

          <h6>Tilt motor</h6>
          <div class="row align-items-end g-1 mb-3">
<% if [ "true" != "$is_spi" ]; then %>
            <div class="col"><% field_number "gpio_tilt_1" "pin 1" %></div>
            <div class="col"><% field_number "gpio_tilt_2" "pin 2" %></div>
            <div class="col"><% field_number "gpio_tilt_3" "pin 3" %></div>
            <div class="col"><% field_number "gpio_tilt_4" "pin 4" %></div>
            <div class="col">
              <button type="button" class="btn btn-outline-secondary mb-2 flip_motor"
                data-direction="tilt" title="Flip tilt motion direction">
                <i class="bi bi-arrow-left-right"></i>
              </button>
            </div>
<% fi %>
            <div class="col"><% field_number "steps_tilt" "Steps" %></div>
            <div class="col"><% field_number "speed_tilt" "Speed" %></div>
          </div>

          <h6>Homing</h6>
          <% field_switch "homing" "Perform homing on boot" %>
          <div class="row align-items-end g-1">
            <div class="col-2"><% field_number "pos_0_x" "Start pos. X" %></div>
            <div class="col-1 text-center">
              <button type="button" class="btn btn-outline-secondary mb-2 mx-auto read-motors"
                title="Pick up the recent position">
                <i class="bi bi-bullseye"></i>
              </button>
            </div>
            <div class="col-2"><% field_number "pos_0_y" "Start pos. Y" %></div>
          </div>
          <div class="mt-3"><% button_submit %></div>
        </form>
      </div>
<% fi %>

      <div class="tab-pane" id="iq" role="tabpanel" aria-labelledby="iq-tab" tabindex="0">
        <div class="row g-2">
          <div class="col-2"><% field_number_range "brightness" "Brightness" "0,255,1" %></div>
          <div class="col-2"><% field_number_range "contrast" "Contrast" "0,255,1" %></div>
          <div class="col-2"><% field_number_range "sharpness" "Sharpness" "0,255,1" %></div>
          <div class="col-2"><% field_number_range "saturation" "Saturation" "0,255,1" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_number_range "backlight" "Backlight" "0,10,1" %></div>
          <div class="col-2"><% field_number_range "wide_dynamic_range" "WDR" "0,255,1" %></div>
          <div class="col-2"><% field_number_range "tone" "Highlights" "0,255,1" %></div>
          <div class="col-2"><% field_number_range "defog" "Defog" "0,255,1" %></div>
          <div class="col-3"><% field_number_range "noise_reduction" "Noise reduction" "0,255,1" %></div>
          <div class="col-3">
            <div class="mb-2 select" id="image_core_wb_mode_wrap">
              <label for="image_core_wb_mode" class="form-label">White balance mode</label>
              <select class="form-select" id="image_core_wb_mode" name="image_core_wb_mode">
                <option value="0">AUTO</option>
                <option value="1">MANUAL</option>
                <option value="2">DAY LIGHT</option>
                <option value="3">CLOUDY</option>
                <option value="4">INCANDESCENT</option>
                <option value="5">FLOURESCENT</option>
                <option value="6">TWILIGHT</option>
                <option value="7">SHADE</option>
                <option value="8">WARM FLOURESCENT</option>
                <option value="9">CUSTOM</option>
              </select>
            </div>
          </div>
          <div class="col-3"><% field_number_range "image_wb_bgain" "Blue channel gain" "0,1024,1" %></div>
          <div class="col-3"><% field_number_range "image_wb_rgain" "Red channel gain" "0,1024,1" %></div>
          <div class="col-3"><% field_number_range "image_ae_compensation" "<abbr title=\"Automatic Exposure\">AE</abbr> compensation" "0,255,1" %></div>
        </div>
        <div class="row g-2">
          <div class="col-3">
                  <% field_switch "image_hflip" "V-Flip" %>
            <% field_switch "image_vflip" "H-Flip" %>
          </div>
        </div>
      </div>

      <div class="tab-pane" id="streamer" role="tabpanel" aria-labelledby="streamer-tab" tabindex="0">
        <div class="row g-2">
          <div class="col-2"><% field_text "stream0_width" "Width" %></div>
          <div class="col-2"><% field_text "stream0_height" "Height" %></div>
          <div class="col-2"><% field_number_range "stream0_fps" "FPS" "$SENSOR_FPS_MIN,$SENSOR_FPS_MAX,1" %></div>
          <div class="col-2"><% field_text "stream0_gop" "GOP" %></div>
          <div class="col-2"><% field_text "stream0_max_gop" "Max GOP" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_select "stream0_format" "Format" "$FORMATS" %></div>
          <div class="col-2"><% field_text "stream0_bitrate" "Bitrate" %></div>
          <div class="col-3"><% field_select "stream0_mode" "Mode" "$modes" %></div>
          <div class="col-2"><% field_text "stream0_buffers" "Buffers" %></div>
          <div class="col-2"><% field_text "stream0_profile" "Profile" %></div>
        </div>
        <div class="row g-2">
          <div class="col-4"><% field_text "stream0_rtsp_endpoint" "RTSP Endpoint" %></div>
          <div class="col-4">
                  <% field_switch "stream0_video_enabled" "Video in stream" %>
            <% field_switch "stream0_audio_enabled" "Audio in stream" %>
          </div>
        </div>
      </div>

      <div class="tab-pane" id="osd0" role="tabpanel" aria-labelledby="osd0-tab" tabindex="0">
        <div class="row g-2">
          <div class="col-4"><% field_switch "osd0_enabled" "OSD enabled" %></div>
          <div class="col-4">
            <label class="form-label" for="osd0_fontname">Font</label>
            <div class="input-group mb-3">
              <button class="btn btn-secondary" type="button"
                data-bs-toggle="modal" data-bs-target="#mdFont" title="Upload a font">
                <i class="bi bi-upload"></i>
              </button>
              <select class="form-select" id="osd0_fontname">
              <% for f in $FONTS; do %><option><%= $f %></option><% done %>
              </select>
            </div>
          </div>
          <div class="col-2"><% field_text "osd0_fontsize" "Size" %></div>
          <div class="col-2"><% field_text "osd0_strokesize" "Shadow" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_switch "osd0_logo_enabled" "Logo" %></div>
          <div class="col-3"><% field_text "osd0_logo_position" "Position (x,y)" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_switch "osd0_time_enabled" "Time" %></div>
          <div class="col-3"><% field_text "osd0_time_position" "Position (x,y)" %></div>
          <div class="col-2"><% field_color "osd0_time_fillcolor" "Color" %></div>
          <div class="col-2"><% field_color "osd0_time_strokecolor" "Shadow" %></div>
          <div class="col-3"><% field_text "osd0_time_format" "Format" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_switch "osd0_uptime_enabled" "Uptime" %></div>
          <div class="col-3"><% field_text "osd0_uptime_position" "Position (x,y)" %></div>
          <div class="col-2"><% field_color "osd0_uptime_fillcolor" "Color" %></div>
          <div class="col-2"><% field_color "osd0_uptime_strokecolor" "Shadow" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_switch "osd0_usertext_enabled" "User text" %></div>
          <div class="col-3"><% field_text "osd0_usertext_position" "Position (x,y)" %></div>
          <div class="col-2"><% field_color "osd0_usertext_fillcolor" "Color" %></div>
          <div class="col-2"><% field_color "osd0_usertext_strokecolor" "Shadow" %></div>
          <div class="col-3"><% field_text "osd0_usertext_format" "Format" %></div>
        </div>
      </div>

      <div class="tab-pane" id="substream" role="tabpanel" aria-labelledby="substream-tab" tabindex="0">
        <div class="row g-2">
          <div class="col-2"><% field_text "stream1_width" "Width" %></div>
          <div class="col-2"><% field_text "stream1_height" "Height" %></div>
          <div class="col-2"><% field_number_range "stream1_fps" "FPS" "$SENSOR_FPS_MIN,$SENSOR_FPS_MAX,1" %></div>
          <div class="col-2"><% field_text "stream1_gop" "GOP" %></div>
          <div class="col-2"><% field_text "stream1_max_gop" "Max GOP" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_select "stream1_format" "Format" "$FORMATS" %></div>
          <div class="col-2"><% field_text "stream1_bitrate" "Bitrate" %></div>
          <div class="col-3"><% field_select "stream1_mode" "Mode" "$modes" %></div>
          <div class="col-2"><% field_text "stream1_buffers" "Buffers" %></div>
          <div class="col-2"><% field_text "stream1_profile" "Profile" %></div>
        </div>
        <div class="row g-2">
          <div class="col-4"><% field_text "stream1_rtsp_endpoint" "RTSP Endpoint" %></div>
          <div class="col-4">
                  <% field_switch "stream1_video_enabled" "Video in stream" %>
            <% field_switch "stream1_audio_enabled" "Audio in stream" %>
                </div>
        </div>
      </div>

      <div class="tab-pane" id="osd1" role="tabpanel" aria-labelledby="osd1-tab" tabindex="0">
        <div class="row g-2">
          <div class="col-4"><% field_switch "osd1_enabled" "OSD enabled" %></div>
          <div class="col-4">
            <label class="form-label" for="osd1_fontname">Font</label>
            <div class="input-group mb-3">
              <button class="btn btn-secondary" type="button"
                data-bs-toggle="modal" data-bs-target="#mdFont" title="Upload a font">
                <i class="bi bi-upload"></i>
              </button>
              <select class="form-select" id="osd1_fontname">
                <% for f in $FONTS; do %><option><%= $f %></option><% done %>
              </select>
            </div>
          </div>
          <div class="col-2"><% field_text "osd1_fontsize" "Size" %></div>
          <div class="col-2"><% field_text "osd1_strokesize" "Shadow" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_switch "osd1_logo_enabled" "Logo" %></div>
          <div class="col-3"><% field_text "osd1_logo_position" "Position (x,y)" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_switch "osd1_time_enabled" "Time" %></div>
          <div class="col-3"><% field_text "osd1_time_position" "Position (x,y)" %></div>
          <div class="col-2"><% field_color "osd1_time_fillcolor" "Color" %></div>
          <div class="col-2"><% field_color "osd1_time_strokecolor" "Shadow" %></div>
          <div class="col-3"><% field_text "osd1_time_format" "Format" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_switch "osd1_uptime_enabled" "Uptime" %></div>
          <div class="col-3"><% field_text "osd1_uptime_position" "Position (x,y)" %></div>
          <div class="col-2"><% field_color "osd1_uptime_fillcolor" "Color" %></div>
          <div class="col-2"><% field_color "osd1_uptime_strokecolor" "Shadow" %></div>
        </div>
        <div class="row g-2">
          <div class="col-2"><% field_switch "osd1_usertext_enabled" "User text" %></div>
          <div class="col-3"><% field_text "osd1_usertext_position" "Position (x,y)" %></div>
          <div class="col-2"><% field_color "osd1_usertext_fillcolor" "Color" %></div>
          <div class="col-2"><% field_color "osd1_usertext_strokecolor" "Shadow" %></div>
          <div class="col-3"><% field_text "osd1_usertext_format" "Format" %></div>
        </div>
      </div>

      <div class="tab-pane" id="audio" role="tabpanel" aria-labelledby="audio-tab" tabindex="0">
        <h6>Microphone</h6>
        <div class="row g-2">
          <div class="col-2"><% field_select "audio_mic_format" "Codec" "$AUDIO_FORMATS" %></div>
          <div class="col-2"><% field_select "audio_mic_sample_rate" "Sampling, Hz" "$AUDIO_SAMPLING" %></div>
          <div class="col-2"><% field_select "audio_mic_bitrate" "Bitrate, kbps" "$AUDIO_BITRATES" %></div>
          <div class="col-2"><% field_number_range "audio_mic_vol" "Mic volume" "-30,120,1" %></div>
          <div class="col-2"><% field_number_range "audio_mic_gain" "Mic gain" "0,31,1" %></div>
          <div class="col-2"><% field_number_range "audio_mic_alc_gain" "<abbr title=\"Automatic Level Control\">ALC</abbr> gain" "0,7,1" %></div>
        </div>
        <div class="row g-2">
          <div class="col"><% field_switch "audio_mic_agc_enabled" "<abbr title=\"Automatic gain control\">AGC</abbr> Enabled" %></div>
          <div class="col"><% field_switch "audio_mic_high_pass_filter" "High pass filter" %></div>
          <div class="col"><% field_switch "audio_force_stereo" "Force stereo" %></div>
        </div>
        <div class="row g-2">
          <div class="col"><% field_number_range "audio_mic_noise_suppression" "Noise suppression" "0,3,1" %></div>
          <div class="col"><% field_number_range "audio_mic_agc_compression_gain_db" "Compression gain, dB" "0,90,1" %></div>
          <div class="col"><% field_number_range "audio_mic_agc_target_level_dbfs" "Target level, dBfs" "0,31,1" %></div>
        </div>

        <h6>Speaker</h6>
        <div class="row g-2">
          <div class="col"><% field_number_range "audio_spk_vol" "Speaker volume" "-30,120,1" %></div>
          <div class="col"><% field_number_range "audio_spk_gain" "Speaker gain" "0,31,1" %></div>
          <div class="col"><% field_select "audio_spk_sample_rate" "Speaker sampling, Hz" "$AUDIO_SAMPLING" %></div>
        </div>
      </div>

      <div class="tab-pane" id="photosensing" role="tabpanel" aria-labelledby="photosensing-tab" tabindex="0">
        <div class="row g-2">
          <div class="col-12">
            <% field_switch "daynight_enabled" "Enable photosensing on boot" %>
          </div>
          <div class="col col-md-6">
            <h6>Controls</h6>
            <% field_checkbox "daynight_controls_color" "Change color mode" %>
            <% field_checkbox "daynight_controls_ircut" "Flip IR cut filter" %>
            <% field_checkbox "daynight_controls_ir850" "Toggle IR 850 nm" %>
            <% field_checkbox "daynight_controls_ir940" "Toggle IR 940 nm" %>
            <% field_checkbox "daynight_controls_white" "Toggle white light" %>
          </div>
          <div class="col col-md-6">
            <h6>Thresholds</h6>
            <% field_number_range "daynight_total_gain_night_threshold" "Switch to night mode above" "0,10000,1" %>
            <% field_number_range "daynight_total_gain_day_threshold" "Switch to day mode below" "0,10000,1" %>
          </div>
        </div>
      </div>

      <div class="tab-pane" id="sensor" role="tabpanel" aria-labelledby="sensor-tab" tabindex="0">
        <h6>Sensor IQ file</h6>
        <p class="alert alert-secondary">
          File: <%= "${SENSOR_IQ_PATH}/${SENSOR_IQ_FILE}" %><br>
          MD5: <% md5sum "${SENSOR_IQ_PATH}/${SENSOR_IQ_FILE}" | cut -d' ' -f1 %>
        </p>
        <p>Upload a custom sensor IQ file for <span class="fw-bold text-uppercase"><%= $soc_model %></span>
          and <span class="fw-bold text-uppercase"><%= $sensor_model %></span>, e.g. from a stock firmware backup.</p>
        <button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#mdSensorIQ">
          <i class="bi bi-upload"></i> Upload Sensor IQ File
        </button>
      </div>
   </div><!-- .tab-content -->
  </div><!-- #tabs-col -->
</div><!-- .preview -->

<div class="alert alert-dark ui-debug d-none">
  <h4 class="mb-3">Debug info</h4>
</div>

<%in _preview.cgi %>

<script>
const ImageBlackMode = 1
const ImageColorMode = 0

const endpoint = '/x/json-prudynt.cgi';

const stream_params = [
  'width', 'height', 'fps', 'bitrate', 'gop', 'max_gop', 'format', 'mode',
  'buffers', 'profile', 'rtsp_endpoint', 'video_enabled', 'audio_enabled'
];
const osd_params = ['enabled', 'fontname', 'fontsize', 'strokesize'];
const audio_params = [
  'mic_enabled', 'mic_format', 'mic_sample_rate', 'mic_bitrate',
  'mic_vol', 'mic_gain', 'mic_alc_gain', 'mic_agc_enabled',
  'mic_high_pass_filter', 'mic_noise_suppression',
  'mic_agc_compression_gain_db', 'mic_agc_target_level_dbfs',
  'spk_enabled', 'spk_vol', 'spk_gain', 'spk_sample_rate', 'force_stereo'
];

function rgba2color(hex8) {
  return hex8.substring(0, 7);
}

function rgba2alpha(hex8) {
  const alphaHex = hex8.substring(7, 9);
  const alpha = parseInt(alphaHex, 16);
  return alpha;
}

function handleOsdData(osd, streamIndex) {
  if (!osd) return;

  if (osd.enabled !== undefined) {
    const el = $(`#osd${streamIndex}_enabled`);
    if (el) {
      el.checked = osd.enabled;
      el.disabled = false;
    }
  }
  if (osd.font_path) {
    const el = $(`#osd${streamIndex}_fontname`);
    if (el) {
      el.value = osd.font_path.split('/').pop();
      el.disabled = false;
    }
  }
  if (osd.font_size !== undefined) {
    const el = $(`#osd${streamIndex}_fontsize`);
    if (el) {
      el.value = osd.font_size;
      el.disabled = false;
    }
  }
  if (osd.stroke_size !== undefined) {
    const el = $(`#osd${streamIndex}_strokesize`);
    if (el) {
      el.value = osd.stroke_size;
      el.disabled = false;
    }
  }

  // Logo element
  if (osd.logo) {
    if (osd.logo.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_logo_enabled`);
      if (el) {
        el.checked = osd.logo.enabled;
        el.disabled = false;
      }
    }
    if (osd.logo.position !== undefined) {
      const el = $(`#osd${streamIndex}_logo_position`);
      if (el) {
        el.value = osd.logo.position;
        el.disabled = false;
      }
    }
  }

  // Time element
  if (osd.time) {
    if (osd.time.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_time_enabled`);
      if (el) {
        el.checked = osd.time.enabled;
        el.disabled = false;
      }
    }
    if (osd.time.format !== undefined) {
      const el = $(`#osd${streamIndex}_time_format`);
      if (el) {
        el.value = osd.time.format;
        el.disabled = false;
      }
    }
    if (osd.time.position !== undefined) {
      const el = $(`#osd${streamIndex}_time_position`);
      if (el) {
        el.value = osd.time.position;
        el.disabled = false;
      }
    }
    if (osd.time.fill_color) {
      const el = $(`#osd${streamIndex}_time_fillcolor`);
      if (el) {
        el.value = rgba2color(osd.time.fill_color);
        el.disabled = false;
      }
    }
    if (osd.time.stroke_color) {
      const el = $(`#osd${streamIndex}_time_strokecolor`);
      if (el) {
        el.value = rgba2color(osd.time.stroke_color);
        el.disabled = false;
      }
    }
  }

  // Uptime element
  if (osd.uptime) {
    if (osd.uptime.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_uptime_enabled`);
      if (el) {
        el.checked = osd.uptime.enabled;
        el.disabled = false;
      }
    }
    if (osd.uptime.position !== undefined) {
      const el = $(`#osd${streamIndex}_uptime_position`);
      if (el) {
        el.value = osd.uptime.position;
        el.disabled = false;
      }
    }
    if (osd.uptime.fill_color) {
      const el = $(`#osd${streamIndex}_uptime_fillcolor`);
      if (el) {
        el.value = rgba2color(osd.uptime.fill_color);
        el.disabled = false;
      }
    }
    if (osd.uptime.stroke_color) {
      const el = $(`#osd${streamIndex}_uptime_strokecolor`);
      if (el) {
        el.value = rgba2color(osd.uptime.stroke_color);
        el.disabled = false;
      }
    }
  }

  // Usertext element
  if (osd.usertext) {
    if (osd.usertext.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_usertext_enabled`);
      if (el) {
        el.checked = osd.usertext.enabled;
        el.disabled = false;
      }
    }
    if (osd.usertext.format !== undefined) {
      const el = $(`#osd${streamIndex}_usertext_format`);
      if (el) {
        el.value = osd.usertext.format;
        el.disabled = false;
      }
    }
    if (osd.usertext.position !== undefined) {
      const el = $(`#osd${streamIndex}_usertext_position`);
      if (el) {
        el.value = osd.usertext.position;
        el.disabled = false;
      }
    }
    if (osd.usertext.fill_color) {
      const el = $(`#osd${streamIndex}_usertext_fillcolor`);
      if (el) {
        el.value = rgba2color(osd.usertext.fill_color);
        el.disabled = false;
      }
    }
    if (osd.usertext.stroke_color) {
      const el = $(`#osd${streamIndex}_usertext_strokecolor`);
      if (el) {
        el.value = rgba2color(osd.usertext.stroke_color);
        el.disabled = false;
      }
    }
  }
}

function handleMessage(msg) {
  if (msg.motion && msg.motion.enabled !== undefined) {
    $('#motion').checked = msg.motion.enabled;
  }
  if (msg.privacy && msg.privacy.enabled !== undefined) {
    $('#privacy').checked = msg.privacy.enabled;
  }

  // if (msg.rtsp) {
  //   const r = msg.rtsp;
  //   if (r.username && r.password && r.port && msg.stream0?.rtsp_endpoint)
  //     $('#playrtsp').innerHTML = `ffplay -hide_banner -rtsp_transport tcp rtsp://${r.username}:${r.password}@${document.location.hostname}:${r.port}/${msg.stream0.rtsp_endpoint}`;
  // }

  // Handle image params
  if (msg.image) {
    const imageParams = ['hflip', 'vflip', 'wb_bgain', 'wb_rgain', 'ae_compensation', 'core_wb_mode'];
    imageParams.forEach(param => {
      if (msg.image[param] !== undefined) {
        setValue(msg.image, 'image', param);
      }
    });
  }

  // Handle daynight params
  if (msg.daynight) {
    if (msg.daynight.enabled !== undefined) {
      setValue(msg.daynight, 'daynight', 'enabled');
    }
    if (msg.daynight.total_gain_night_threshold !== undefined) {
      setValue(msg.daynight, 'daynight', 'total_gain_night_threshold');
    }
    if (msg.daynight.total_gain_day_threshold !== undefined) {
      setValue(msg.daynight, 'daynight', 'total_gain_day_threshold');
    }
    if (msg.daynight.controls) {
      if (msg.daynight.controls.color !== undefined) {
        const el = $('#daynight_controls_color');
        if (el) {
          el.checked = msg.daynight.controls.color;
          el.disabled = false;
        }
      }
      if (msg.daynight.controls.ircut !== undefined) {
        const el = $('#daynight_controls_ircut');
        if (el) {
          el.checked = msg.daynight.controls.ircut;
          el.disabled = false;
        }
      }
      if (msg.daynight.controls.ir850 !== undefined) {
        const el = $('#daynight_controls_ir850');
        if (el) {
          el.checked = msg.daynight.controls.ir850;
          el.disabled = false;
        }
      }
      if (msg.daynight.controls.ir940 !== undefined) {
        const el = $('#daynight_controls_ir940');
        if (el) {
          el.checked = msg.daynight.controls.ir940;
          el.disabled = false;
        }
      }
      if (msg.daynight.controls.white !== undefined) {
        const el = $('#daynight_controls_white');
        if (el) {
          el.checked = msg.daynight.controls.white;
          el.disabled = false;
        }
      }
    }
  }

  // Handle stream0 params
  if (msg.stream0) {
    stream_params.forEach(param => {
      if (msg.stream0[param] !== undefined) {
        setValue(msg.stream0, 'stream0', param);
      }
    });
    handleOsdData(msg.stream0.osd, 0);
  }

  // Handle stream1 params
  if (msg.stream1) {
    stream_params.forEach(param => {
      if (msg.stream1[param] !== undefined) {
        setValue(msg.stream1, 'stream1', param);
      }
    });
    handleOsdData(msg.stream1.osd, 1);
  }

  // Handle audio params
  if (msg.audio) {
    audio_params.forEach(param => {
      if (msg.audio[param] !== undefined) {
        setValue(msg.audio, 'audio', param);
      }
    });
  }
}

async function loadConfig() {
  const payload = JSON.stringify({
      image: {
        hflip: null, vflip: null,
        wb_bgain: null, wb_rgain: null,
        ae_compensation: null, core_wb_mode: null
      },
      motion: {enabled: null},
      privacy: {enabled: null},
      rtsp: {username: null, password: null, port: null},
      daynight: {
        enabled: null,
        total_gain_night_threshold: null,
        total_gain_day_threshold: null,
        controls: {
          color: null,
          ircut: null,
          ir850: null,
          ir940: null,
          white: null
        }
      },
      stream0: {
        width: null, height: null, fps: null, bitrate: null, gop: null, max_gop: null,
        format: null, mode: null, buffers: null, profile: null, rtsp_endpoint: null,
        video_enabled: null, audio_enabled: null,
        osd: {
          enabled: null, font_path: null, font_size: null, stroke_size: null,
          logo: {enabled: null, position: null},
          time: {enabled: null, format: null, position: null, fill_color: null, stroke_color: null},
          uptime: {enabled: null, position: null, fill_color: null, stroke_color: null},
          usertext: {enabled: null, format: null, position: null, fill_color: null, stroke_color: null}
        }
      },
      stream1: {
        width: null, height: null, fps: null, bitrate: null, gop: null, max_gop: null,
        format: null, mode: null, buffers: null, profile: null, rtsp_endpoint: null,
        video_enabled: null, audio_enabled: null,
        osd: {
          enabled: null, font_path: null, font_size: null, stroke_size: null,
          logo: {enabled: null, position: null},
          time: {enabled: null, format: null, position: null, fill_color: null, stroke_color: null},
          uptime: {enabled: null, position: null, fill_color: null, stroke_color: null},
          usertext: {enabled: null, format: null, position: null, fill_color: null, stroke_color: null}
        }
      },
      audio: {
        mic_enabled: null, mic_format: null, mic_sample_rate: null, mic_bitrate: null,
        mic_vol: null, mic_gain: null, mic_alc_gain: null, mic_agc_enabled: null,
        mic_high_pass_filter: null, mic_noise_suppression: null,
        mic_agc_compression_gain_db: null, mic_agc_target_level_dbfs: null,
        spk_enabled: null, spk_vol: null, spk_gain: null, spk_sample_rate: null,
        force_stereo: null
      },
      action: {capture: null}
    });
  console.log('===>', payload);
  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: payload
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    if (text) {
      try {
        const msg = JSON.parse(text);
        console.log(ts(), '<===', JSON.stringify(msg));
        handleMessage(msg);
      } catch (parseErr) {
        console.warn(ts(), 'Invalid JSON response', text, parseErr);
      }
    } else {
      console.log(ts(), '<===', 'Empty response');
    }
  } catch (err) {
    console.error('Load config error', err);
  }
}

async function sendToEndpoint(payload) {
  console.log(ts(), '--->', payload);
  const payloadStr = typeof payload === 'string' ? payload : JSON.stringify(payload);
  console.log(ts(), '===>', payloadStr);
  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: payloadStr
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    if (text) {
      try {
        const msg = JSON.parse(text);
        console.log(ts(), '<===', JSON.stringify(msg));
        handleMessage(msg);
      } catch (parseErr) {
        console.warn(ts(), 'Invalid JSON response', text, parseErr);
      }
    } else {
      console.log(ts(), '<===', 'Empty response');
    }
  } catch (err) {
    console.error('Send error', err);
  }
}

// Init on load
loadConfig().then(() => {
  // Determine which stream to show based on tabs visibility
  const tabsVisible = localStorage.getItem('preview_tabs_visible') === 'true';
  let streamUrl = tabsVisible ? '/x/ch1.mjpg' : '/x/ch0.mjpg';

  // Preview
  const timeout = 5000;
  const preview = $('#preview');
  let lastLoadTime = Date.now();
  preview.src = streamUrl;
  preview.addEventListener('load', () => {
    lastLoadTime = Date.now();
  });
  setInterval(() => {
    if (Date.now() - lastLoadTime > timeout) {
      // Restart stream
      preview.src = preview.src.split('?')[0] + '?' + new Date().getTime();
      lastLoadTime = Date.now();
    }
  }, 1000);
});

const imagingFields = [
  "brightness",
  "contrast",
  "sharpness",
  "saturation",
  "backlight",
  "wide_dynamic_range",
  "tone",
  "defog",
  "noise_reduction"
];

const imageConfigKeyMap = {
  brightness: "brightness",
  contrast: "contrast",
  sharpness: "sharpness",
  saturation: "saturation",
  backlight: "backlight_compensation",
  wide_dynamic_range: "drc_strength",
  tone: "highlight_depress",
  defog: "defog_strength",
  noise_reduction: "sinter_strength"
};

// Disable all imaging controls initially
imagingFields.forEach(field => {
  const input = $(`#${field}`);
  if (input) {
    input.disabled = true;
    const wrapper = input.closest('.number-range, .col');
    if (wrapper) wrapper.classList.add('disabled');
  }
  // Also disable the modal slider if it exists
  const slider = $(`#${field}-slider`);
  if (slider) slider.disabled = true;
});

function updateImagingLabel(name, value) {
  const input = $(`#${name}`);
  if (input) {
    input.value = value === undefined || value === null ? '' : value;
  }
  // Also update the slider value display in modal
  const sliderValue = $(`#${name}-slider-value`);
  if (sliderValue) {
    const displayValue = value === undefined || value === null ? '—' : value;
    sliderValue.textContent = displayValue;
  }
  // Update the actual slider
  const slider = $(`#${name}-slider`);
  if (slider && value !== undefined && value !== null) {
    slider.value = value;
  }
}

function setSliderBounds(input, slider, min, max, value, defaultValue) {
  if (Number.isFinite(min)) {
    if (input) input.dataset.min = min;
    if (slider) slider.min = min;
  }
  if (Number.isFinite(max)) {
    if (input) input.dataset.max = max;
    if (slider) slider.max = max;
  }
  if (Number.isFinite(value)) {
    if (input) input.value = value;
    if (slider) slider.value = value;
  }
  if (Number.isFinite(defaultValue)) {
    if (input) input.dataset.defaultValue = defaultValue;
    if (slider) slider.dataset.defaultValue = defaultValue;
  } else {
    if (input) delete input.dataset.defaultValue;
    if (slider) delete slider.dataset.defaultValue;
  }
}

function applyFieldMetadata(field, data) {
  const input = $(`#${field}`);
  const slider = $(`#${field}-slider`);
  if (!input) return;
  const wrapper = input.closest('.col, .number-range') || input.parentElement;
  const isSupported = data && data.supported !== false;
  if (!isSupported) {
    input.disabled = true;
    if (slider) slider.disabled = true;
    if (wrapper) wrapper.classList.add('disabled');
    delete input.dataset.defaultValue;
    if (slider) delete slider.dataset.defaultValue;
    updateImagingLabel(field, '—');
    return;
  }
  input.disabled = false;
  if (slider) slider.disabled = false;
  if (wrapper) wrapper.classList.remove('disabled');
  setSliderBounds(input, slider, Number(data.min), Number(data.max), Number(data.value), Number(data.default));
  updateImagingLabel(field, data.value);
}

async function fetchImagingState() {
  try {
    const res = await fetch('/x/json-imaging.cgi?cmd=read', {cache: 'no-store'});
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const payload = await res.json();
    const fields = payload && payload.message && payload.message.fields;
    if (!fields) return;
    imagingFields.forEach(field => applyFieldMetadata(field, fields[field] || null));
  } catch (err) {
    console.warn('Unable to load imaging state', err);
  }
}

async function persistImagingSetting(field, value) {
  const configKey = imageConfigKeyMap[field];
  if (!configKey) return;
  const numericValue = Number(value);
  if (!Number.isFinite(numericValue)) return;
  try {
    await sendToEndpoint({image: {[configKey]: numericValue}});
  } catch (err) {
    console.warn('Failed to persist imaging setting', field, err);
  }
}

async function sendImagingUpdate(field, value, element) {
  const params = new URLSearchParams({cmd: 'set'});
  params.append(field, value);
  element?.setAttribute('data-busy', '1');
  element?.classList.add('opacity-75');
  try {
    const res = await fetch(`/x/json-imaging.cgi?${params.toString()}`, {cache: 'no-store'});
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const text = await res.text();
    if (text) {
      const payload = JSON.parse(text);
      const fields = payload && payload.message && payload.message.fields;
      if (fields) {
        applyFieldMetadata(field, fields[field] || null);
      }
    }
    await persistImagingSetting(field, value);
  } catch (err) {
    console.error('Failed to update imaging value', err);
  } finally {
    element?.removeAttribute('data-busy');
    element?.classList.remove('opacity-75');
  }
}

// Setup event handlers for imaging fields (number inputs and modal sliders)
imagingFields.forEach(field => {
  const input = $(`#${field}`);
  const slider = $(`#${field}-slider`);

  // Handle text input changes
  if (input) {
    input.addEventListener('change', ev => {
      const value = parseInt(ev.target.value);
      if (!isNaN(value)) {
        sendImagingUpdate(field, value, ev.target);
      }
    });

    // Double-click on input to reset to default
    input.addEventListener('dblclick', ev => {
      const min = Number(ev.target.dataset.min ?? 0);
      const max = Number(ev.target.dataset.max ?? 255);
      const midpoint = Math.round((min + max) / 2);
      const defaultValue = ev.target.dataset.defaultValue;
      const targetValue = Number.isFinite(Number(defaultValue)) ? Number(defaultValue) : midpoint;
      ev.target.value = targetValue;
      updateImagingLabel(field, targetValue);
      sendImagingUpdate(field, targetValue, ev.target);
    });
  }

  // Handle modal slider input (live update)
  if (slider) {
    slider.addEventListener('input', ev => {
      updateImagingLabel(field, ev.target.value);
    });

    // Handle slider change (on release)
    slider.addEventListener('change', ev => {
      const value = parseInt(ev.target.value);
      if (!isNaN(value)) {
        sendImagingUpdate(field, value, ev.target);
      }
    });

    // Double-click on slider to reset to default
    slider.addEventListener('dblclick', ev => {
      const min = Number(ev.target.min ?? 0);
      const max = Number(ev.target.max ?? 255);
      const midpoint = Math.round((min + max) / 2);
      const defaultValue = ev.target.dataset.defaultValue;
      const targetValue = Number.isFinite(Number(defaultValue)) ? Number(defaultValue) : midpoint;
      ev.target.value = targetValue;
      updateImagingLabel(field, targetValue);
      sendImagingUpdate(field, targetValue, ev.target);
    });
  }
});

// Streamer controls
function coerceStreamValue(param, el) {
  if (el.type === 'checkbox') {
    return el.checked;
  }

  const raw = typeof el.value === 'string' ? el.value : '';
  const trimmed = raw.trim();
  if (trimmed === '') {
    return '';
  }

  // Treat any purely numeric string as a number so prudynt gets the correct type.
  if (/^-?\d+(?:\.\d+)?$/.test(trimmed)) {
    return trimmed.includes('.') ? Number.parseFloat(trimmed) : Number.parseInt(trimmed, 10);
  }

  return trimmed;
}

function saveStreamValue(streamId, param) {
  const el = $(`#stream${streamId}_${param}`);
  if (!el) return;
  const value = coerceStreamValue(param, el);
  const payload = {[`stream${streamId}`]: {[param]: value}, action: {restart_thread: ThreadRtsp | ThreadVideo}};
  sendToEndpoint(payload);
}

// Setup stream0 and stream1 controls
[0, 1].forEach(streamId => {
  stream_params.forEach(param => {
    const el = $(`#stream${streamId}_${param}`);
    if (el) {
      el.addEventListener('change', () => saveStreamValue(streamId, param));
      el.disabled = true;
    }

    // Also handle modal slider if it exists
    const slider = $(`#stream${streamId}_${param}-slider`);
    if (slider) {
      slider.addEventListener('input', ev => {
        // Update the text input while dragging
        if (el) el.value = ev.target.value;
        const sliderValue = $(`#stream${streamId}_${param}-slider-value`);
        if (sliderValue) sliderValue.textContent = ev.target.value;
      });
      slider.addEventListener('change', () => saveStreamValue(streamId, param));
      slider.disabled = true;
    }
  });
});

// OSD controls
function sendOsdUpdate(streamId, osdPayload) {
  // OSD changes require Video + OSD thread restart to take effect immediately
  const payload = {[`stream${streamId}`]: {osd: osdPayload}, action: {restart_thread: ThreadVideo | ThreadOSD}};
  sendToEndpoint(payload);
}

function setFont(streamId) {
  const fontSelect = $(`#osd${streamId}_fontname`);
  const fontSizeInput = $(`#osd${streamId}_fontsize`);
  const strokeSizeInput = $(`#osd${streamId}_strokesize`);
  if (!fontSelect || !fontSizeInput || !strokeSizeInput) return;

  const payload = {};
  const fontName = fontSelect.value;
  if (fontName)
    payload.font_path = `/usr/share/fonts/${fontName}`;

  const fontSize = Number(fontSizeInput.value);
  if (!Number.isNaN(fontSize)) {
    payload.font_size = fontSize;
  }

  const strokeSize = Number(strokeSizeInput.value);
  if (!Number.isNaN(strokeSize)) {
    payload.stroke_size = strokeSize;
  }

  if (Object.keys(payload).length === 0) return;
  console.log(ts(), 'setFont for stream', streamId, ':', payload);
  // Font changes require Video + OSD thread restart for immediate effect
  const fullPayload = {[`stream${streamId}`]: {osd: payload}, action: {restart_thread: ThreadVideo | ThreadOSD}};
  sendToEndpoint(fullPayload);
}

// Setup OSD controls for both stream0 and stream1
[0, 1].forEach(streamId => {
  const osdEnabled = $(`#osd${streamId}_enabled`);
  if (osdEnabled) {
    osdEnabled.addEventListener('change', (e) => {
      sendOsdUpdate(streamId, {enabled: e.target.checked});
    });
    osdEnabled.disabled = true;
  }

  const osdFontname = $(`#osd${streamId}_fontname`);
  if (osdFontname) {
    osdFontname.addEventListener('change', () => setFont(streamId));
    osdFontname.disabled = true;
  }

  const osdFontsize = $(`#osd${streamId}_fontsize`);
  if (osdFontsize) {
    osdFontsize.addEventListener('change', () => setFont(streamId));
    osdFontsize.disabled = true;
  }

  const osdStrokesize = $(`#osd${streamId}_strokesize`);
  if (osdStrokesize) {
    osdStrokesize.addEventListener('change', () => setFont(streamId));
    osdStrokesize.disabled = true;
  }

  const osdLogoEnabled = $(`#osd${streamId}_logo_enabled`);
  if (osdLogoEnabled) {
    osdLogoEnabled.addEventListener('change', (e) => {
      sendOsdUpdate(streamId, {logo: {enabled: e.target.checked}});
    });
    osdLogoEnabled.disabled = true;
  }

  const osdLogoPosition = $(`#osd${streamId}_logo_position`);
  if (osdLogoPosition) {
    osdLogoPosition.addEventListener('change', () => {
      sendOsdUpdate(streamId, {logo: {position: osdLogoPosition.value}});
    });
    osdLogoPosition.disabled = true;
  }

  const osdTimeEnabled = $(`#osd${streamId}_time_enabled`);
  if (osdTimeEnabled) {
    osdTimeEnabled.addEventListener('change', (e) => {
      sendOsdUpdate(streamId, {time: {enabled: e.target.checked}});
    });
    osdTimeEnabled.disabled = true;
  }

  const osdTimeFormat = $(`#osd${streamId}_time_format`);
  if (osdTimeFormat) {
    osdTimeFormat.addEventListener('change', () => {
      sendOsdUpdate(streamId, {time: {format: osdTimeFormat.value}});
    });
    osdTimeFormat.disabled = true;
  }

  const osdTimePosition = $(`#osd${streamId}_time_position`);
  if (osdTimePosition) {
    osdTimePosition.addEventListener('change', () => {
      sendOsdUpdate(streamId, {time: {position: osdTimePosition.value}});
    });
    osdTimePosition.disabled = true;
  }

  const osdTimeFillcolor = $(`#osd${streamId}_time_fillcolor`);
  if (osdTimeFillcolor) {
    osdTimeFillcolor.addEventListener('change', () => {
      sendOsdUpdate(streamId, {time: {fill_color: osdTimeFillcolor.value + 'ff'}});
    });
    osdTimeFillcolor.disabled = true;
  }

  const osdTimeStrokecolor = $(`#osd${streamId}_time_strokecolor`);
  if (osdTimeStrokecolor) {
    osdTimeStrokecolor.addEventListener('change', () => {
      sendOsdUpdate(streamId, {time: {stroke_color: osdTimeStrokecolor.value + 'ff'}});
    });
    osdTimeStrokecolor.disabled = true;
  }

  const osdUptimeEnabled = $(`#osd${streamId}_uptime_enabled`);
  if (osdUptimeEnabled) {
    osdUptimeEnabled.addEventListener('change', (e) => {
      sendOsdUpdate(streamId, {uptime: {enabled: e.target.checked}});
    });
    osdUptimeEnabled.disabled = true;
  }

  const osdUptimePosition = $(`#osd${streamId}_uptime_position`);
  if (osdUptimePosition) {
    osdUptimePosition.addEventListener('change', () => {
      sendOsdUpdate(streamId, {uptime: {position: osdUptimePosition.value}});
    });
    osdUptimePosition.disabled = true;
  }

  const osdUptimeFillcolor = $(`#osd${streamId}_uptime_fillcolor`);
  if (osdUptimeFillcolor) {
    osdUptimeFillcolor.addEventListener('change', () => {
      sendOsdUpdate(streamId, {uptime: {fill_color: osdUptimeFillcolor.value + 'ff'}});
    });
    osdUptimeFillcolor.disabled = true;
  }

  const osdUptimeStrokecolor = $(`#osd${streamId}_uptime_strokecolor`);
  if (osdUptimeStrokecolor) {
    osdUptimeStrokecolor.addEventListener('change', () => {
      sendOsdUpdate(streamId, {uptime: {stroke_color: osdUptimeStrokecolor.value + 'ff'}});
    });
    osdUptimeStrokecolor.disabled = true;
  }

  const osdUsertextEnabled = $(`#osd${streamId}_usertext_enabled`);
  if (osdUsertextEnabled) {
    osdUsertextEnabled.addEventListener('change', (e) => {
      sendOsdUpdate(streamId, {usertext: {enabled: e.target.checked}});
    });
    osdUsertextEnabled.disabled = true;
  }

  const osdUsertextFormat = $(`#osd${streamId}_usertext_format`);
  if (osdUsertextFormat) {
    osdUsertextFormat.addEventListener('change', () => {
      sendOsdUpdate(streamId, {usertext: {format: osdUsertextFormat.value}});
    });
    osdUsertextFormat.disabled = true;
  }

  const osdUsertextPosition = $(`#osd${streamId}_usertext_position`);
  if (osdUsertextPosition) {
    osdUsertextPosition.addEventListener('change', () => {
      sendOsdUpdate(streamId, {usertext: {position: osdUsertextPosition.value}});
    });
    osdUsertextPosition.disabled = true;
  }

  const osdUsertextFillcolor = $(`#osd${streamId}_usertext_fillcolor`);
  if (osdUsertextFillcolor) {
    osdUsertextFillcolor.addEventListener('change', () => {
      sendOsdUpdate(streamId, {usertext: {fill_color: osdUsertextFillcolor.value + 'ff'}});
    });
    osdUsertextFillcolor.disabled = true;
  }

  const osdUsertextStrokecolor = $(`#osd${streamId}_usertext_strokecolor`);
  if (osdUsertextStrokecolor) {
    osdUsertextStrokecolor.addEventListener('change', () => {
      sendOsdUpdate(streamId, {usertext: {stroke_color: osdUsertextStrokecolor.value + 'ff'}});
    });
    osdUsertextStrokecolor.disabled = true;
  }
});

// Audio controls
function saveAudioValue(param) {
  const el = $('#audio_' + param);
  if (!el) return;
  let value = el.type === 'checkbox' ? el.checked : el.value;

  // Convert numeric strings to numbers for non-format fields
  if (el.type !== 'checkbox' && param !== 'mic_format' && !isNaN(value)) {
    value = Number(value);
  }

  const payload = {audio: {[param]: value}, action: {restart_thread: ThreadAudio}};
  sendToEndpoint(payload);
}

audio_params.forEach(param => {
  const el = $('#audio_' + param);
  if (el) {
    el.addEventListener('change', () => saveAudioValue(param));
    el.disabled = true;
  }

  // Also handle modal slider if it exists
  const slider = $('#audio_' + param + '-slider');
  if (slider) {
    slider.addEventListener('input', ev => {
      // Update the text input while dragging
      if (el) el.value = ev.target.value;
      const sliderValue = $('#audio_' + param + '-slider-value');
      if (sliderValue) sliderValue.textContent = ev.target.value;
    });
    slider.addEventListener('change', () => saveAudioValue(param));
    slider.disabled = true;
  }
});

// Motors config helpers (PTZ tab)
function updateHomingInputs() {
  const homing = $('#homing');
  const x = $('#pos_0_x');
  const y = $('#pos_0_y');
  if (!homing) return;
  const disabled = !homing.checked;
  if (x) x.disabled = disabled;
  if (y) y.disabled = disabled;
}

async function readMotorsPosition() {
  try {
    const res = await fetch('/x/json-motor.cgi?' + new URLSearchParams({ d: 'j' }).toString());
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const { message } = await res.json();
    if (message) {
      if ($('#pos_0_x')) $('#pos_0_x').value = message.xpos;
      if ($('#pos_0_y')) $('#pos_0_y').value = message.ypos;
    }
    if ($('#homing')) $('#homing').checked = true;
    updateHomingInputs();
  } catch (err) {
    console.error('Failed to read motors position', err);
  }
}

$$('.read-motors').forEach(el => {
  el.addEventListener('click', ev => {
    ev.preventDefault();
    readMotorsPosition();
  });
});

$$('.flip_motor').forEach(el => {
  el.addEventListener('click', ev => {
    ev.preventDefault();
    const dir = el.dataset.direction;
    if (!dir) return;
    const base = '#gpio_' + dir + '_';
    const pins = [1,2,3,4].map(i => $(base + i)?.value).reverse();
    [1,2,3,4].forEach((i, idx) => {
      const field = $(base + i);
      if (field && pins[idx] !== undefined) field.value = pins[idx];
    });
  });
});

const homingSwitch = $('#homing');
if (homingSwitch) {
  homingSwitch.addEventListener('change', updateHomingInputs);
  updateHomingInputs();
}

// Image controls (WB and AE)
function saveImageValue(param) {
  const el = $('#image_' + param);
  if (!el) return;

  let value;
  if (el.type === 'checkbox') {
    value = el.checked;
  } else if (el.type === 'select-one') {
    value = parseInt(el.value);
  } else {
    value = parseInt(el.value);
  }

  const payload = {image: {[param]: value}};
  console.log(ts(), 'Sending image param:', param, '=', value);
  sendToEndpoint(payload);
}

const imageParams = ['hflip', 'vflip', 'wb_bgain', 'wb_rgain', 'ae_compensation', 'core_wb_mode'];
imageParams.forEach(param => {
  const el = $('#image_' + param);
  if (el) {
    el.addEventListener('change', () => {
      console.log('Image param changed:', param);
      saveImageValue(param);
    });
    el.disabled = true;
  }
});

// Daynight controls
function saveDayNightValue(param) {
  const el = $('#daynight_' + param);
  if (!el) return;

  let value = el.type === 'checkbox' ? el.checked : el.value;
  if (el.type !== 'checkbox' && !isNaN(value)) {
    value = Number(value);
  }

  const payload = {daynight: {[param]: value}};
  console.log(ts(), 'Sending daynight param:', param, '=', value);
  sendToEndpoint(payload);
}

function saveDayNightControlValue(control) {
  const el = $('#daynight_controls_' + control);
  if (!el) return;

  const payload = {daynight: {controls: {[control]: el.checked}}};
  console.log(ts(), 'Sending daynight control:', control, '=', el.checked);
  sendToEndpoint(payload);
}

const dayNightParams = ['enabled', 'total_gain_night_threshold', 'total_gain_day_threshold'];
dayNightParams.forEach(param => {
  const el = $('#daynight_' + param);
  if (el) {
    el.addEventListener('change', () => {
      console.log('Daynight param changed:', param);
      saveDayNightValue(param);
    });
    // Don't disable - values are loaded server-side from prudynt.json
  }
});

const dayNightControls = ['color', 'ircut', 'ir850', 'ir940', 'white'];
dayNightControls.forEach(control => {
  const el = $('#daynight_controls_' + control);
  if (el) {
    el.addEventListener('change', () => {
      console.log('Daynight control changed:', control);
      saveDayNightControlValue(control);
    });
    // Don't disable - values are loaded server-side from prudynt.json
  }
});

// Tab selector dropdown functionality
const tabSelector = $('#tab-selector');
const tabPanes = {
  'ptz': $('#ptz'),
  'iq': $('#iq'),
  'streamer': $('#streamer'),
  'osd0': $('#osd0'),
  'substream': $('#substream'),
  'osd1': $('#osd1'),
  'audio': $('#audio'),
  'sensor': $('#sensor'),
  'settings': $('#settings'),
  'photosensing': $('#photosensing')
};

function showTab(tabId) {
  // Hide all tab panes
  Object.values(tabPanes).forEach(pane => {
    if (pane) pane.classList.remove('show', 'active');
  });

  // Show selected tab pane
  const selectedPane = tabPanes[tabId];
  if (selectedPane) {
    selectedPane.classList.add('show', 'active');
  }

  // Switch preview based on active tab
  const preview = $('#preview');
  if (preview) {
    if (tabId === 'streamer' || tabId === 'osd0') {
      // Main stream tab or Main stream OSD - switch to ch0
      preview.src = '/x/ch0.mjpg';
    } else {
      // Any other tab (including substream and substream OSD) - switch to ch1
      preview.src = '/x/ch1.mjpg';
    }
  }

  // Save to localStorage
  localStorage.setItem('preview_active_tab', tabId);
}

// Restore active tab from localStorage
const savedTab = localStorage.getItem('preview_active_tab');
if (savedTab && tabSelector) {
  tabSelector.value = savedTab;
  showTab(savedTab);
} else if (tabSelector) {
  // Show first tab by default
  const firstOption = tabSelector.options[0];
  if (firstOption) {
    showTab(firstOption.value);
  }
}

// Handle tab selector change
if (tabSelector) {
  tabSelector.addEventListener('change', event => {
    showTab(event.target.value);
  });
}

// Export configuration button
const exportConfigBtn = $('#export-config');
if (exportConfigBtn) {
  exportConfigBtn.addEventListener('click', () => {
    exportConfigBtn.disabled = true;

    // Open the CGI endpoint which will trigger download
    window.location.href = '/x/json-prudynt-config.cgi';

    // Re-enable button after a short delay
    setTimeout(() => {
      exportConfigBtn.disabled = false;
    }, 1000);
  });
}

// Save configuration button
const saveConfigBtn = $('#save-config');
if (saveConfigBtn) {
  saveConfigBtn.addEventListener('click', async () => {
    if (!confirm('Save the current configuration to /etc/prudynt.json?\n\nThis will overwrite the saved configuration file on the camera.')) {
      return;
    }

    try {
      saveConfigBtn.disabled = true;

      const payload = {action: {save_config: null}};
      const res = await fetch('/x/json-prudynt.cgi', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(payload)
      });

      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();

      if (data.action && data.action.save_config === 'ok') {
        alert('Configuration saved successfully to /etc/prudynt.json');
      } else {
        throw new Error('Save failed');
      }
    } catch (err) {
      console.error('Failed to save config:', err);
      alert('Failed to save configuration: ' + err.message);
    } finally {
      saveConfigBtn.disabled = false;
    }
  });
}

// Restart prudynt button
const restartPrudyntBtn = $('#restart-prudynt');
if (restartPrudyntBtn) {
  restartPrudyntBtn.addEventListener('click', async () => {
    if (!confirm('Restart prudynt service?\n\nThe video stream will be interrupted for a few seconds.')) {
      return;
    }

    try {
      restartPrudyntBtn.disabled = true;

      const res = await fetch('/x/restart-prudynt.cgi', {method: 'GET'});
      if (!res.ok) throw new Error(`HTTP ${res.status}`);

      // Wait for prudynt to restart
      await new Promise(resolve => setTimeout(resolve, 3000));

      alert('Prudynt restarted successfully');
      // Reload the page to refresh all states
      location.reload();
    } catch (err) {
      console.error('Failed to restart prudynt:', err);
      alert('Failed to restart prudynt: ' + err.message);
      restartPrudyntBtn.disabled = false;
    }
  });
}

fetchImagingState();

// Toggle tabs functionality
const toggleTabsBtn = $('#toggle-tabs');
const previewCol = $('#preview-col');
const tabsCol = $('#tabs-col');
const preview = $('#preview');

// Load saved state from localStorage (default: hidden)
const tabsVisible = localStorage.getItem('preview_tabs_visible') === 'true';

function updateTabsVisibility(visible) {
  if (visible) {
    // Showing tabs: hide tabs first, switch to ch1, then show tabs
    tabsCol.classList.remove('d-none');
    //previewCol.classList.remove('col');
    //previewCol.classList.add('col-5');
    preview.src = '/x/ch1.mjpg';
    localStorage.setItem('preview_tabs_visible', visible);
  } else {
    // Hiding tabs: switch to ch0 first, wait for load, then hide tabs
    const newSrc = '/x/ch0.mjpg';
    const onLoad = () => {
      preview.removeEventListener('load', onLoad);
      tabsCol.classList.add('d-none');
      //previewCol.classList.remove('col-5');
      //previewCol.classList.add('col');
    };
    preview.addEventListener('load', onLoad);
    preview.src = newSrc;
    localStorage.setItem('preview_tabs_visible', visible);
  }
}

// Apply saved state if different from default (which is already hidden in HTML)
if (tabsVisible) {
  updateTabsVisibility(true);
}

if (toggleTabsBtn) {
  toggleTabsBtn.addEventListener('click', () => {
    const currentlyVisible = !tabsCol.classList.contains('d-none');
    updateTabsVisibility(!currentlyVisible);
  });
}
</script>

<div class="modal fade" id="mdFont" tabindex="-1" aria-labelledby="mdlFont" aria-hidden="true">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title fs-4" id="mdlFont">Upload font file</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body text-center">
        <form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4" enctype="multipart/form-data">
          <input type="hidden" name="form" value="font">
          <% field_file "fontfile" "Upload a TTF file" %>
          <% button_submit %>
        </form>
      </div>
    </div>
  </div>
</div>

<div class="modal fade" id="mdSensorIQ" tabindex="-1" aria-labelledby="mdlSensorIQ" aria-hidden="true">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title fs-4" id="mdlSensorIQ">Upload sensor IQ file</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body text-center">
        <form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4" enctype="multipart/form-data">
          <input type="hidden" name="form" value="sensor">
          <% field_file "sensorfile" "Upload a sensor IQ binary file" %>
          <% button_submit %>
        </form>
      </div>
    </div>
  </div>
</div>

<div class="modal fade" id="helpModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title">Homing</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <p>During boot, the camera rotates to its minimum limits and zeroes both axes. Disable if you prefer a fixed pose.</p>
        <% wiki_page "Motors" %>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
      </div>
    </div>
  </div>
</div>

<!--
<p>Play RTSP: <span id="playrtsp" class="cb"></span></p>
-->

<%in _footer.cgi %>
