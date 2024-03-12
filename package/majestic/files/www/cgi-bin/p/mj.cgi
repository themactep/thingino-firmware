# line format: parameter|label|units|type|o,p,t,i,o,n,s|placeholder|hint
# number options: min,max,step
# range options: min,max,step[,button]
# select options: value2,value2,value3...

mj="
.audio.codec|Codec for RTSP and MP4 encoding||select|mp3,opus,aac,pcm,alaw,ulaw|opus|
.audio.device|Audio card||string||hw:2|
.audio.enabled|Enable Audio||boolean|true,false|false|
.audio.outputEnabled|Enable audio output||boolean|true,false|false|
.audio.outputGain|Output gain||range|0,31,1|15|
.audio.outputVolume|Speaker volume|%|range|0,100,1|0|
.audio.speakerPinInvert|Audio speaker signal is inverted||boolean|true,false|false|
.audio.speakerPin|GPIO pin of audio speaker||number|1,255,1|32|
.audio.srate|Audio sampling rate|kHz|number|1,96000,1|8000|
.audio.volume|Audio volume level|%|range|1,100,1|50|
.hls.enabled|Enable HTTP Live Streaming (HLS)||boolean|true,false|true|
.isp.blkCnt|Block count||number|1,32,1|1|
.isp.lowDelay|Low delay mode||boolean|true,false|false|May break sophisticated settings.
.isp.memMode|Memory mode||select|normal,reduction|reduction|
.isp.rawMode|Raw feed mode||select|slow,fast,none|none|
.jpeg.enabled|Enable JPEG||boolean|true,false|true|
.jpeg.qfactor|JPEG quality level|%|range|1,100,1|50|
.jpeg.size|Snapshot size|px|string||1920x1080|
.jpeg.toProgressive|Progressive JPEG||boolean|true,false|false|
.motionDetect.debug|Enable debugging||boolean|true,false|true|
.motionDetect.enabled|Enable motion detection||boolean|true,false|false|
.motionDetect.roi|Region of interest (ROI) for motion detection|px|string||0x0x960x1080|
.motionDetect.skipIn|Region excluded from detection|px|string||960x0x960x1080|
.motionDetect.visualize|Visualize motion detection||boolean|true,false|true|
.netip.enabled|Enable NETIP protocol support||boolean|true,false|false|
.netip.ignoreSetTime|Ignore set time||boolean|true,false|false|
.netip.password-plain|NETIP password||password|||Pain-text password, it will be hashed for NETIP.
.netip.password|NETIP password (hash)||hidden||6V0Y4HLF|
.netip.port|NETIP port||number|1,65535,1|34567|
.netip.snapshots|NETIP snaphots||boolean|true,false|true|
.netip.user|NETIP user||string||admin|
.onvif.enabled|Enable ONVIF protocol support||boolean|true,false|false|
.osd.corner|OSD preset position||select|tl:Top Left,tr:Top Right,bl:Bottom Left,br:Bottom Right|br|
.osd.enabled|Enable On-Screen Display (OSD)||boolean|true,false|false|
.osd.font|Path to font file used in OSD||string||/usr/share/fonts/truetype/UbuntuMono-Regular.ttf|
.osd.posX|Horizontal position of OSD|px|number|-2000,2000,2|-100|
.osd.posY|Vertical position of OSD|px|number|-2000,2000,2|-100|
.osd.privacyMasks|Privacy masks|px|string||0x0x234x640,2124x0x468x1300|Coordinates of masked areas separated by commas.
.osd.template|OSD template||string||%a %e %B %Y %H:%M:%S %Z|Supports <a href=\"https://man7.org/linux/man-pages/man3/strftime.3.html \" target=\"_blank\">strftime()</a> format.
.outgoing.enabled|Enable output||boolean|true,false|false|
.outgoing.naluSize|Packet size||number|200,20000,1|1200|
.outgoing.server|Address for outgoing stream||string||udp://192.168.1.10:5600|
.records.enabled|Enable saving records||boolean|true,false|false|
.records.maxUsage|Limit of available space usage|%|range|1,100,1|95|
.records.path|Template for saving video records||string||/mnt/mmc/%Y/%m/%d/%H.mp4|Supports <a href=\"https://man7.org/linux/man-pages/man3/strftime.3.html \" target=\"_blank\">strftime()</a> format.
.records.timelapseFrameRate|Timelapse output file framerate|fps|number|1,100,1|2|in frames per second
.records.timelapseInterval|Timelapse capture interval|sec|number|1,65355,1|5|in seconds
.rtsp.enabled|Enable RTSP||boolean|true,false|true|
.rtsp.port|Port for RTSP protocol||number|1,65535,1|554|rtsp://user:pass@${network_address}:[port]/stream={0,1}
.system.buffer|Maximum buffer size|KB|number||1024|per client
.system.httpsCertificateKey|Path to private SSL key||string||/etc/ssl/private/www.example.com.key|
.system.httpsCertificate|Path to public SSL certificate||string||/etc/ssl/certs/www.example.com.crt|
.system.httpsPort|Port for HTTPS access||number|1,65535,1|443|
.system.logLevel|Severity of logging||select|ERROR,WARN,INFO,DEBUG,TRACE|TRACE|Used for syslog messages.
.system.staticDir|Home directory for static files||string||/var/www/html|
.system.webAdmin|Serve Web Admin via Majestic||boolean|enabled,disabled|disabled|Experimental! Disable on camera with public access.
.system.webPort|Port for HTTP access||number|1,65535,1|80|
.video0.bitrate|Video bitrate|kbps|number|1,68000,1|4096|
.video0.codec|Video0 codec||select|h264,h265|h264|
.video0.crop|Crop video to size|px|string||0x0x960x540|
.video0.enabled|Enable Video0||boolean|true,false|true|
.video0.fps|Video frame rate|fps|number|1,120,1|25|
.video0.gopMode|Group of Pictures (GOP) mode||select|normal,dual,smart|normal|
.video0.gopSize|Send I-frames each 1 second||number|0.1,20,0.1|1|
.video0.rcMode|RC mode||select|avbr,cbr,vbr|avbr|
.video0.size|Video resolution|px|string|1920x1080,1280x720,704x576|1920x1080|
.video0.sliceUnits|Number of slices per frame||number|1,10,1|4
.video1.bitrate|Video1 bitrate|kbps|number|1,68000,1|2048|
.video1.codec|Video1 codec||select|h264,h265|h264|
.video1.crop|Crop video to size|px|string||0x0x960x540|
.video1.enabled|Enable Video1||boolean|true,false|false|
.video1.fps|Video1 frame rate|fps|number|1,60,1|15|
.video1.gopMode|GOP mode||select|normal,dual,smart|normal|
.video1.gopSize|Send I-frame each 1 second||number|1,20,1|1|
.video1.rcMode|RC mode||select|avbr|avbr|
.video1.size|Video1 resolution|px|string|1920x1080,1280x720,704x576|704x576|
.video1.sliceUnits|Number of slices per frame||number|1,10,1|4
.watchdog.enabled|Enable watchdog||boolean|true,false|true|
.watchdog.timeout|Watchdog timeout|sec|number|1,600,1|10|
.youtube.enabled|Enable Youtube support||boolean|true,false|false|
.youtube.key|Youtube API key||string||xxxx-xxxx-xxxx-xxxx-xxxx|
"
