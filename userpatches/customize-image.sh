#!/usr/bin/env bash
# 注意：去掉 set -e，避免非关键命令失败直接炸毁整个 GitHub Actions 构建
set -uo pipefail

RELEASE="${1:-}"
LINUXFAMILY="${2:-}"
BOARD="${3:-}"
BUILD_DESKTOP="${4:-}"

# 仅针对 vontar-h618 执行
[[ "${BOARD}" == "vontar-h618" ]] || exit 0

export DEBIAN_FRONTEND=noninteractive

echo "=== [Customize] 开始执行用户自定义配置脚本 ==="

# 1. 更新源并安装依赖 (包含容错处理)
apt-get update -y || true
apt-get install -y --no-install-recommends \
    ir-keytable \
    python3-evdev \
    docker.io \
    docker-compose-plugin \
    rsync \
    gdisk \
    e2fsprogs \
    parted \
    util-linux || {
        echo "=== [Customize] APT 软件安装存在部分失败，继续尝试后续配置 ==="
    }

# 2. 创建所需目录
mkdir -p /etc/rc_keymaps /usr/local/sbin /etc/systemd/system

# 3. Enable 服务（在 chroot 中优先使用 systemctl，失败则 fallback 到软链接）
enable_service() {
    local svc="$1"
    systemctl enable "$svc" 2>/dev/null || \
    ln -sf "/etc/systemd/system/$svc" "/etc/systemd/system/multi-user.target.wants/$svc" || true
}

enable_service docker.service

# 4. 拷贝 overlay 文件（兼顾 /tmp/overlay 和当前相对路径）
OVERLAY_DIR="/tmp/overlay"
[ -d "$OVERLAY_DIR" ] || OVERLAY_DIR="$(dirname "$0")/overlay"

if [ -d "$OVERLAY_DIR" ]; then
    echo "=== [Customize] 发现 Overlay 目录: $OVERLAY_DIR ==="
    
    # 拷贝服务文件并启用
    for service in vontar-h618-ir.service vontar-h618-power-key.service vontar-h618-migrate.service; do
        if [ -f "$OVERLAY_DIR/etc/systemd/system/$service" ]; then
            cp -f "$OVERLAY_DIR/etc/systemd/system/$service" "/etc/systemd/system/$service"
            enable_service "$service"
        fi
    done

    # 拷贝 sbin 脚本
    for f in vontar-h618-migrate-rootfs vontar-h618-migrate-now vontar-h618-disk-notify; do
        if [ -f "$OVERLAY_DIR/usr/local/sbin/$f" ]; then
            cp -f "$OVERLAY_DIR/usr/local/sbin/$f" "/usr/local/sbin/$f"
            chmod +x "/usr/local/sbin/$f"
        fi
    done
else
    echo "=== [Customize] 未找到 Overlay 目录，跳过 Overlay 文件复制 ==="
fi

echo "=== [Customize] 自定义配置脚本执行完毕 ==="
exit 0
