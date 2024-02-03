#!/bin/sh

plugin="telegrambot"

if [ -z "$(command -v jsonfilter)" ]; then
	echo "${plugin} is not supported on this platform, missing jsonfilter."
	exit 99
fi

. /usr/sbin/common-plugins
singleton

[ "true" != "$telegrambot_enabled" ] &&
	log "Telegram Bot is not enabled in ${CONFIG_FILE}." &&
	quit_clean 10

data_file="/tmp/${plugin}.json"
offset_file="/tmp/${plugin}_offset"
offset_file_backup="/etc/webui/${plugin}_offset"

IFS_ORIG=$IFS
API_URL="https://api.telegram.org/bot${telegrambot_token}"

### Build command menu and keyboards

bot_commands="["
bot_keyboard="{\"keyboard\":[["
bot_inline_keyboard="{\"inline_keyboard\":[["

for i in 0 1 2 3 4 5 6 7 8 9; do
	_c=$(eval "echo \"\$telegrambot_command_$i\"")
	if [ -n "$_c" ]; then
		_d=$(eval "echo \"\$telegrambot_description_$i\"")
		_s=$(eval "echo \"\$telegrambot_script_$i\"")
		bot_commands="${bot_commands}{\"command\":\"${_c}\",\"description\":\"${_d}\"},"
		bot_keyboard="${bot_keyboard}\"/${_c}\","
		bot_inline_keyboard="${bot_inline_keyboard}{\"text\":\"${_c}\",\"callback_data\":\"${_s}\"},"
		unset _d; unset _s
	fi; unset _c
done; unset i

bot_commands="${bot_commands}{\"command\":\"help\",\"description\":\"Help\"}]"
bot_keyboard="${bot_keyboard}\"/help\"]],\"one_time_keyboard\":true,\"resize_keyboard\":true}"
bot_inline_keyboard="${bot_inline_keyboard}{\"text\":\"help\",\"callback_data\":\"help.sh\"}]],\"one_time_keyboard\":true,\"resize_keyboard\":true}"

### Common methods

dump_data() {
	log "DATA: $(cat $data_file)" 37
}

save_offset() {
	if [ -f "$offset_file" ]; then
		log "Save offset file to permanent storage."
		cp "$offset_file" "$offset_file_backup"
		sync
		sleep 1
	else
		log "Offset file ${offset_file} not found."
	fi
}

restore_offset() {
	if [ -f "$offset_file_backup" ]; then
		log "Restore offset file from permanent storage."
		cp "$offset_file_backup" "$offset_file"
	else
		log "Offset file backup not found in permanent storage."
	fi
}

#### Telegram API

api_call() {
	log $1 32
	cmd="curl --silent --request POST --url \"${API_URL}/${1}\" --header \"Content-Type: application/json\" --data '${2}' $3"
	log_and_run "$cmd"
}

### Bot actions

get_me() {
	api_call "getMe" "{\"timeout\":5}" "--output ${data_file}"
	ME="@$(jsonfilter -i $data_file -e "$.result.username")"
	log "Starting Telegram Bot ${ME}." 35
}

# leave_chat "chat_id"
leave_chat() {
	api_call "leaveChat" "{\"chat_id\":\"$1\"}"
}

### Commands menu

get_my_commands() {
	api_call "getMyCommands"
}

delete_my_commands() {
	api_call "deleteMyCommands"
}

set_my_commands() {
	api_call "setMyCommands" "{\"commands\":$bot_commands}"
}

set_chat_menu_button() {
	api_call "setChatMenuButton" "{\"menu_button\":'{\"type\":\"commands\"}'}"
}

# show_menu "chat_id"
show_menu() {
	local data="{\"chat_id\":\"$1\",\"text\":\"Here you go\""
#	[ -n "$2" ] && data="${data},\"reply_to_message_id\":\"$2\""
	case "$chat_type" in
	"private")
		#data="${data},\"reply_markup\":${bot_keyboard}"
		data="${data},\"reply_markup\":${bot_inline_keyboard}"
		;;
	"channel")
		#data="${data},\"reply_markup\":${bot_keyboard}"
		data="${data},\"reply_markup\":${bot_inline_keyboard}"
		;;
	"group")
		#data="${data},\"reply_markup\":${bot_keyboard}"
		data="${data},\"reply_markup\":${bot_inline_keyboard}"
		;;
	"supergroup")
		#data="${data},\"reply_markup\":${bot_keyboard}"
		data="${data},\"reply_markup\":${bot_inline_keyboard}"
		;;
	esac
	data="${data}}"
	api_call "sendMessage" "$data"
}

### Updates

get_updates() {
	local offset=0
	[ -f "$offset_file" ] && offset=$(cat $offset_file)

	# Available types of update:
	# - message
	# - edited_message
	# - channel_post
	# - edited_channel_post
	# - inline_query
	# - chosen_inline_result
	# - callback_query
	# - shipping_query
	# - pre_checkout_query
	# - poll
	# - poll_answer
	# - my_chat_member
	# - chat_member
	# - chat_join_request

	local data="{\"offset\":\"${offset}\",\"timeout\":5,\"allowed_updates\":[\"message\",\"channel_post\"]}"
	api_call "getUpdates" "$data" "--output ${data_file}"
}

