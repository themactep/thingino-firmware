#!/bin/bash

# Initialize empty arrays for the menu items from each directory
CAMERAS_ITEMS=()
MODULES_ITEMS=()
EXPERIMENTAL_ITEMS=()

# Define a function to read items from a directory
read_items() {
    local path="$1"
    local -n items_ref=$2  # Use a nameref for indirect variable reference in bash 4.3+
    while IFS= read -r file; do
        items_ref+=("$(basename "$file")" "")
    done < <(find "$path" -type f ! -path "*/github/*")
}

# Populate arrays with items from each directory
read_items ./configs/cameras CAMERAS_ITEMS
read_items ./configs/modules MODULES_ITEMS
read_items ./configs/testing EXPERIMENTAL_ITEMS

# Combine all items into one MENU_ITEMS array and add custom items
MENU_ITEMS=("*----- CAMERAS ---------------------------*" "" "${CAMERAS_ITEMS[@]}" "*----- MODULES ---------------------------*" "" "${MODULES_ITEMS[@]}" "*----- EXPERIMENTAL CONFIGS --------------*" "" "${EXPERIMENTAL_ITEMS[@]}")

# Check if we found any items
if [ ${#MENU_ITEMS[@]} -eq 0 ]; then
    echo "No configuration files found."
    exit 1
fi

# Display the menu with dialog
dialog --title "Configuration Files" --menu "Select a configuration file:" 18 110 30 "${MENU_ITEMS[@]}"
