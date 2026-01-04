#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Recording"

MOUNTS=$(awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab)
RECORD_FILENAME_FB="%Y%m%d/%H/%Y%m%dT%H%M%S"

active_tab=$(echo "$QUERY_STRING" | sed -n 's/.*[?&]tab=\([^&]*\).*/\1/p')
[ -z "$active_tab" ] && active_tab=$(echo "$REQUEST_URI" | sed -n 's/.*[?&]tab=\([^&]*\).*/\1/p')
[ -z "$active_tab" ] && active_tab="$POST_tab"
case "$active_tab" in
  timelapse|video) : ;;
  *) active_tab="video" ;;
esac

########################################
# Video recorder
########################################
vr_domain="recorder"
vr_config_file="/etc/prudynt.json"
vr_temp_config_file="/tmp/${vr_domain}.json"

vr_defaults() {
  default_for vr_autostart "false"
  default_for vr_channel 0
  default_for vr_device_path "$(hostname)/records"
  default_for vr_filename "$RECORD_FILENAME_FB"
  [ "/" = "${vr_filename:0-1}" ] && vr_filename="$RECORD_FILENAME_FB"
  default_for vr_duration 60
  default_for vr_limit 15
}

vr_set_value() {
  [ -f "$vr_temp_config_file" ] || echo '{}' > "$vr_temp_config_file"
  jct "$vr_temp_config_file" set "$vr_domain.$1" "$2" >/dev/null 2>&1
}

vr_get_value() {
  jct "$vr_config_file" get "$vr_domain.$1" 2>/dev/null
}

vr_read_config() {
  [ -f "$vr_config_file" ] || return

  vr_autostart=$(vr_get_value autostart)
  vr_channel=$(vr_get_value channel)
  vr_device_path=$(vr_get_value device_path)
  vr_duration=$(vr_get_value duration)
  vr_filename=$(vr_get_value filename)
  vr_limit=$(vr_get_value limit)
  vr_mount=$(vr_get_value mount)
}

########################################
# Timelapse recorder
########################################
tl_domain="timelapse"
tl_config_file="/etc/timelapse.json"
tl_temp_config_file="/tmp/${tl_domain}.json"

tl_defaults() {
  default_for tl_enabled "false"
  default_for tl_filepath "$(hostname)/timelapses"
  default_for tl_filename "%Y%m%d/%Y%m%dT%H%M%S.jpg"
  default_for tl_interval 1
  default_for tl_keep_days 7
  default_for tl_preset_enabled "false"
  default_for tl_ircut ""
  default_for tl_ir850 ""
  default_for tl_ir940 ""
  default_for tl_white ""
  default_for tl_color ""
}

tl_set_value() {
  [ -f "$tl_temp_config_file" ] || echo '{}' > "$tl_temp_config_file"
  jct "$tl_temp_config_file" set "$tl_domain.$1" "$2" >/dev/null 2>&1
}

tl_get_value() {
  jct "$tl_config_file" get "$tl_domain.$1" 2>/dev/null
}

tl_read_config() {
  [ -f "$tl_config_file" ] || return

  tl_enabled=$(tl_get_value enabled)
  tl_mount=$(tl_get_value mount)
  tl_filepath=$(tl_get_value filepath)
  tl_filename=$(tl_get_value filename)
  tl_interval=$(tl_get_value interval)
  tl_keep_days=$(tl_get_value keep_days)
  tl_preset_enabled=$(tl_get_value preset_enabled)
  tl_ircut=$(tl_get_value ircut)
  tl_ir850=$(tl_get_value ir850)
  tl_ir940=$(tl_get_value ir940)
  tl_white=$(tl_get_value white)
  tl_color=$(tl_get_value color)
}

