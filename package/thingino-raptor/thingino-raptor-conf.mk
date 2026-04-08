# Raptor configuration patching
# Included from thingino-raptor.mk
#
# String settings: non-empty BR2 value -> uncomment and set in raptor.conf
# Bool settings: _TRUE/_FALSE choice -> set true/false, _DEFAULT -> leave as-is

# Helper: map bool choice to "true", "false", or "" (default = don't touch)
raptor_bval = $(if $(filter y,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_$(1)_TRUE)),true,$(if $(filter y,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_$(1)_FALSE)),false,))

define THINGINO_RAPTOR_PATCH_CONF
	CONF=$(TARGET_DIR)/etc/raptor.conf; \
	rset() { \
		[ -n "$$3" ] && \
		sed -i "/^\[$$1\]/,/^\[/{s|^[# ]*$$2 = .*|$$2 = $$3|;}" "$$CONF" || true; \
	}; \
	\
	rset sensor name "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_NAME))"; \
	rset sensor i2c_addr "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_I2C_ADDR))"; \
	rset sensor i2c_adapter "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_I2C_ADAPTER))"; \
	rset sensor fps "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_FPS))"; \
	rset sensor rst_gpio "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_RST_GPIO))"; \
	rset sensor pwdn_gpio "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_PWDN_GPIO))"; \
	rset sensor power_gpio "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_POWER_GPIO))"; \
	rset sensor boot "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_BOOT))"; \
	rset sensor mclk "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_MCLK))"; \
	rset sensor video_interface "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_VIDEO_INTERFACE))"; \
	rset sensor antiflicker "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_SENSOR_ANTIFLICKER))"; \
	rset sensor low_latency "$(call raptor_bval,SENSOR_LOW_LATENCY)"; \
	\
	rset stream0 width "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_WIDTH))"; \
	rset stream0 height "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_HEIGHT))"; \
	rset stream0 fps "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_FPS))"; \
	rset stream0 codec "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_CODEC))"; \
	rset stream0 profile "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_PROFILE))"; \
	rset stream0 bitrate "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_BITRATE))"; \
	rset stream0 max_bitrate "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_MAX_BITRATE))"; \
	rset stream0 rc_mode "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_RC_MODE))"; \
	rset stream0 gop "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_GOP))"; \
	rset stream0 min_qp "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_MIN_QP))"; \
	rset stream0 max_qp "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_MAX_QP))"; \
	rset stream0 init_qp "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_INIT_QP))"; \
	rset stream0 nr_vbs "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_NR_VBS))"; \
	rset stream0 ivdc "$(call raptor_bval,STREAM0_IVDC)"; \
	rset stream0 osd_enabled "$(call raptor_bval,STREAM0_OSD_ENABLED)"; \
	rset stream0 jpeg "$(call raptor_bval,STREAM0_JPEG)"; \
	rset stream0 jpeg_quality "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_JPEG_QUALITY))"; \
	rset stream0 jpeg_fps "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM0_JPEG_FPS))"; \
	\
	rset stream1 enabled "$(call raptor_bval,STREAM1_ENABLED)"; \
	rset stream1 width "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_WIDTH))"; \
	rset stream1 height "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_HEIGHT))"; \
	rset stream1 fps "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_FPS))"; \
	rset stream1 codec "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_CODEC))"; \
	rset stream1 profile "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_PROFILE))"; \
	rset stream1 bitrate "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_BITRATE))"; \
	rset stream1 max_bitrate "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_MAX_BITRATE))"; \
	rset stream1 rc_mode "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_RC_MODE))"; \
	rset stream1 gop "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_GOP))"; \
	rset stream1 min_qp "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_MIN_QP))"; \
	rset stream1 max_qp "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_MAX_QP))"; \
	rset stream1 init_qp "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_INIT_QP))"; \
	rset stream1 nr_vbs "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_NR_VBS))"; \
	rset stream1 osd_enabled "$(call raptor_bval,STREAM1_OSD_ENABLED)"; \
	rset stream1 jpeg "$(call raptor_bval,STREAM1_JPEG)"; \
	rset stream1 jpeg_quality "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_JPEG_QUALITY))"; \
	rset stream1 jpeg_fps "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_STREAM1_JPEG_FPS))"; \
	\
	rset jpeg enabled "$(call raptor_bval,JPEG_ENABLED)"; \
	rset jpeg quality "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_JPEG_QUALITY))"; \
	rset jpeg fps "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_JPEG_FPS))"; \
	rset jpeg bufshare "$(call raptor_bval,JPEG_BUFSHARE)"; \
	rset jpeg idle "$(call raptor_bval,JPEG_IDLE)"; \
	\
	rset ring main_slots "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RING_MAIN_SLOTS))"; \
	rset ring main_data_mb "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RING_MAIN_DATA_MB))"; \
	rset ring sub_slots "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RING_SUB_SLOTS))"; \
	rset ring sub_data_mb "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RING_SUB_DATA_MB))"; \
	\
	rset audio enabled "$(call raptor_bval,AUDIO_ENABLED)"; \
	rset audio sample_rate "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_SAMPLE_RATE))"; \
	rset audio codec "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_CODEC))"; \
	rset audio opus_complexity "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_OPUS_COMPLEXITY))"; \
	rset audio bitrate "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_BITRATE))"; \
	rset audio volume "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_VOLUME))"; \
	rset audio gain "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_GAIN))"; \
	rset audio device "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_DEVICE))"; \
	rset audio ao_enabled "$(call raptor_bval,AUDIO_AO_ENABLED)"; \
	rset audio ao_volume "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_AO_VOLUME))"; \
	rset audio ao_gain "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_AO_GAIN))"; \
	rset audio ns_enabled "$(call raptor_bval,AUDIO_NS_ENABLED)"; \
	rset audio ns_level "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_NS_LEVEL))"; \
	rset audio hpf_enabled "$(call raptor_bval,AUDIO_HPF_ENABLED)"; \
	rset audio agc_enabled "$(call raptor_bval,AUDIO_AGC_ENABLED)"; \
	rset audio agc_target_dbfs "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_AGC_TARGET_DBFS))"; \
	rset audio agc_compression_db "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_AUDIO_AGC_COMPRESSION_DB))"; \
	\
	rset rtsp enabled "$(call raptor_bval,RTSP_ENABLED)"; \
	rset rtsp port "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_PORT))"; \
	rset rtsp max_clients "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_MAX_CLIENTS))"; \
	rset rtsp endpoint_main "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_ENDPOINT_MAIN))"; \
	rset rtsp endpoint_sub "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_ENDPOINT_SUB))"; \
	rset rtsp username "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_USERNAME))"; \
	rset rtsp password "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_PASSWORD))"; \
	rset rtsp tls "$(call raptor_bval,RTSP_TLS)"; \
	rset rtsp tls_cert "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_TLS_CERT))"; \
	rset rtsp tls_key "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_TLS_KEY))"; \
	rset rtsp session_name "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_SESSION_NAME))"; \
	rset rtsp session_info "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_SESSION_INFO))"; \
	rset rtsp session_timeout "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_SESSION_TIMEOUT))"; \
	rset rtsp tcp_sndbuf "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RTSP_TCP_SNDBUF))"; \
	\
	rset http enabled "$(call raptor_bval,HTTP_ENABLED)"; \
	rset http port "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_HTTP_PORT))"; \
	rset http max_clients "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_HTTP_MAX_CLIENTS))"; \
	rset http username "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_HTTP_USERNAME))"; \
	rset http password "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_HTTP_PASSWORD))"; \
	rset http https "$(call raptor_bval,HTTP_HTTPS)"; \
	rset http cert "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_HTTP_CERT))"; \
	rset http key "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_HTTP_KEY))"; \
	\
	rset osd enabled "$(call raptor_bval,OSD_ENABLED)"; \
	rset osd isp_osd "$(call raptor_bval,OSD_ISP_OSD)"; \
	rset osd font "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_FONT))"; \
	rset osd font_size "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_FONT_SIZE))"; \
	rset osd font_color "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_FONT_COLOR))"; \
	rset osd font_stroke "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_FONT_STROKE))"; \
	rset osd stroke_color "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STROKE_COLOR))"; \
	rset osd time_enabled "$(call raptor_bval,OSD_TIME_ENABLED)"; \
	rset osd time_format "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_TIME_FORMAT))"; \
	rset osd uptime_enabled "$(call raptor_bval,OSD_UPTIME_ENABLED)"; \
	rset osd text_enabled "$(call raptor_bval,OSD_TEXT_ENABLED)"; \
	rset osd text_string "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_TEXT_STRING))"; \
	rset osd privacy_color "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_PRIVACY_COLOR))"; \
	rset osd logo_enabled "$(call raptor_bval,OSD_LOGO_ENABLED)"; \
	rset osd logo_path "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_LOGO_PATH))"; \
	rset osd logo_width "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_LOGO_WIDTH))"; \
	rset osd logo_height "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_LOGO_HEIGHT))"; \
	rset osd stream0_font_size "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STREAM0_FONT_SIZE))"; \
	rset osd stream0_time_pos "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STREAM0_TIME_POS))"; \
	rset osd stream0_uptime_pos "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STREAM0_UPTIME_POS))"; \
	rset osd stream0_text_pos "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STREAM0_TEXT_POS))"; \
	rset osd stream0_logo_pos "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STREAM0_LOGO_POS))"; \
	rset osd stream1_font_size "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STREAM1_FONT_SIZE))"; \
	rset osd stream1_time_pos "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STREAM1_TIME_POS))"; \
	rset osd stream1_uptime_pos "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STREAM1_UPTIME_POS))"; \
	rset osd stream1_text_pos "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STREAM1_TEXT_POS))"; \
	rset osd stream1_logo_pos "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_OSD_STREAM1_LOGO_POS))"; \
	\
	rset ircut enabled "$(call raptor_bval,IRCUT_ENABLED)"; \
	rset ircut mode "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_MODE))"; \
	rset ircut trigger "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_TRIGGER))"; \
	rset ircut night_luma "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_NIGHT_LUMA))"; \
	rset ircut night_gain "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_NIGHT_GAIN))"; \
	rset ircut day_gain_pct "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_DAY_GAIN_PCT))"; \
	rset ircut adc_channel "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_ADC_CHANNEL))"; \
	rset ircut adc_night "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_ADC_NIGHT))"; \
	rset ircut adc_day "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_ADC_DAY))"; \
	rset ircut night_threshold "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_NIGHT_THRESHOLD))"; \
	rset ircut day_threshold "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_DAY_THRESHOLD))"; \
	rset ircut hysteresis_sec "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_HYSTERESIS_SEC))"; \
	rset ircut poll_interval_ms "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_POLL_INTERVAL_MS))"; \
	rset ircut gpio_ircut "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_GPIO_IRCUT))"; \
	rset ircut gpio_ircut2 "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_GPIO_IRCUT2))"; \
	rset ircut gpio_irled "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_IRCUT_GPIO_IRLED))"; \
	\
	rset recording enabled "$(call raptor_bval,RECORDING_ENABLED)"; \
	rset recording mode "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RECORDING_MODE))"; \
	rset recording stream "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RECORDING_STREAM))"; \
	rset recording audio "$(call raptor_bval,RECORDING_AUDIO)"; \
	rset recording segment_minutes "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RECORDING_SEGMENT_MINUTES))"; \
	rset recording storage_path "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RECORDING_STORAGE_PATH))"; \
	rset recording max_storage_mb "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RECORDING_MAX_STORAGE_MB))"; \
	rset recording prebuffer_sec "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RECORDING_PREBUFFER_SEC))"; \
	rset recording clip_length_sec "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RECORDING_CLIP_LENGTH_SEC))"; \
	rset recording clip_max_mb "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_RECORDING_CLIP_MAX_MB))"; \
	\
	rset webrtc enabled "$(call raptor_bval,WEBRTC_ENABLED)"; \
	rset webrtc udp_port "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBRTC_UDP_PORT))"; \
	rset webrtc http_port "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBRTC_HTTP_PORT))"; \
	rset webrtc max_clients "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBRTC_MAX_CLIENTS))"; \
	rset webrtc cert "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBRTC_CERT))"; \
	rset webrtc key "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBRTC_KEY))"; \
	rset webrtc https "$(call raptor_bval,WEBRTC_HTTPS)"; \
	rset webrtc local_ip "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBRTC_LOCAL_IP))"; \
	rset webrtc audio_mode "$(if $(filter y,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBRTC_AUDIO_MODE_AUTO)),auto,$(if $(filter y,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBRTC_AUDIO_MODE_OPUS)),opus,))"; \
	rset webrtc opus_complexity "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBRTC_OPUS_COMPLEXITY))"; \
	rset webrtc opus_bitrate "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBRTC_OPUS_BITRATE))"; \
	\
	rset webcam enabled "$(call raptor_bval,WEBCAM_ENABLED)"; \
	rset webcam device "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBCAM_DEVICE))"; \
	rset webcam jpeg_stream "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBCAM_JPEG_STREAM))"; \
	rset webcam h264_stream "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBCAM_H264_STREAM))"; \
	rset webcam buffers "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBCAM_BUFFERS))"; \
	rset webcam audio "$(call raptor_bval,WEBCAM_AUDIO)"; \
	rset webcam audio_stream "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBCAM_AUDIO_STREAM))"; \
	\
	rset webtorrent enabled "$(call raptor_bval,WEBTORRENT_ENABLED)"; \
	rset webtorrent tracker "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBTORRENT_TRACKER))"; \
	rset webtorrent stun_server "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBTORRENT_STUN_SERVER))"; \
	rset webtorrent stun_port "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBTORRENT_STUN_PORT))"; \
	rset webtorrent tls_verify "$(call raptor_bval,WEBTORRENT_TLS_VERIFY)"; \
	rset webtorrent viewer_url "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBTORRENT_VIEWER_URL))"; \
	rset webtorrent share_key "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_WEBTORRENT_SHARE_KEY))"; \
	\
	rset motion enabled "$(call raptor_bval,MOTION_ENABLED)"; \
	rset motion algorithm "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_MOTION_ALGORITHM))"; \
	rset motion sensitivity "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_MOTION_SENSITIVITY))"; \
	rset motion grid "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_MOTION_GRID))"; \
	rset motion cooldown_sec "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_MOTION_COOLDOWN_SEC))"; \
	rset motion poll_interval_ms "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_MOTION_POLL_INTERVAL_MS))"; \
	rset motion skip_frames "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_MOTION_SKIP_FRAMES))"; \
	rset motion record "$(call raptor_bval,MOTION_RECORD)"; \
	rset motion record_post_sec "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_MOTION_RECORD_POST_SEC))"; \
	rset motion gpio_pin "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_MOTION_GPIO_PIN))"; \
	\
	rset log level "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_LOG_LEVEL))"; \
	rset log target "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_LOG_TARGET))"; \
	rset log file "$(call qstrip,$(BR2_PACKAGE_THINGINO_RAPTOR_CONF_LOG_FILE))"; \
	\
	true
endef
