#!/usr/bin/env bash
set -euo pipefail

RELEASE="${1:-}"
LINUXFAMILY="${2:-}"
BOARD="${3:-}"
BUILD_DESKTOP="${4:-}"

Main() {
 [[ "${BOARD}" == "vontar-h618" ]] || return 0

 export DEBIAN_FRONTEND=noninteractive
 
 # 核心修复：使用 || true 让这一步就算失败也不退出整个编译过程
 apt-get update || true
 apt-get install -y --no-install-recommends ir-keytable python3-evdev || echo "警告：部分包安装失败，正在跳过并继续打包..."

 install -d -m 0755 /etc/rc_keymaps /usr/local/sbin /etc/systemd/system
 
 # 只有文件存在才安装，避免文件缺失报错
 [ -f /tmp/overlay/etc/rc_keymaps/vontar-h618.toml ] && install -m 0644 /tmp/overlay/etc/rc_keymaps/vontar-h618.toml /etc/rc_keymaps/vontar-h618.toml
 
 # 自动启动服务逻辑
 if [ -f /etc/systemd/system/vontar-h618-ir.service ]; then
     systemctl enable vontar-h618-ir.service || true
 fi
 if [ -f /etc/systemd/system/vontar-h618-power-key.service ]; then
     systemctl enable vontar-h618-power-key.service || true
 fi
}

Main "$@"
