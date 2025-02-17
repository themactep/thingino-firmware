#!/bin/sh
# Update buildroot submodule to the latest version
git pull
git submodule update --remote --merge