# Load current config for display
vr_read_config
tl_read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
  case "$POST_form" in
    video)
      error=""

      vr_autostart="$POST_vr_autostart"
      vr_channel="$POST_vr_channel"
      vr_device_path="$POST_vr_device_path"
      vr_duration="$POST_vr_duration"
      vr_filename="$POST_vr_filename"
      vr_limit="$POST_vr_limit"
      vr_mount="$POST_vr_mount"

      vr_defaults

      # normalize
      [ "/" = "${vr_filename:0:1}" ] && vr_filename="${vr_filename:1}"

      # validate
      error_if_empty "$vr_mount" "Record mount cannot be empty."
      error_if_empty "$vr_filename" "Record filename cannot be empty."

      if [ -z "$error" ]; then
        vr_set_value autostart "$vr_autostart"
        vr_set_value channel "$vr_channel"
        vr_set_value device_path "$vr_device_path"
        vr_set_value duration "$vr_duration"
        vr_set_value filename "$vr_filename"
        vr_set_value limit "$vr_limit"
        vr_set_value mount "$vr_mount"

        jct "$vr_config_file" import "$vr_temp_config_file"
        rm "$vr_temp_config_file"

        update_caminfo

        redirect_to "$SCRIPT_NAME?tab=video" "success" "Data updated."
      else
        redirect_to "$SCRIPT_NAME?tab=video" "danger" "Error: $error"
      fi
      ;;

    timelapse)
      error=""

      tl_enabled="$POST_tl_enabled"
      tl_mount="$POST_tl_mount"
      tl_filepath="$POST_tl_filepath"
      tl_filename="$POST_tl_filename"
      tl_interval="$POST_tl_interval"
      tl_keep_days="$POST_tl_keep_days"
      tl_preset_enabled="$POST_tl_preset_enabled"
      tl_ircut="$POST_tl_ircut"
      tl_ir850="$POST_tl_ir850"
      tl_ir940="$POST_tl_ir940"
      tl_white="$POST_tl_white"
      tl_color="$POST_tl_color"

      tl_defaults

      # normalize
      [ "/" = "${tl_filename:0:1}" ] && tl_filename="${tl_filename:1}"

      # validate
      if [ "true" = "$tl_enabled" ]; then
        error_if_empty "$tl_mount" "Timelapse mount cannot be empty."
        error_if_empty "$tl_filename" "Timelapse filename cannot be empty."
      fi

      if [ -z "$error" ]; then
        tl_set_value enabled "$tl_enabled"
        tl_set_value mount "$tl_mount"
        tl_set_value filepath "$tl_filepath"
        tl_set_value filename "$tl_filename"
        tl_set_value interval "$tl_interval"
        tl_set_value keep_days "$tl_keep_days"
        tl_set_value preset_enabled "$tl_preset_enabled"
        tl_set_value ircut "$tl_ircut"
        tl_set_value ir850 "$tl_ir850"
        tl_set_value ir940 "$tl_ir940"
        tl_set_value white "$tl_white"
        tl_set_value color "$tl_color"

        jct "$tl_config_file" import "$tl_temp_config_file"
        rm "$tl_temp_config_file"

        # update crontab
        tmpfile=$(mktemp -u)
        cat $CRONTABS > $tmpfile
        sed -i '/timelapse/d' $tmpfile
        echo "# run timelapse every $tl_interval minutes" >> $tmpfile
        [ "true" = "$tl_enabled" ] || echo -n "#" >> $tmpfile
        echo "*/$tl_interval * * * * timelapse" >> $tmpfile
        mv $tmpfile $CRONTABS

        redirect_to "$SCRIPT_NAME?tab=timelapse" "success" "Data updated."
      else
        redirect_to "$SCRIPT_NAME?tab=timelapse" "danger" "Error: $error"
      fi
      ;;
  esac
fi

# Ensure defaults are present for rendering
vr_defaults
tl_defaults
%>
<%in _header.cgi %>

<ul class="nav nav-tabs mb-3" role="tablist" id="record-tabs">
  <li class="nav-item" role="presentation">
    <button class="nav-link<% [ "video" = "$active_tab" ] && echo -n " active" %>" id="tab-video" data-tab="video" data-bs-toggle="tab" data-bs-target="#pane-video" type="button" role="tab" aria-controls="pane-video" aria-selected="<% [ "video" = "$active_tab" ] && echo -n "true" || echo -n "false" %>">Video recorder</button>
  </li>
  <li class="nav-item" role="presentation">
    <button class="nav-link<% [ "timelapse" = "$active_tab" ] && echo -n " active" %>" id="tab-timelapse" data-tab="timelapse" data-bs-toggle="tab" data-bs-target="#pane-timelapse" type="button" role="tab" aria-controls="pane-timelapse" aria-selected="<% [ "timelapse" = "$active_tab" ] && echo -n "true" || echo -n "false" %>">Timelapse recorder</button>
  </li>
</ul>

