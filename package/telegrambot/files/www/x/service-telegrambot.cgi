#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Telegram Bot"
%>
<%in _header.cgi %>

<form action="" method="post" class="mb-4">
<% field_switch "tb_enabled" "Enable Telegram Bot" %>
<div class="row mb-3">
<div class="col col-lg-6">
<% field_text "tb_token" "Bot Token" "click <span class=\"link\" data-bs-toggle=\"modal\" data-bs-target=\"#helpModal\">here</span> for help" %>
<% field_text "tb_users" "Respond only to these users" "whitespace separated list" %>
</div>
</div>
<div class="bot-commands mb-4">
<h5>Bot Commands</h5>
<p class="hint mb-3">Use $chat_id variable for the active chat ID.</p>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $CONFIG_FILE print" %>
</div>

<script src="/a/telegrambot-ui.js"></script>
<%in _tg_bot.cgi %>
<%in _footer.cgi %>
