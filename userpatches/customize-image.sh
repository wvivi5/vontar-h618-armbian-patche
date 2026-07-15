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
	[[ "${BOARD}" == "vontar-h618" ]] || return 0

	export DEBIAN_FRONTEND=noninteractive
	apt-get install -y --no-install-recommends ir-keytable

	install -d -m 0755 /etc/rc_keymaps /usr/local/sbin /etc/systemd/system
	install -m 0644 /tmp/overlay/etc/rc_keymaps/vontar-h618.toml \
		/etc/rc_keymaps/vontar-h618.toml
	install -m 0755 /tmp/overlay/usr/local/sbin/vontar-h618-ir-setup \
		/usr/local/sbin/vontar-h618-ir-setup
	install -m 0644 /tmp/overlay/etc/systemd/system/vontar-h618-ir.service \
		/etc/systemd/system/vontar-h618-ir.service

	systemctl enable vontar-h618-ir.service
}

Main "$@"
