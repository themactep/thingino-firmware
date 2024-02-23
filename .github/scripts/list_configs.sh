#!/bin/bash
cd configs || exit

# Array of strings to exclude
exclude_patterns=("t23" "n23" "toolchain")

# Build the grep pattern to exclude files
exclude_pattern=$(printf "|%s" "${exclude_patterns[@]}")
exclude_pattern=${exclude_pattern:1} # Remove the leading '|'

# List .defconfig files that do not start with an underscore, do not contain excluded strings, and strip the _defconfig suffix
for file in $(ls | grep -v '^_' | grep -vE "${exclude_pattern}" | grep '_defconfig'); do
    echo "${file%_defconfig}"
done
