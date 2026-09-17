#!/bin/sh
# Start MariaDB, Apache and ZoneMinder in one container.
#
# Local database only: the plain test rig has no use for the remote-database
# and multi-distro detection of the upstream ZoneMinder entrypoint.

set -eu

TZ="${TZ:-UTC}"
export TZ

ZMCONF=/etc/zm/zm.conf
ZM_CREATE_SQL=/usr/share/zoneminder/db/zm_create.sql
MYSQL_DATADIR=/var/lib/mysql
ZM_LOG=/var/log/zm/zm.log

fail() {
	printf 'FATAL: %s\n' "$*" >&2
	exit 1
}

[ -f "$ZMCONF" ] || fail "missing $ZMCONF"
[ -f "$ZM_CREATE_SQL" ] || fail "missing $ZM_CREATE_SQL"

if [ -e "/usr/share/zoneinfo/$TZ" ]; then
	ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
	printf '%s\n' "$TZ" >/etc/timezone
fi

# The image has no systemd-tmpfiles to create these at boot. /run/zm holds the
# process sockets, /tmp/zm the swap files (ZM_PATH_SOCKS / ZM_PATH_SWAP).
mkdir -p /run/zm /tmp/zm /var/log/zm
touch "$ZM_LOG"
chown -R www-data:www-data /run/zm /tmp/zm /var/log/zm

chown -R mysql:mysql "$MYSQL_DATADIR"

if [ ! -d "$MYSQL_DATADIR/mysql" ]; then
	echo "Initializing MariaDB data directory"
	mariadb-install-db --user=mysql --datadir="$MYSQL_DATADIR" >/dev/null
fi

echo "Starting MariaDB"
mariadbd-safe --user=mysql >/dev/null 2>&1 &

i=0
while ! mariadb-admin ping >/dev/null 2>&1; do
	i=$((i + 1))
	[ "$i" -lt 60 ] || fail "MariaDB did not start within 60s"
	sleep 1
done

mariadb -u root <<'SQL'
CREATE DATABASE IF NOT EXISTS zm;
CREATE USER IF NOT EXISTS 'zmuser'@'localhost' IDENTIFIED BY 'zmpass';
GRANT ALL PRIVILEGES ON zm.* TO 'zmuser'@'localhost';
FLUSH PRIVILEGES;
SQL

tables=$(mariadb -u root -N -B -e \
	"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zm'")
if [ "$tables" -eq 0 ]; then
	echo "Loading ZoneMinder schema"
	mariadb -u root zm <"$ZM_CREATE_SQL"
fi

mkdir -p /var/cache/zoneminder/events /var/cache/zoneminder/images
chown -R www-data:www-data /var/cache/zoneminder

echo "Starting Apache"
apache2ctl -k start

echo "Starting ZoneMinder"
if ! zmpkg.pl start; then
	zmpkg.pl status || true
	fail "zoneminder failed to start"
fi

tail -F "$ZM_LOG" &
TAIL_PID=$!

cleanup() {
	trap - TERM INT
	echo "Shutting down"
	kill "$TAIL_PID" 2>/dev/null || true
	zmpkg.pl stop 2>/dev/null || true
	apache2ctl -k stop 2>/dev/null || true
	mariadb-admin shutdown 2>/dev/null || true
	exit 0
}
trap cleanup TERM INT

wait "$TAIL_PID"
