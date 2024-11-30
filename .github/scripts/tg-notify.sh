#!/bin/bash

SILENT=false
if [ "$1" == "-s" ]; then
    SILENT=true
    shift
fi

if [ $# -lt 4 ]; then
	echo "Usage: $0 <TG_TOKEN> <TG_CHANNEL> [TG_TOPIC] <MESSAGE_TYPE> [options]"
	echo "MESSAGE_TYPE: start | finish | completed | error"
	echo
	echo "Options:"
	echo "  start <BUILD_NAME> <JOB_ID> <REPOSITORY>"
	echo "      Send a 'build started' message."
	echo
	echo "  finish <BUILD_NAME> <ELAPSED_TIME> <JOB_ID> <REPOSITORY>"
	echo "      Send a 'build completed' message with elapsed time."
	echo
	echo "  completed <BUILD_NAME> <JOB_ID> <REPOSITORY> <COMMIT_HASH> <BRANCH> <TAG_NAME> <TIME> <FILE_PATH>"
	echo "      Send a 'build completed with binaries' message, optionally attaching a file."
	echo
	echo "  error <BUILD_NAME> <ERROR_MESSAGE> <JOB_ID> <REPOSITORY>"
	echo "      Send a 'build failed' message."
	exit 1
fi

# Arguments
TG_TOKEN="$1"
TG_CHANNEL="$2"

if [[ "$3" =~ ^(start|finish|completed|error)$ ]]; then
	TG_TOPIC=""
	MESSAGE_TYPE="$3"
	BUILD_NAME="$4"
	shift 4
else
	TG_TOPIC="$3"
	MESSAGE_TYPE="$4"
	BUILD_NAME="$5"
	shift 5
fi

# Default Options
TG_OPTIONS="$([ "$SILENT" == true ] && echo '-s -o /dev/null' || echo '')"
API_URL="https://api.telegram.org/bot${TG_TOKEN}"

# Escape MarkdownV2 special characters
escape_markdown() {
	local text="$1"
	echo -e "$text" | sed -E \
		-e 's/\\/\\\\/g' \
		-e 's/\*/\\*/g' \
		-e 's/_/\\_/g' \
		-e 's/\{/\\{/g' \
		-e 's/\}/\\}/g' \
		-e 's/#/\\#/g' \
		-e 's/\+/\\+/g' \
		-e 's/-/\\-/g' \
		-e 's/\./\\./g' \
		-e 's/!/\\!/g' \
		-e 's/\|/\\|/g' \
		-e 's/>/\\>/g' \
		-e 's/=/\\=/g' \
		-e 's/`/\\`/g' \
		-e 's/~/\\~/g' \
		-e 's/</\\</g' \
		-e 's/\$/\\\$/g' \
		-e 's/:/\\:/g'
}

send_message() {
	local message="$1"
	local topic="$2"

	if [ -n "$topic" ]; then
		curl $TG_OPTIONS -H "Content-Type: multipart/form-data" -X POST "$API_URL/sendMessage" \
			-F parse_mode=MarkdownV2 \
			-F message_thread_id="$topic" \
			-F chat_id="$TG_CHANNEL" \
			-F text="$message" \
			-F disable_web_page_preview=true
	else
		curl $TG_OPTIONS -H "Content-Type: multipart/form-data" -X POST "$API_URL/sendMessage" \
			-F parse_mode=MarkdownV2 \
			-F chat_id="$TG_CHANNEL" \
			-F text="$message" \
			-F disable_web_page_preview=true
	fi
}

send_file() {
	local message="$1"
	local topic="$2"
	local file_path="$3"

	if [ -n "$topic" ]; then
		curl $TG_OPTIONS -H "Content-Type: multipart/form-data" -X POST \
			"$API_URL/sendDocument" \
			-F parse_mode=MarkdownV2 \
			-F chat_id="$TG_CHANNEL" \
			-F message_thread_id="$topic" \
			-F caption="$message" \
			-F document=@"$file_path" \
			-F disable_web_page_preview=true
	else
		curl $TG_OPTIONS -H "Content-Type: multipart/form-data" -X POST \
			"$API_URL/sendDocument" \
			-F parse_mode=MarkdownV2 \
			-F chat_id="$TG_CHANNEL" \
			-F caption="$message" \
			-F document=@"$file_path" \
			-F disable_web_page_preview=true
	fi
}

# Message Types
case "$MESSAGE_TYPE" in
	start)
		JOB_ID="$1"
		REPOSITORY="$2"
		JOB_LINK="https://github.com/${REPOSITORY}/actions/runs/${JOB_ID}"
		MESSAGE="${BUILD_NAME} build started:\nJob: [${JOB_ID}](${JOB_LINK})\n\n🚦 GitHub Actions"
		MESSAGE=$(escape_markdown "$MESSAGE")
		send_message "$MESSAGE" "$TG_TOPIC"
		;;
	finish)
		ELAPSED="$1"
		JOB_ID="$2"
		REPOSITORY="$3"
		JOB_LINK="https://github.com/${REPOSITORY}/actions/runs/${JOB_ID}"
		MESSAGE="${BUILD_NAME} build completed:\nTotal elapsed time: ${ELAPSED}\nJob: [${JOB_ID}](${JOB_LINK})\n\n🚩 GitHub Actions"
		MESSAGE=$(escape_markdown "$MESSAGE")
		send_message "$MESSAGE" "$TG_TOPIC"
		;;
	completed)
		JOB_ID="$1"
		REPOSITORY="$2"
		COMMIT_HASH="$3"
		BRANCH="$4"
		TAG_NAME="$5"
		TIME="$6"
		FILE_PATH="$7"

		JOB_LINK="https://github.com/${REPOSITORY}/actions/runs/${JOB_ID}"
		COMMIT_LINK="https://github.com/${REPOSITORY}/commit/${COMMIT_HASH}"
		BRANCH_LINK="https://github.com/${REPOSITORY}/tree/${BRANCH}"
		TAG_LINK="https://github.com/${REPOSITORY}/releases/tag/${TAG_NAME}"

		MESSAGE="Commit: [${COMMIT_HASH}](${COMMIT_LINK})\nBranch: [${BRANCH}](${BRANCH_LINK})\nTag: [${TAG_NAME}](${TAG_LINK})\nTime: ${TIME}\nJob: [${JOB_ID}](${JOB_LINK})\n\n✅ GitHub Actions"
		MESSAGE=$(escape_markdown "$MESSAGE")

		if [ -f "$FILE_PATH" ]; then
			send_file "$MESSAGE" "$TG_TOPIC" "$FILE_PATH"
		else
			send_message "$MESSAGE" "$TG_TOPIC"
		fi
		;;
	error)
		ERROR_MESSAGE="$1"
		JOB_ID="$2"
		REPOSITORY="$3"
		JOB_LINK="https://github.com/${REPOSITORY}/actions/runs/${JOB_ID}"
		MESSAGE="${BUILD_NAME} build failed:\nError: ${ERROR_MESSAGE}\nJob: [${JOB_ID}](${JOB_LINK})\n\n❌ GitHub Actions"
		MESSAGE=$(escape_markdown "$MESSAGE")
		send_message "$MESSAGE" "$TG_TOPIC"
		;;
	*)
		echo "Unknown MESSAGE_TYPE: $MESSAGE_TYPE"
		exit 1
		;;
esac
