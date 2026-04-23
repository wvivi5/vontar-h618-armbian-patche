#!/usr/bin/env bash
set -eu
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${TVBOX_HOST:-}" ] && [ "${LANTEST_LOCAL:-0}" != "1" ]; then
  exec "$DIR/tvbox-remote.sh" all gpio
fi
exec "$DIR/lantest.sh" gpio "${1:-/tmp}"
