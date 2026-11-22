#!/bin/sh
set -eu
cd "$(dirname "$0")"

if command -v podman >/dev/null 2>&1; then
	exec podman compose up --build --abort-on-container-exit \
		--exit-code-from tests
fi

exec docker compose up --build --abort-on-container-exit \
	--exit-code-from tests