# send_message "chat_id" "message text" "reply_to_message"
send_message() {
	local data="{\"chat_id\":\"$1\",\"text\":\"$2\""
	[ -n "$3" ] && data="${data},\"reply_to_message_id\":\"$3\""
	data="${data}}"
	api_call "sendMessage" "$data"
}

# delete_message "chat_id" "message_id"
delete_message() {
	local data="{\"chat_id\":\"$1\",\"message_id\":\"$2\"}"
	api_call "deleteMessage" "$data"
}

tgb_readfromapi() {
	local cmd="jsonfilter -s \"$updates\" -e \"$.result[@.update_id=$update_id].message.chat.id\""
	log_and_run "$cmd"
}

### Logics

restore_offset

get_me
delete_my_commands
set_my_commands
get_my_commands
set_chat_menu_button

while [ true ]; do
	get_updates
	dump_data

	status=$(jsonfilter -i $data_file -e "$.ok")
	if [ "true" = "$status" ]; then
		update_ids=$(jsonfilter -i $data_file -e "$.result[*].update_id")
		if [ -z "$update_ids" ]; then
			log "No new messages."
		else
			log "Found new messages: ${update_ids}."

			for update_id in $update_ids; do
				log "Processing message ${update_id}."

				log "Saving pointer $((update_id + 1)) to $offset_file."
				echo $((update_id + 1)) >$offset_file

				if [ -z "$(jsonfilter -i $data_file -e "$.result[@.update_id=$update_id].*.entities")" ]; then
					log "Message ${update_id} has no entities."
					continue
				fi

				jsonfilter -i $data_file -e "$.result[@.update_id=$update_id].*.entities[*]" > /tmp/entities.json
				log "Message ${update_id} has entities: $(cat /tmp/entities.json)"

				IFS=$'\n'
				entities=$(cat /tmp/entities.json);
				for entity in $entities; do
					chat_id=$(jsonfilter -i ${data_file} -e "$.result[@.update_id=$update_id].*.chat.id")
					chat_type=$(jsonfilter -i ${data_file} -e "$.result[@.update_id=$update_id].*.chat.type")
					message_id=$(jsonfilter -i ${data_file} -e "$.result[@.update_id=$update_id].*.message_id")
					message_text=$(jsonfilter -i ${data_file} -e "$.result[@.update_id=$update_id].*.text")

					# Available entity types:
					# - mention (@username)
					# - hashtag (#hashtag)
					# - cashtag ($USD)
					# - bot_command (/start@jobs_bot)
					# - url (https://telegram.org)
					# - email (do-not-reply@telegram.org)
					# - phone_number (+1-212-555-0123)
					# - bold (bold text)
					# - italic (italic text)
					# - underline (underlined text)
					# - strikethrough (strikethrough text)
					# - spoiler (spoiler message)
					# - code (monowidth string)
					# - pre (monowidth block)
					# - text_link (for clickable text URLs)
					# - text_mention” (for users without usernames)
					# - custom_emoji (for inline custom emoji stickers)

					message_type=$(jsonfilter -s "${entity}" -e "$.type")
					if [ "bot_command" = "$message_type" ]; then
						_o=$(jsonfilter -s "${entity}" -e "$.offset")
						_l=$(jsonfilter -s "${entity}" -e "$.length")
						bot_command="${message_text:$_o:$_l}"
						log "BOT COMMAND: ${bot_command}" 31
						unset _l; unset _o

						# split command by '@' to $command and $mention
						mention=${bot_command##*@}
						if [ "$bot_command" = "$mention" ]; then
							log "Command ${bot_command} is global."
							unset mention
						else
							bot_command=${bot_command%%@*}
							if [ -n "$mention" ] && [ "$ME" != "@${mention}" ]; then
								log "Command ${bot_command} is not for ${ME} but for ${mention}."
								unset mention
								unset bot_command
							fi
						fi
					fi
				done
				IFS=$IFS_ORIG

				if [ -n "$bot_command" ]; then
					[ "reboot" = "$bot_command" ] && save_offset

					casecmd="case \"\$bot_command\" in "
					for i in 0 1 2 3 4 5 6 7 8 9; do
						eval _c="\$telegrambot_command_$i"
						eval _s="\$telegrambot_script_$i"
						[ -n "$telegrambot_command_$i" ] && casecmd="${casecmd}\"/$_c\") script='$_s' ;;"
						unset _c; unset _s
					done
					casecmd="${casecmd}*) message=\"Command \$bot_command not found.\" ;;"
					casecmd="${casecmd}esac;"
					eval $casecmd

					if [ -n "$script" ]; then
						log "SCRIPT: ${script}" 35
						message=$(eval $script)
					fi
					# sanitize doublequotes
					message=${message//\"/\\\"}
					# reply only if script produced an output
					[ -n "$message" ] && send_message "$chat_id" "$message" "$message_id"
				fi

				# clean up
				unset bot_command; unset chat_id; unset chat_type; unset mention
				unset message_id; unset message_text; unset message_type; unset url
				unset message; unset script; unset casecmd
			done
		fi
	fi

	sleep 1
done

exit 0