<div class="tab-content">
  <div class="tab-pane fade<% [ "video" = "$active_tab" ] && echo -n " show active" %>" id="pane-video" role="tabpanel" aria-labelledby="tab-video" tabindex="0">
    <form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
      <input type="hidden" name="form" value="video">
      <input type="hidden" name="tab" value="video">
      <div class="row row-cols-1 row-cols-md-3">
        <div class="col">
          <% field_select "vr_mount" "Storage mount" "$MOUNTS" "SD card or a network share" %>
          <% field_text "vr_device_path" "Device-specific path" "Helps to deal with multiple devices" %>
          <% field_text "vr_filename" "File name template" "$STR_SUPPORTS_STRFTIME" %>
        </div>
        <div class="col">
          <% field_select "vr_channel" "Stream to record" "0:Main_stream,1:Substream" %>
          <% field_number "vr_duration" "Clip duration" "" "seconds" %>
          <% field_number "vr_limit" "Storage limit" "" "gigabytes" %>
        </div>
        <div class="col">
          <% field_switch "vr_autostart" "Start recording on boot" %>
        </div>
      </div>
      <% button_submit %>
    </form>
  </div>

  <div class="tab-pane fade<% [ "timelapse" = "$active_tab" ] && echo -n " show active" %>" id="pane-timelapse" role="tabpanel" aria-labelledby="tab-timelapse" tabindex="0">
    <form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
      <input type="hidden" name="form" value="timelapse">
      <input type="hidden" name="tab" value="timelapse">
      <div class="row">
        <div class="col col-xl-4">
          <% field_select "tl_mount" "Storage mountpoint" "$MOUNTS" "SD card or a network share" %>
          <% field_text "tl_filepath" "Device-specific path in the storage" "Helps to deal with multiple devices" %>
          <% field_text "tl_filename" "Individual image filename template" "$STR_SUPPORTS_STRFTIME" %>
        </div>
        <div class="col col-xl-4">
          <div class="mb-2 string" id="tl_interval_wrap">
            <label for="tl_interval" class="form-label">Save a snapshot every <input type="text" id="tl_interval" name="tl_interval" class="form-control" style="max-width:4rem;display:inline-block;margin:0 0.25rem" value="<%= $tl_interval %>"> minutes</label>
          </div>
          <div class="mb-2 string" id="tl_keep_days_wrap">
            <label for="tl_keep_days" class="form-label">Keep timelapses of the last <input type="text" id="tl_keep_days" name="tl_keep_days" class="form-control" style="max-width:4rem;display:inline-block;margin:0 0.25rem" value="<%= $tl_keep_days %>"> days</label>
          </div>
        </div>
        <div class="col col-xl-4">
          <% field_switch "tl_enabled" "Launch timelapse recorder on boot" %>
          <div class="card mt-4">
            <div class="card-header">
              <% field_switch "tl_preset_enabled" "Enable snapshot preset" %>
            </div>
            <div class="card-body">
              <p class="small text-muted">When enabled, preset values are applied before each snapshot and restored after. When disabled, snapshots are taken with current settings.</p>
              <div class="row row-cols-1 g-2">
                <div class="col"><% field_switch "tl_ircut" "IR-cut filter" %></div>
                <div class="col"><% field_switch "tl_ir850" "IR LED 850 nm" %></div>
                <div class="col"><% field_switch "tl_ir940" "IR LED 940 nm" %></div>
                <div class="col"><% field_switch "tl_white" "White LED" %></div>
                <div class="col"><% field_switch "tl_color" "Force color mode" %></div>
              </div>
            </div>
          </div>
        </div>
      </div>
      <% button_submit %>
    </form>

    <div class="alert alert-info">
      <p>Use this command on your PC to combine separate still images from the storage directory into a single video file:</p>
      <pre class="cb mb-0">ffmpeg -r 10 -f image2 -pattern_type glob -i '*.jpg' -vcodec libx264 -an timelapse.mp4</pre>
    </div>
  </div>
</div>

<div class="alert alert-dark ui-debug d-none">
  <h4 class="mb-3">Debug info</h4>
  <% ex "jct $vr_config_file get $vr_domain" %>
  <% ex "jct $tl_config_file get $tl_domain" %>
  <% ex "crontab -l" %>
</div>

<script>
(() => {
  // Preserve active tab via URL and hidden form inputs (borrowed from tool-send2)
  $$('#record-tabs button[data-tab]').forEach(btn => {
    btn.addEventListener('shown.bs.tab', ev => {
      const tab = ev.target.dataset.tab;
      const url = new URL(window.location.href);
      url.searchParams.set('tab', tab);
      history.replaceState({}, '', url);
      $$('input[name="tab"]').forEach(hidden => hidden.value = tab);
    });
  });

  // Update File Manager links based on selected mounts
  const vrLink = $('#vr-link-fm');
  if (vrLink) {
    vrLink.addEventListener('click', ev => {
      ev.target.href = 'tool-file-manager.cgi?cd=' + $('#vr_mount').value;
    });
  }

  const tlLink = $('#tl-link-fm');
  if (tlLink) {
    tlLink.addEventListener('click', ev => {
      ev.target.href = 'tool-file-manager.cgi?cd=' + $('#tl_mount').value + '/' + $('#tl_filepath').value;
    });
  }
})();
</script>

<%in _footer.cgi %>
