#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Save Locally"

defaults() {
  default_for "save_dir" "/mnt/records"
  default_for "save_template" "${network_hostname}-%Y%m%d-%H%M%S"
  default_for "save_send_video" "false"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
  error=""

  # read posted values
  read_from_post "save" "dir template send_video"

  # only validate if enabled
  [ -z "$save_dir" ] && error="Local directory cannot be empty."

  defaults

  if [ -z "$error" ]; then
    save2config "
save_dir=\"$save_dir\"
save_template=\"$save_template\"
save_send_video=\"$save_send_video\"
"
    redirect_to $SCRIPT_NAME "success" "Data updated."
  else
    redirect_to $SCRIPT_NAME "danger" "Error: $error"
  fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
  <div class="row row-cols-1 row-cols-md-2">
    <div class="col">
      <% field_text "save_dir" "Local directory" "Absolute path to save files" %>
      <% field_text "save_template" "Filename template" "$STR_SUPPORTS_STRFTIME" "without extension" %>
    </div>
    <div class="col">
      <% field_radio "save_send_video" "Save video buffer instead of snapshot" %>
    </div>
  </div>
  <% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Save Now" data-sendto="savelocal">Test</button>

<div class="alert alert-dark ui-debug d-none">
  <h4 class="mb-3">Debug info</h4>
  <% ex "grep ^save_ $CONFIG_FILE" %>
</div>

<%in _footer.cgi %>
