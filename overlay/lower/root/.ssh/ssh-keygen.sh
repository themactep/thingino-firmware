#!/bin/sh

ROOT_SSH_DIR=$(dirname $0)
cd ${ROOT_SSH_DIR}

[ -f id_dropbear -a -f id_dropbear.pub ] && exit 0
/bin/dropbearkey -t ed25519 -f id_dropbear

exit 0
