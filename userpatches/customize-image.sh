#!/usr/bin/env bash
set -euo pipefail

RELEASE="${1:-}"
LINUXFAMILY="${2:-}"
BOARD="${3:-}"
BUILD_DESKTOP="${4:-}"

Main() {
  [[ "${BOARD}" == "vontar-h618" ]] || return 0

  export DEBIAN_FRONTEND=noninteractive
  
  echo "=== [vontar-h618] Customize image starting ==="
  apt-get update || true

  # 1. 遥控器与基础依赖
  apt-get install -y --no-install-recommends ir-keytable python3-evdev || echo "警告：遥控器组件部分包安装失败"

  # 2. 预装 Docker 与 Docker Compose
  echo "=== [vontar-h618] Pre-installing Docker & Docker Compose ==="
  apt-get install -y --no-install-recommends docker.io docker-compose-v2 || apt-get install -y --no-install-recommends docker.io docker-compose || echo "警告：Docker 安装步骤异常"

  # 3. 启用服务
  systemctl enable docker || true

  install -d -m 0755 /etc/rc_keymaps /usr/local/sbin /etc/systemd/system
  
  [ -f /tmp/overlay/etc/rc_keymaps/vontar-h618.toml ] && install -m 0644 /tmp/overlay/etc/rc_keymaps/vontar-h618.toml /etc/rc_keymaps/vontar-h618.toml

  # Armbian exposes the project overlay at /tmp/overlay during customization,
  # but does not copy these service units into the image automatically.
  for service in vontar-h618-ir.service vontar-h618-power-key.service vontar-h618-migrate.service; do
      if [ -f "/tmp/overlay/etc/systemd/system/$service" ]; then
          install -m 0644 "/tmp/overlay/etc/systemd/system/$service" "/etc/systemd/system/$service"
      fi
  done

  for service in vontar-h618-ir.service vontar-h618-power-key.service; do
      if [ -f "/etc/systemd/system/$service" ]; then
          systemctl enable "$service" || true
      fi
  done

  # 4. 首启自动迁移 rootfs 到 USB 硬盘 + 运行后插盘广播提示（用户 2026-08-13 需求，方案 A）
  echo "=== [vontar-h618] Enabling rootfs migration (firstboot auto / runtime manual) ==="
  for f in vontar-h618-migrate-rootfs vontar-h618-migrate-now vontar-h618-disk-notify; do
      if [ -f "/tmp/overlay/usr/local/sbin/$f" ]; then
          install -m 0755 "/tmp/overlay/usr/local/sbin/$f" "/usr/local/sbin/$f"
      fi
  done
  # udev 规则：运行后热插 USB 硬盘广播提示（不自动迁移）
  install -d -m 0755 /etc/udev/rules.d
  [ -f /tmp/overlay/etc/udev/rules.d/99-vontar-h618-disk-notify.rules ] && \
      install -m 0644 /tmp/overlay/etc/udev/rules.d/99-vontar-h618-disk-notify.rules /etc/udev/rules.d/99-vontar-h618-disk-notify.rules
  # 迁移依赖工具（rsync/gdisk/e2fsprogs/parted 一般已在，缺则补）
  apt-get install -y --no-install-recommends rsync gdisk e2fsprogs parted util-linux || echo "警告：迁移依赖部分安装失败"
  if [ -f /etc/systemd/system/vontar-h618-migrate.service ]; then
      systemctl enable vontar-h618-migrate.service || true
  fi

  echo "=== [vontar-h618] Customize image completed ==="
}

Main "$@"
