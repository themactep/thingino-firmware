#!/bin/sh
# Update buildroot submodule to the latest version

set -eu

buildroot_path="buildroot"

if [ -n "${1:-}" ]; then
    if ! git -C "$buildroot_path" checkout "$1"; then
        echo "Failed to checkout $1"
        exit 1
    fi
    commit_message="Update buildroot to version $1"
else
    git submodule update --remote "$buildroot_path"
    commit_message="Update buildroot to latest version"
fi

git add "$buildroot_path"

if git diff --cached --quiet -- "$buildroot_path"; then
    echo "No buildroot changes to commit"
    exit 0
fi

git commit --only -m "$commit_message" -- "$buildroot_path"
