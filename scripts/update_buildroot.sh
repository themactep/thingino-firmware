#!/bin/sh
# Update buildroot submodule to a specific version or latest stable release

set -eu

buildroot_path="buildroot"

if [ -n "${1:-}" ]; then
    if ! git -C "$buildroot_path" checkout "$1"; then
        echo "Failed to checkout $1"
        exit 1
    fi
    commit_message="Update buildroot to version $1"
else
    git -C "$buildroot_path" fetch --tags --quiet origin
    latest_stable_release="$(
        git -C "$buildroot_path" tag -l \
            | grep -E '^[0-9]{4}\.[0-9]{2}(\.[0-9]+)?$' \
            | sort -V \
            | tail -n 1
    )"

    if [ -z "$latest_stable_release" ]; then
        echo "Failed to resolve latest stable buildroot release tag"
        exit 1
    fi

    if ! git -C "$buildroot_path" checkout "$latest_stable_release"; then
        echo "Failed to checkout $latest_stable_release"
        exit 1
    fi

    commit_message="Update buildroot to latest stable release $latest_stable_release"
fi

git add "$buildroot_path"

if git diff --cached --quiet -- "$buildroot_path"; then
    echo "No buildroot changes to commit"
    exit 0
fi

git commit --only -m "$commit_message" -- "$buildroot_path"
