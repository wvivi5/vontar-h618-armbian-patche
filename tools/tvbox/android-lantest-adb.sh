#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-all}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
TARGET="${2:-${ADB_TVBOX_HOST:-}}"
OUTDIR="${3:-$REPO_DIR/logs/lantest}"

usage() {
  cat <<'__USAGE__'
Usage:
  ./android-lantest-adb.sh [quick|all|i2c|bt] <host[:port]> [outdir]

Environment:
  ADB_TVBOX_HOST can provide the default Android ADB target.
__USAGE__
}

case "$MODE" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

if [ -z "$TARGET" ]; then
  usage >&2
  echo "set ADB_TVBOX_HOST or pass host[:port] as the second argument" >&2
  exit 2
fi

case "$MODE" in
  quick|all|i2c|bt) ;;
  *)
    usage >&2
    exit 2
    ;;
esac

case "$TARGET" in
  *:*) SERIAL="$TARGET" ;;
  *) SERIAL="${TARGET}:5555" ;;
esac

HOST_TAG="$(printf '%s' "$SERIAL" | tr ':/' '__')"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="${OUTDIR%/}/android_lantest_${HOST_TAG}_${MODE}_${TS}.log"

mkdir -p "$OUTDIR"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing host tool: $1" >&2
    exit 2
  }
}

need_cmd adb

adb start-server >/dev/null
adb connect "$SERIAL" >/dev/null
adb -s "$SERIAL" wait-for-device

ADB_STATE="$(adb -s "$SERIAL" get-state 2>/dev/null | tr -d '\r')"
if [ "$ADB_STATE" != "device" ]; then
  echo "adb target state is '$ADB_STATE', expected 'device'" >&2
  echo "if this is Android, confirm USB debugging auth and 'adb connect $SERIAL'" >&2
  exit 3
fi

USE_SU=0
if adb -s "$SERIAL" shell "su -c id -u" >/tmp/.android_lantest_adb_su.$$ 2>/dev/null; then
  if grep -q '^0' /tmp/.android_lantest_adb_su.$$; then
    USE_SU=1
  fi
fi
rm -f /tmp/.android_lantest_adb_su.$$

run_local() {
  local title="$1"
  local cmd="$2"
  {
    echo
    echo "===== $title ====="
    echo "+ $cmd"
    bash -lc "$cmd"
    echo "[rc=$?]"
  } >>"$LOG" 2>&1
}

adb_shell_run() {
  local title="$1"
  local cmd="$2"
  {
    echo
    echo "===== $title ====="
    if [ "$USE_SU" -eq 1 ]; then
      echo "+ su -c $cmd"
      adb -s "$SERIAL" shell "su -c \"$cmd\""
    else
      echo "+ $cmd"
      adb -s "$SERIAL" shell "$cmd"
    fi
    echo "[rc=$?]"
  } >>"$LOG" 2>&1 || true
}

adb_shell_plain() {
  local title="$1"
  local cmd="$2"
  {
    echo
    echo "===== $title ====="
    echo "+ $cmd"
    adb -s "$SERIAL" shell "$cmd"
    echo "[rc=$?]"
  } >>"$LOG" 2>&1 || true
}

adb_prop_dump() {
  local path="$1"
  local base="$2"
  adb_shell_plain "${base}_path" "if [ -e '$path' ]; then echo '$path'; else echo MISSING; fi"
  adb_shell_plain "${base}_strings" "if [ -e '$path' ]; then tr '\\000' '\\n' < '$path'; else echo MISSING; fi"
  adb_shell_plain "${base}_hex" "if [ -e '$path' ]; then od -An -tx4 -v '$path'; else echo MISSING; fi"
}

adb_shell_find() {
  local title="$1"
  local expr="$2"
  adb_shell_plain "$title" "find /vendor /system /odm /proc/device-tree /sys/firmware/devicetree/base 2>/dev/null | grep -iE \"$expr\" | sort -u"
}

