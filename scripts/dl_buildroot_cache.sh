#!/bin/bash

OWNER="themactep"
REPO="thingino-firmware"

echo "Downloading buildroot-dl cache..."

# Check if the required environment variables are set
if [ -z "$BR2_EXTERNAL" ]; then
	echo "Error: BR2_EXTERNAL environment variable is not set"
	exit 1
fi

if [ -z "$BR2_DL_DIR" ]; then
	echo "Error: BR2_DL_DIR environment variable is not set"
	exit 1
fi

# Get only the first page with most recent releases (limit to 10)
echo "Fetching most recent releases..."
RELEASES_INFO=$(curl -s "https://api.github.com/repos/$OWNER/$REPO/releases?per_page=10")

# Extract tag names that contain "update_cache"
UPDATE_CACHE_TAGS=$(echo "$RELEASES_INFO" | grep -o '"tag_name": *"update_cache[^"]*"' | cut -d'"' -f4)

# Get the most recent update_cache tag (should be first in the list)
LATEST_UPDATE_CACHE_TAG=$(echo "$UPDATE_CACHE_TAGS" | head -1)

if [ -n "$LATEST_UPDATE_CACHE_TAG" ]; then
	echo "Found update_cache tag: $LATEST_UPDATE_CACHE_TAG"
	DOWNLOAD_URL="https://github.com/$OWNER/$REPO/releases/download/$LATEST_UPDATE_CACHE_TAG/buildroot-dl-cache.zip.001"

	# Create download path in BR2_EXTERNAL
	DOWNLOAD_PATH="$BR2_EXTERNAL/buildroot-dl-cache.zip.001"

	echo "Downloading to: $DOWNLOAD_PATH"
	curl -L -o "$DOWNLOAD_PATH" "$DOWNLOAD_URL"

	# Check if download was successful
	if [ $? -ne 0 ]; then
		echo "Download failed"
		exit 1
	fi

	echo "Download complete"

	# Check if BR2_DL_DIR exists
	if [ ! -d "$BR2_DL_DIR" ]; then
		echo "Creating directory: $BR2_DL_DIR"
		mkdir -p "$BR2_DL_DIR"

		# Check if directory creation was successful
		if [ $? -ne 0 ]; then
			echo "Failed to create directory: $BR2_DL_DIR"
			exit 1
		fi
	fi

	# Extract the zip file to BR2_DL_DIR
	echo "Extracting to: $BR2_DL_DIR"
	unzip -oj "$DOWNLOAD_PATH" -d "$BR2_DL_DIR"

	# Check if extraction was successful
	if [ $? -ne 0 ]; then
		echo "Extraction failed"
		exit 1
	fi

	echo "Extraction complete"

	rm "$DOWNLOAD_PATH"
	echo "Temporary download file removed"

	echo "Process completed successfully"
else
	echo "Failed to find any update_cache release tags in the most recent releases"
	exit 1
fi
