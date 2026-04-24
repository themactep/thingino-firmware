#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 OUTPUT_DIR" >&2
  exit 1
fi

output_dir=$1
images_dir="${output_dir}/images"
target_dir="${output_dir}/target"
os_release_file="${target_dir}/usr/lib/os-release"

if [ ! -f "$os_release_file" ]; then
  os_release_file="${target_dir}/etc/os-release"
fi

[ -d "$images_dir" ] || {
  echo "Missing images directory: $images_dir" >&2
  exit 1
}

[ -f "$os_release_file" ] || {
  echo "Missing os-release file in $target_dir" >&2
  exit 1
}

read_os_release_value() {
  key=$1
  sed -n "s/^${key}=//p" "$os_release_file" | head -n1 | sed 's/^"//; s/"$//'
}

image_id=$(read_os_release_value IMAGE_ID)
build_id=$(read_os_release_value BUILD_ID)

[ -n "$image_id" ] || {
  echo "Missing IMAGE_ID in $os_release_file" >&2
  exit 1
}

[ -n "$build_id" ] || {
  echo "Missing BUILD_ID in $os_release_file" >&2
  exit 1
}

full_firmware_name="thingino-${image_id}.bin"
full_firmware_path="${images_dir}/${full_firmware_name}"

[ -f "$full_firmware_path" ] || {
  echo "Missing full firmware image: $full_firmware_path" >&2
  exit 1
}

write_sha256sum() {
  firmware_path=$1
  firmware_name=$2
  output_file="${firmware_path}.sha256sum"
  tmp_file="${output_file}.tmp"

  rm -f "$tmp_file"
  printf '# %s\n' "$image_id" >>"$tmp_file"
  printf '# %s\n' "$build_id" >>"$tmp_file"
  sha256sum "$firmware_path" | awk '{print $1 "  " filename}' filename="$firmware_name" >>"$tmp_file"
  mv "$tmp_file" "$output_file"
}

write_sha256sum "$full_firmware_path" "$full_firmware_name"

# update_firmware_name="thingino-${image_id}-update.bin"
# update_firmware_path="${images_dir}/${update_firmware_name}"
## Boot, env, and config partitions are fixed at 256K + 32K + 224K.
# kernel_offset_bytes=$(((256 + 32 + 224) * 1024))
# dd if="$full_firmware_path" of="$update_firmware_path" skip="${kernel_offset_bytes}B" status=none
# write_sha256sum "$update_firmware_path" "$update_firmware_name"
