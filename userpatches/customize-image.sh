#!/usr/bin/env bash
set -euo pipefail

# Armbian passes: RELEASE LINUXFAMILY BOARD BUILD_DESKTOP.
# Keep the public image customization intentionally minimal; board-specific
# kernel/U-Boot integration lives in userpatches/config/boards/vontar-h618.tvb.

RELEASE="${1:-}"
LINUXFAMILY="${2:-}"
BOARD="${3:-}"
BUILD_DESKTOP="${4:-}"

Main() {
	return 0
}

Main "$@"
