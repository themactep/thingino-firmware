#!/bin/sh

set -eu

OWNER="themactep"
REPO="thingino-firmware"
HOSTARCH="$(uname -m)"
RELEASE_TAG="toolchain-${HOSTARCH}"
TOOLCHAIN_DL_SUBDIR="toolchain-external-custom"

if [ -z "${BR2_DL_DIR:-}" ]; then
	echo "Error: BR2_DL_DIR environment variable is not set"
	exit 1
fi

TOOLCHAIN_DL_DIR="${BR2_DL_DIR}/${TOOLCHAIN_DL_SUBDIR}"

API_URL="https://api.github.com/repos/${OWNER}/${REPO}/releases/tags/${RELEASE_TAG}"

echo "Checking toolchain release: ${RELEASE_TAG}"
release_json="$(curl -fsSL "${API_URL}")"

assets="$(
	printf '%s' "${release_json}" | python3 -c '
import json
import sys

release = json.load(sys.stdin)
for asset in release.get("assets", []):
    name = asset.get("name")
    updated = asset.get("updated_at")
    digest = asset.get("digest") or ""
    size = asset.get("size") or ""
    if name and updated:
        print(f"{name}|{updated}|{digest}|{size}")
'
)"

if [ -z "${assets}" ]; then
	echo "No toolchain assets found for ${RELEASE_TAG}"
	exit 1
fi

mkdir -p "${TOOLCHAIN_DL_DIR}"
assets_file="$(mktemp)"
trap 'rm -f "${assets_file}"' EXIT
printf '%s\n' "${assets}" >"${assets_file}"

checked=0
kept=0
removed=0
missing=0

while IFS='|' read -r name updated_at digest size; do
	checked=$((checked + 1))
	dst="${TOOLCHAIN_DL_DIR}/${name}"
	stamp="${dst}.github-updated-at"

	if [ ! -f "${dst}" ]; then
		missing=$((missing + 1))
		continue
	fi

	if [ -f "${stamp}" ] && [ "$(cat "${stamp}")" = "${updated_at}" ]; then
		echo "Current: ${name}"
		kept=$((kept + 1))
		continue
	fi

	# Buildroot downloads the bundle without recording the release
	# timestamp, so verify the content against the release asset before
	# trusting it. Keep the stamp so later runs skip the checksum.
	if [ -n "${digest}" ]; then
		actual="sha256:$(sha256sum "${dst}" | cut -d' ' -f1)"
		if [ "${actual}" = "${digest}" ]; then
			printf '%s\n' "${updated_at}" >"${stamp}"
			echo "Current: ${name}"
			kept=$((kept + 1))
			continue
		fi
	elif [ -n "${size}" ] && [ "$(stat -c %s "${dst}")" = "${size}" ]; then
		printf '%s\n' "${updated_at}" >"${stamp}"
		echo "Current: ${name}"
		kept=$((kept + 1))
		continue
	fi

	echo "Removing stale bundle: ${name}"
	rm -f "${dst}" "${stamp}"
	removed=$((removed + 1))
done <"${assets_file}"

echo "Toolchain bundles checked: ${checked}, current: ${kept}, removed stale: ${removed}, missing locally: ${missing}"
