#!/bin/bash

#
# Thingino Configuration Generator
#
# This script generates the /etc/thingino.json file by merging multiple
# configuration sources with proper key override behavior.
#
# Usage: thingino_config_gen.sh <output_file> <br2_external> <camera_subdir> <camera>
#

# Check arguments
if [ $# -ne 4 ]; then
	echo "Usage: $0 <output_file> <br2_external> <camera_subdir> <camera>"
	echo "  output_file  - Path to the output thingino.config file"
	echo "  br2_external - Path to BR2_EXTERNAL directory"
	echo "  camera_subdir - Camera subdirectory (e.g., configs/cameras)"
	echo "  camera       - Camera name"
	exit 1
fi

OUTPUT_FILE="$1"
BR2_EXTERNAL="$2"
CAMERA_SUBDIR="$3"
CAMERA="$4"

# Function to escape JSON strings
json_escape() {
	local raw="$1"
	raw=${raw//\\/\\\\}
	raw=${raw//\"/\\\"}
	raw=${raw//$'\n'/\\n}
	raw=${raw//$'\r'/\\r}
	raw=${raw//$'\t'/\\t}
	echo "$raw"
}

# Function to merge config files with proper key override behavior
merge_config_files() {
	local output_file="$1"
	shift
	local config_files=("$@")

	# Use associative array to track key-value pairs
	declare -A config_vars

	# Process each config file in order
	for config_file in "${config_files[@]}"; do
		if [ -f "$config_file" ]; then
			echo "Processing config file: $config_file" >&2
			while IFS= read -r line; do
				# Skip comments and empty lines
				if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
					continue
				# Handle key=value pairs
				elif [[ "$line" =~ ^[[:space:]]*([^=]+)=(.*)$ ]]; then
					local key="${BASH_REMATCH[1]}"
					local value="${BASH_REMATCH[2]}"
					# Remove leading/trailing whitespace from key
					key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
					value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
					# Strip surrounding quotes if present
					if [[ "$value" =~ ^\".*\"$ ]]; then
						value="${value:1:-1}"
						# Unescape any escaped quotes within the value
						value=${value//\\"/"}
					fi
					# Store the key-value pair (later files override earlier ones)
					config_vars["$key"]="$value"
					echo "  Set: $key=$value" >&2
				fi
			done < "$config_file"
		else
			echo "Config file not found: $config_file" >&2
		fi
	done

	# Write the merged configuration as JSON
	{
		echo "{"
		local keys=($(printf '%s\n' "${!config_vars[@]}" | sort))
		local total=${#keys[@]}
		local index=0
		local value escaped
		for key in "${keys[@]}"; do
			value="${config_vars[$key]}"
			escaped=$(json_escape "$value")
			printf '  "%s": "%s"' "$key" "$escaped"
			index=$((index + 1))
			if [ "$index" -lt "$total" ]; then
				printf ',\n'
			else
				printf '\n'
			fi
		done
		echo "}"
	} > "$output_file"

	echo "Generated config with ${#config_vars[@]} keys" >&2
}

# Create a temporary file for merging configurations
TEMP_CONFIG=$(mktemp)

# Prepare list of config files in priority order (lowest to highest)
CONFIG_FILES=(
	"${BR2_EXTERNAL}/configs/common.config"
	"${BR2_EXTERNAL}/${CAMERA_SUBDIR}/${CAMERA}/${CAMERA}.config"
)

# Add local.config if it exists
if [ -f "${BR2_EXTERNAL}/configs/local.config" ]; then
	CONFIG_FILES+=("${BR2_EXTERNAL}/configs/local.config")
fi

echo "Generating thingino.json..." >&2
echo "Output file: $OUTPUT_FILE" >&2
echo "Config files to merge:" >&2
for config_file in "${CONFIG_FILES[@]}"; do
	echo "  - $config_file" >&2
done

# Merge all configuration files
merge_config_files "$TEMP_CONFIG" "${CONFIG_FILES[@]}"

# Copy the merged config to the final location with restrictive permissions
install -m 0600 "$TEMP_CONFIG" "$OUTPUT_FILE"

# Clean up temporary file
rm "$TEMP_CONFIG"

echo "Successfully generated $OUTPUT_FILE" >&2
