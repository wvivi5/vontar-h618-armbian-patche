#!/usr/bin/env bash
set -euo pipefail
RELEASE="${1:-}"; LINUXFAMILY="${2:-}"; BOARD="${3:-}"; BUILD_DESKTOP="${4:-}"
[[ "${BOARD}" == "vontar-h618" ]] || return 0
export DEBIAN_FRONTEND=noninteractive
apt-get update || true
apt-get install -y --no-install-recommends ir-keytable python3-evdev docker.io docker-compose-plugin rsync gdisk e2fsprogs parted util-linux
systemctl enable docker || true
install -d -m 0755 /etc/rc_keymaps /usr/local/sbin /etc/systemd/system
for service in vontar-h618-ir.service vontar-h618-power-key.service vontar-h618-migrate.service; do
    if [ -f "/tmp/overlay/etc/systemd/system/$service" ]; then
        install -m 0644 "/tmp/overlay/etc/systemd/system/$service" "/etc/systemd/system/$service"
        systemctl enable "$service" || true
    fi
done
for f in vontar-h618-migrate-rootfs vontar-h618-migrate-now vontar-h618-disk-notify; do
    [ -f "/tmp/overlay/usr/local/sbin/$f" ] && install -m 0755 "/tmp/overlay/usr/local/sbin/$f" "/usr/local/sbin/$f"
done