adb_shell_prop_tree() {
  local base="$1"
  local title="$2"
  adb_shell_plain "$title" "
if [ -d '$base' ]; then
  find '$base' -maxdepth 2 -mindepth 1 2>/dev/null | sort
  for f in '$base'/*; do
    [ -e \"\$f\" ] || continue
    [ -d \"\$f\" ] && continue
    echo \"--- \$f ---\"
    tr '\\000' '\\n' < \"\$f\" 2>/dev/null || od -An -tx4 -v \"\$f\" 2>/dev/null || true
  done
else
  echo MISSING
fi"
}

DT_PATH_RAW="$(adb -s "$SERIAL" shell "{ readlink -f /sys/class/net/eth0/device/of_node 2>/dev/null || true; for base in /proc/device-tree /sys/firmware/devicetree/base; do [ -d \"\$base\" ] || continue; find \"\$base\" -maxdepth 6 -type d 2>/dev/null | grep -Ei '/(eth|ethernet)@5030000$|/5030000\\.eth$|/5030000\\.ethernet$' | head -n1 && break; done; } | sed -n '1p'" 2>/dev/null || true)"
DT_PATH="$(printf '%s' "$DT_PATH_RAW" | tr -d '\r')"

{
  echo "android_lantest"
  echo "timestamp=$TS"
  echo "serial=$SERIAL"
  echo "mode=$MODE"
  echo "adb_state=$ADB_STATE"
  echo "use_su=$USE_SU"
  echo "dt_path=${DT_PATH:-missing}"
} >"$LOG"

run_local "HOST_ADB" "adb devices -l"
run_local "HOST_CONNECT" "adb connect '$SERIAL' || true"

adb_shell_plain "ANDROID_BUILD" "getprop | grep -Ei 'ro\\.build|ro\\.product|ro\\.board|ro\\.boot|service\\.adb\\.tcp\\.port|persist\\.sys\\.usb\\.config' | sort"
adb_shell_plain "ANDROID_UNAME" "uname -a"
adb_shell_plain "ANDROID_IP_BR" "ip -br a"
adb_shell_plain "ANDROID_ROUTE" "ip route"
adb_shell_plain "ANDROID_NET_ETH0" "for f in operstate carrier address mtu; do printf '%s=' \"\$f\"; cat /sys/class/net/eth0/\$f 2>/dev/null || echo MISSING; done"
adb_shell_plain "ANDROID_SYS_CLASS_NET" "ls -l /sys/class/net"
adb_shell_plain "ANDROID_MDIO_SYSFS" "ls -l /sys/bus/mdio_bus/devices 2>/dev/null || true"
adb_shell_plain "ANDROID_MDIO_DETAILS" "for d in /sys/bus/mdio_bus/devices/*; do [ -e \"\$d\" ] || continue; echo \"--- \$d ---\"; readlink -f \"\$d\" 2>/dev/null || true; for f in phy_id name phy_interface; do [ -e \"\$d/\$f\" ] && { printf '%s=' \"\$f\"; cat \"\$d/\$f\"; }; done; [ -d \"\$d/attached_dev\" ] && { printf 'attached_dev='; readlink -f \"\$d/attached_dev\" 2>/dev/null || true; }; done"
adb_shell_plain "ANDROID_INTERRUPTS" "grep -Ei 'eth|gmac|stmmac|dwmac|phy|mdio' /proc/interrupts 2>/dev/null || true"
adb_shell_run "ANDROID_KERNEL_LOG" "dmesg 2>/dev/null | grep -Ei 'eth0|gmac|stmmac|dwmac|phy|mdio|ac200|ac300|i2c|link|rmii|ephy' | tail -n 400"
adb_shell_plain "ANDROID_LOGCAT_KERNEL" "logcat -d -b kernel 2>/dev/null | grep -Ei 'eth0|gmac|stmmac|dwmac|phy|mdio|ac200|ac300|i2c|link|rmii|ephy' | tail -n 400"
adb_shell_plain "ANDROID_ETH0_OF_NODE" "readlink -f /sys/class/net/eth0/device/of_node 2>/dev/null || true"
adb_shell_plain "ANDROID_ETH0_UEVENT" "cat /sys/class/net/eth0/device/uevent 2>/dev/null || true"

if [ -n "$DT_PATH" ]; then
  adb_prop_dump "$DT_PATH/compatible" "DT_compatible"
  adb_prop_dump "$DT_PATH/status" "DT_status"
  adb_prop_dump "$DT_PATH/phy-mode" "DT_phy_mode"
  adb_prop_dump "$DT_PATH/interrupt-names" "DT_interrupt_names"
  adb_prop_dump "$DT_PATH/clock-names" "DT_clock_names"
  adb_prop_dump "$DT_PATH/reset-names" "DT_reset_names"
  adb_prop_dump "$DT_PATH/reg" "DT_reg"
  adb_prop_dump "$DT_PATH/interrupts" "DT_interrupts"
  adb_prop_dump "$DT_PATH/clocks" "DT_clocks"
  adb_prop_dump "$DT_PATH/resets" "DT_resets"
  adb_prop_dump "$DT_PATH/syscon" "DT_syscon"
  adb_prop_dump "$DT_PATH/pinctrl-0" "DT_pinctrl_0"
  adb_prop_dump "$DT_PATH/phy-handle" "DT_phy_handle"
  adb_prop_dump "$DT_PATH/phy-supply" "DT_phy_supply"
  adb_prop_dump "$DT_PATH/phy-io-supply" "DT_phy_io_supply"
  adb_shell_plain "DT_children" "find '$DT_PATH' -maxdepth 2 -mindepth 1 2>/dev/null | sort"
else
  adb_shell_plain "DT_SEARCH" "for base in /proc/device-tree /sys/firmware/devicetree/base; do [ -d \"\$base\" ] || continue; echo \"--- \$base ---\"; find \"\$base\" -maxdepth 6 -type d 2>/dev/null | grep -Ei '5030000|ethernet|eth@|emac|gmac' | sort; done"
fi

if [ "$MODE" = "all" ] || [ "$MODE" = "i2c" ]; then
  adb_shell_plain "I2C_SYSFS_DEVICES" "find /sys/bus/i2c/devices -maxdepth 2 -type f \\( -name name -o -name modalias -o -name of_node \\) 2>/dev/null | sort"
  adb_shell_plain "I2C_SYSFS_LS" "ls -lR /sys/bus/i2c/devices 2>/dev/null || true"
  adb_shell_plain "I2C_DEV_NODES" "ls -l /dev/i2c-* 2>/dev/null || true"
  adb_shell_plain "I2C_TOOLS" "command -v i2cdetect || true; command -v i2cget || true"
  adb_shell_plain "I2C_LIST" "i2cdetect -l 2>/dev/null || true"
  if adb -s "$SERIAL" shell "command -v i2cdetect >/dev/null 2>&1 && echo yes || echo no" 2>/dev/null | tr -d '\r' | grep -q '^yes$'; then
    BUS_LIST="$(adb -s "$SERIAL" shell "{ i2cdetect -l 2>/dev/null | sed -n 's/^i2c-\\([0-9][0-9]*\\).*/\\1/p'; ls /dev/i2c-* 2>/dev/null | sed -n 's#^/dev/i2c-\\([0-9][0-9]*\\)\$#\\1#p'; } | sort -u" 2>/dev/null | tr -d '\r')"
    for bus in $BUS_LIST; do
      adb_shell_run "I2C_BUS_${bus}_SCAN" "i2cdetect -y '$bus' 2>/dev/null || true"
      adb_shell_run "I2C_BUS_${bus}_PMIC_PROBE" "for a in 0x34 0x35 0x36 0x3a; do i2cget -y '$bus' \$a 0x00 2>/dev/null && i2cget -y '$bus' \$a 0x03 2>/dev/null; done || true"
    done
  fi
fi

if [ "$MODE" = "all" ] || [ "$MODE" = "bt" ]; then
  adb_shell_run "BT_DEBUGFS_MOUNT" "mount | grep -q 'debugfs on /sys/kernel/debug' || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true"
  adb_shell_plain "BT_GETPROP" "getprop | grep -iE 'bluetooth|bt|broadcom|brcm|uart|ttyAS' | sort"

  adb_shell_plain "BT_TTY_DEVICES" "ls -l /dev/ttyAS* /dev/ttyS* 2>/dev/null || true"
  adb_shell_plain "BT_UART_PORT" "for p in /dev/ttyAS1 /dev/ttyAS0 /dev/ttyS1 /dev/ttyS2 /dev/ttyS3; do [ -e \"\$p\" ] && ls -l \"\$p\"; done"

  adb_shell_plain "BT_SYS_CLASS" "ls -l /sys/class/bluetooth 2>/dev/null || true"
  adb_shell_plain "BT_SYS_HCI" "find /sys -iname '*hci*' 2>/dev/null | sort | head -n 200"

  adb_shell_plain "BT_RFKILL" "ls -l /sys/class/rfkill 2>/dev/null || true; for d in /sys/class/rfkill/rfkill*; do [ -d \"\$d\" ] || continue; echo \"--- \$d ---\"; for f in name type state soft hard; do [ -e \"\$d/\$f\" ] && { printf '%s=' \"\$f\"; cat \"\$d/\$f\"; }; done; done"

  adb_shell_plain "BT_FIRMWARE_FILES" "find /vendor/firmware /system/etc/firmware /system/vendor/firmware /odm/firmware 2>/dev/null | grep -iE '4334|ap6334|brcm|bcm|hcd|nvram' | sort"
  adb_shell_plain "BT_FIRMWARE_DIRS" "for d in /vendor/firmware /system/etc/firmware /system/vendor/firmware /odm/firmware; do [ -d \"\$d\" ] && { echo \"--- \$d ---\"; ls -l \"\$d\"; }; done"

  adb_shell_plain "BT_LOGCAT_KERNEL" "logcat -d -b kernel 2>/dev/null | grep -iE 'bluetooth|hci|bcm|brcm|ttyAS1|uart|patchram' | tail -n 400"
  adb_shell_plain "BT_LOGCAT_MAIN" "logcat -d 2>/dev/null | grep -iE 'bluetooth|bt_vendor|broadcom|bcm|brcm|ttyAS1|hciattach|patchram' | tail -n 400"

  adb_shell_run "BT_DMESG" "dmesg 2>/dev/null | grep -iE 'bluetooth|hci|bcm|brcm|ttyAS1|uart|patchram' | tail -n 400"

  adb_shell_plain "BT_PROC_DEVICETREE_SEARCH" "grep -RniE 'bluetooth|bcm4334|brcm|ttyAS1|uart|shutdown-gpios|host-wakeup|device-wakeup|wifi-pwrseq|mmc-pwrseq' /proc/device-tree 2>/dev/null || true"
  adb_shell_plain "BT_DT_UART_NODES" "find /proc/device-tree /sys/firmware/devicetree/base 2>/dev/null | grep -Ei '/(serial|uart)@' | sort -u"

  adb_shell_plain "BT_DT_BLUETOOTH_NODES" "find /proc/device-tree /sys/firmware/devicetree/base 2>/dev/null | grep -Ei 'bluetooth|bcm4334|brcm' | sort -u"
  adb_shell_prop_tree "/sys/firmware/devicetree/base/soc@3000000/uart@5000400/bluetooth" "BT_DT_UART1_CHILD"
  adb_shell_prop_tree "/proc/device-tree/soc@3000000/uart@5000400/bluetooth" "BT_PROC_UART1_CHILD"

  adb_shell_plain "BT_SERVICE_STATE" "getprop init.svc.vendor.bluetooth-1-0; getprop ro.boottime.vendor.bluetooth-1-0; getprop persist.vendor.bluetooth_port; getprop persist.log.tag.bluetooth_vendor"

  adb_shell_plain "BT_ADDR" "cat /sys/class/addr_mgt/addr_bt 2>/dev/null || true"

  adb_prop_dump "/sys/firmware/devicetree/base/soc@3000000/uart@5000400/status" "BT_UART1_status"
  adb_prop_dump "/sys/firmware/devicetree/base/soc@3000000/uart@5000400/compatible" "BT_UART1_compatible"
  adb_prop_dump "/sys/firmware/devicetree/base/soc@3000000/uart@5000400/pinctrl-0" "BT_UART1_pinctrl0"
  adb_prop_dump "/sys/firmware/devicetree/base/soc@3000000/uart@5000400/uart1_port" "BT_UART1_port"
  adb_prop_dump "/sys/firmware/devicetree/base/soc@3000000/uart@5000400/uart1_type" "BT_UART1_type"
  adb_shell_plain "BT_SERVICE_PROPS" "getprop | grep -iE 'vendor.bluetooth|bluetooth_port|module_info|bdaddr' | sort"
  adb_shell_plain "BT_RFKILL_VERBOSE" '
for d in /sys/class/rfkill/rfkill*; do
  [ -d "$d" ] || continue
  echo "=== $d ==="
  for f in name type state soft hard device; do
    [ -e "$d/$f" ] && { printf "%s=" "$f"; cat "$d/$f" 2>/dev/null || readlink -f "$d/$f" 2>/dev/null; }
  done
done
'
  adb_shell_plain "BT_SERVICE_PROPS" '
getprop init.svc.vendor.bluetooth-1-0
getprop ro.boottime.vendor.bluetooth-1-0
getprop persist.vendor.bluetooth_port
getprop persist.log.tag.bluetooth_vendor
getprop persist.log.tag.module_info
getprop ro.bt.bdaddr_path
'

  adb_shell_plain "BT_PINCTRL_DEBUGFS" "
for f in /sys/kernel/debug/pinctrl/*/pinmux-pins /sys/kernel/debug/pinctrl/*/pins /sys/kernel/debug/pinctrl/*/pinconf-pins; do
  [ -e \"\$f\" ] || continue
  echo \"=== \$f ===\"
  grep -Ei 'PG1[679]|PG[6-9][[:space:]]|5000400|uart1|bluetooth' \"\$f\" 2>/dev/null || true
done
"
  adb_shell_plain "BT_GPIO_DEBUG" "
for f in /sys/kernel/debug/gpio /sys/kernel/debug/gpio-mockup; do
  [ -e \"\$f\" ] || continue
  echo \"=== \$f ===\"
  cat \"\$f\" 2>/dev/null | grep -Ei 'PG1[679]|gpio-20[89]|gpio-211|gpio-198|gpio-199|gpio-200|gpio-201|bluetooth|bt' || true
done
"
  adb_shell_plain "BT_GPIOINFO" "command -v gpioinfo >/dev/null 2>&1 && gpioinfo 2>/dev/null | grep -Ei 'PG1[679]|PG[6-9]' || true"
  adb_shell_plain "BT_SLEEP_IFACE" "find /proc/bluetooth /sys/class/rfkill /sys/class/addr_mgt 2>/dev/null | sort || true"
  adb_shell_plain "BT_INIT_SCRIPTS" "
grep -RIn -I -E 'bluetooth|bt_vendor|patchram|hciattach|ttyAS1|ttyS1|bcm43|brcm|4334|hostwake|device-wakeup|shutdown-gpios|reset-gpios|PG16|PG17|PG19' \
  /vendor/etc /vendor/bin /vendor/etc/init /system/etc /system/bin /system_ext/etc /odm/etc 2>/dev/null | head -n 400 || true
"
  adb_shell_plain "BT_PROC_MODULES" "cat /proc/modules 2>/dev/null | grep -Ei 'bluetooth|hci|bcm|brcm|wlan' || true"
  adb_shell_plain "BT_REGULATOR_STATE" "
for d in /sys/class/regulator/*; do
  [ -d \"\$d\" ] || continue
  n=$(cat \"\$d/name\" 2>/dev/null || true)
  case \"$n\" in
    *bt*|*wifi*|*vcc3v3*|*aldo1*|*dldo1*|*io*) ;;
    *) continue ;;
  esac
  echo \"=== \$d ===\"
  for f in name state microvolts min_microvolts max_microvolts num_users; do
    [ -e \"\$d/\$f\" ] && { printf '%s=' \"\$f\"; cat \"\$d/\$f\" 2>/dev/null; }
  done
done
"

fi

echo "$LOG"
