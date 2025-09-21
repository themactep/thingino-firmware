#!/bin/sh
# Update buildroot submodule to the latest version

if [ -n "$1" ]; then
    cd buildroot
    git checkout $1 || { echo "Failed to checkout $1"; exit 1; }
    cd ..
    git add buildroot
    git commit -m "Update buildroot to version $1"
else
    git submodule update --remote buildroot
    git add buildroot
    git commit -m "Update buildroot to latest version"
fi
