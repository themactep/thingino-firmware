#!/bin/sh
config_file=/etc/telegrambot.json
if [ "$REQUEST_METHOD" = "POST" ]; then
	cl=${CONTENT_LENGTH:-0}
	json=$(head -c "$cl")
	printf '%s' "$json" > $config_file
fi

echo "Content-Type: application/json"
echo
cat $config_file

