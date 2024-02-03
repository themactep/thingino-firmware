#!/bin/sh

. /usr/sbin/common

clean_quit() {
	echo_c 37 "$2" >&2
	[ -f "$tmp_file" ] && rm $v_opts "$tmp_file"
	exit "$1"
}

print_usage() {
	echo "Usage: $0 [-b <branch>] [-c <hash>] [-v] [-f] [-h]
  -b <branch>  Git branch to use.
  -c <hash>    Git commit hash to use.
  -f           Install even if same version.
  -v           Verbose output.
  -h           Show this help.
"
	exit 0
}

while getopts b:c:fhv flag; do
	case "$flag" in
		b)
			branch=$OPTARG
			;;
		c)
			commit=$OPTARG
			;;
		f)
			enforce=1
			;;
		v)
			verbose=1
			v_opts="-v"
			;;
		h|*)
			print_usage
			;;
	esac
done

if [ -n "$branch" ]; then
	url="https://github.com/OpenIPC/webui/archive/refs/heads/${branch}.zip"
	bundle_dir="webui-${branch}"
elif [ -n "$commit" ]; then
	url="https://github.com/OpenIPC/webui/archive/${commit}.zip"
	bundle_dir="webui-${commit}"
else
	echo_c 31 "branch: ${branch}, commit: ${commit}"
	echo_c 33 "You need to specify either a branch or a commit hash!"
	print_usage
	exit 0
fi

etag_file=/root/.ui.etag
tmp_file="$(mktemp -u)"

cmd="curl --silent --location --insecure --fail"
[ "1" = "$verbose" ] && cmd="${cmd} --verbose"

cmd="${cmd} --etag-save ${etag_file}"
if [ "1" != "$enforce" ] && [ -f "$etag_file" ]; then
	cmd="${cmd} --etag-compare ${etag_file}"
fi

cmd="${cmd} --url $url"
cmd="${cmd} --output $tmp_file"
log_and_run "$cmd"
[ ! -f "$tmp_file" ] && clean_quit 1 "GitHub version matches the installed one. Nothing to update."

[ -z "$commit" ] && commit=$(tail -c 40 "$tmp_file" | cut -b1-7)

# date in ISO format. ugly but it works
_ts=$(unzip -l "$tmp_file" | head -5 | tail -1 | xargs | cut -d" " -f2)
timestamp="$(echo "$_ts" | cut -d- -f3)-$(echo "$_ts" | cut -d- -f1)-$(echo "$_ts" | cut -d- -f2)"

unzip_dir=$(mktemp -d)
cmd="unzip -o -d ${unzip_dir} ${tmp_file}"
[ "1" != "$verbose" ] && cmd="${cmd} -q"
cmd="${cmd} -x ${bundle_dir}/README.md ${bundle_dir}/LICENSE ${bundle_dir}/.git* ${bundle_dir}/dev/* ${bundle_dir}/docs/*"
log_and_run "$cmd"

upd_dir="${unzip_dir}/${bundle_dir}/files"
echo_c 37 "Copy newer files from ${upd_dir} to web directory"
for upd_file in $(find "$upd_dir" -type f -or -type l); do
	ovl_file=${upd_file#${upd_dir}}
	if [ ! -f "$ovl_file" ] || ! diff -q "$ovl_file" "$upd_file"; then
		[ ! -d "${ovl_file%/*}" ] && mkdir -p "$(dirname "$ovl_file")"
		cp $v_opts -f "$upd_file" "$ovl_file"
	fi
done

echo_c 37 "Remove absent files from overlay"
for file in $(diff -qr "/var/www" "${upd_dir}/var/www" | grep "Only in /var/www:" | cut -d':' -f2 | tr -d "^ "); do
	[ "$file" != "$etag_file" ] && rm $v_opts -f "/var/www/${file}"
done
mount -o remount /

echo_c 37 "Delete bundle"
rm $v_opts -f "$tmp_file"

echo_c 37 "Delete temp directory"
rm $v_opts -rf "$unzip_dir"

if [ -n "$error" ]; then
	rm $v_opts "$etag_file"
	clean_quit 2 "ATTENTION! There were errors!"
fi

echo "${branch}+${commit}, ${timestamp}" >/var/www/.version
[ -f /tmp/sysinfo.txt ] && rm $v_opts /tmp/sysinfo.txt

clean_quit 0 "Done."
