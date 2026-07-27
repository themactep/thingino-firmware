#!/usr/bin/awk -f

# Function to trim leading and trailing whitespace from a string
function trim(s) {
	gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
	return s
}

# Function to handle going down a level
function goDownLevel(level, line) {
	gsub(/:[[:space:]]*{[[:space:]]*$/, "", line)
	level = (level ? level "." : "") line
	return level
}

# Function to handle going up a level
function goUpLevel(level) {
	split(level, keyArray, ".")
	return (length(keyArray) > 1 ? substr(level, 1, length(level) - length(keyArray[length(keyArray)]) - 1) : "")
}

BEGIN {
	# Check for the correct number of arguments
	if (ARGC != 3) {
		print "Usage: " ARGV[0] " <device_config_file> <global_config_file>"
		exit 1
	}

	deviceFile = ARGV[1]
	globalFile = ARGV[2]

	# Track key-value pairs from device config
	level = ""
	while ((getline < deviceFile) > 0) {
		line = trim($0)

		# Handle nested objects
		if (line ~ /[[:space:]]*{[[:space:]]*$/) {
			level = goDownLevel(level, line)
		} else if (line ~ /^[[:space:]]*}/) {
			level = goUpLevel(level)
		} else if (line ~ /^[^[:space:]]+:[[:space:]]*[^[:space:]]+/) {
			split(line, kv, ":")
			key = trim(kv[1])
			value = trim(kv[2])
			keyPath = (level ? level "." : "") key
			config[keyPath] = value
		}
	}
	close(deviceFile)

	# Process global config with substitutions
	level = ""
	while ((getline < globalFile) > 0) {
		line = $0
		leading_whitespace = ""

		# Capture leading whitespace
		match(line, /^[[:space:]]*/)
		leading_whitespace = substr(line, RSTART, RLENGTH)

		# Strip whitespace and leading comments
		clean = trim(line)
		gsub(/^#[[:space:]]*/, "", clean)

		# Handle nested objects
		if (clean ~ /[[:space:]]*{[[:space:]]*$/) {
			level = goDownLevel(level, clean)
		} else if (clean ~ /^[[:space:]]*}/) {
			level = goUpLevel(level)
		} else if (clean ~ /^[^[:space:]]+:[[:space:]]*[^[:space:]]+/) {
			split(clean, kv, ":")
			key = trim(kv[1])
			value = trim(kv[2])
			keyPath = (level ? level "." : "") key

			# Perform substitution if key exists in the device config
			if (keyPath in config) {
				sub(/:[[:space:]]*[^[:space:]]+/, ": " config[keyPath], line)

				# Remove leading comment from the line
				gsub(/^[[:space:]]*#[[:space:]]*/, leading_whitespace, line)
			}
		}

		# Print the line with leading whitespace preserved
		print line
	}
	close(globalFile)
}
