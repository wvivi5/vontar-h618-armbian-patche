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
  
  if [ -f /etc/systemd/system/vontar-h618-ir.service ]; then
      systemctl enable vontar-h618-ir.service || true
  fi
  if [ -f /etc/systemd/system/vontar-h618-power-key.service ]; then
      systemctl enable vontar-h618-power-key.service || true
  fi

  echo "=== [vontar-h618] Customize image completed ==="
}

Main "$@"
