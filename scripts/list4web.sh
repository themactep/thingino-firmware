#!/bin/bash

GH_URL_BASE="https://github.com/themactep/thingino-firmware/releases/latest/download"

CAMERA_DIRS=$(realpath $(dirname $0)/../configs/cameras/)
CAMERA_CONFIGS=$(ls -1 $CAMERA_DIRS | sort)

echo -e "Supported Hardware\n==================\n
Full list of supported cameras by brand, model, and hardware
variants linked to the latest Thingino firmware release."

for config_name in $CAMERA_CONFIGS; do
	config_path=${CAMERA_DIRS}/${config_name}/${config_name}_defconfig
	config_brand=$(echo $config_name | awk -F_ '{print $1}')
	config_model=$(echo $config_name | awk -F_ '{print $2}')

	camera_name=$(sed -nE "1s/# NAME: (.+)$/\1/p" $config_path)
	camera_brand=$(echo $camera_name | awk '{print $1}')
	camera_model=$(echo $camera_name | awk -F'(' '{print $1}' | xargs)
	camera_variant=$(echo $camera_name | awk -F'[()]' '{print $2}')

	if [ "$old_brand" != "$config_brand" ]; then
		echo -e "\n\n$camera_brand"
		for i in $(seq 1 ${#camera_brand}); do
			echo -n "-"
		done
		echo
		old_brand=$config_brand
	fi

	if [ "$old_model" != "$config_model" ]; then
		echo -e "\n### ${camera_model}\n"
		old_model=$config_model
	fi

	echo "- [$camera_variant]($GH_URL_BASE/thingino-${config_name}.bin)"
done

exit 0
