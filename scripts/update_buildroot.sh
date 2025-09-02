#!/bin/bash
# Update buildroot submodule to the latest version

make reset-buildroot
git add buildroot && git commit -m "buildroot: update to latest upstream"
make update-buildroot
