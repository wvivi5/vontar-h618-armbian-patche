#!/usr/bin/env bash
set -u

MODE="${1:-quick}"
OUTDIR="${2:-/tmp}"
TS="$(date +%Y%m%d_%H%M%S)"
HOST="$(hostname 2>/dev/null || echo unknown)"
SKIP_INSTALL="${LANTEST_SKIP_INSTALL:-0}"
WITH_I2C="${LANTEST_WITH_I2C:-0}"

dt_last_u32_hex() {
  local p="$1"
  if [ ! -e "$p" ]; then
    echo "na"
    return
  fi
  od -An -tx4 -v "$p" 2>/dev/null | awk '{for(i=1;i<=NF;i++) v=$i} END{ if(v=="") {print "na"} else {v=tolower(v); sub(/^0+/,"",v); if(v=="") v="0"; print v} }'
}

dt_first_u32_hex8() {
  local p="$1"
  if [ ! -e "$p" ]; then
    echo "na"
    return
  fi
  od -An -tx4 -v "$p" 2>/dev/null | awk '{for(i=1;i<=NF;i++) {print tolower($i); exit}} END{if(NR==0) print "na"}'
}

RST_HEX="$(dt_last_u32_hex /proc/device-tree/soc/ethernet@5030000/resets)"
CLK_HEX="$(dt_last_u32_hex /proc/device-tree/soc/ethernet@5030000/clocks)"
SYSCON_HEX="$(dt_last_u32_hex /proc/device-tree/soc/ethernet@5030000/syscon)"
LOG="${OUTDIR%/}/lantest_${HOST}_${MODE}_r${RST_HEX}_c${CLK_HEX}_s${SYSCON_HEX}_${TS}.log"

mkdir -p "$OUTDIR" 2>/dev/null || true
exec > >(tee -a "$LOG") 2>&1

section() {
  echo
  echo "===== $1 ====="
}

run_cmd() {
  local cmd="$1"
  echo "+ $cmd"
  bash -lc "$cmd"
  echo "[rc=$?]"
}

dump_str_prop() {
  local p="$1"
  if [ -e "$p" ]; then
    run_cmd "tr '\\0' '\\n' < '$p'"
  else
    echo "$p: MISSING"
  fi
}

dump_hex_prop() {
  local p="$1"
  if [ -e "$p" ]; then
    run_cmd "hexdump -Cv '$p'"
  else
    echo "$p: MISSING"
  fi
}

ensure_tools() {
  section "TOOLS_CHECK"
  run_cmd "command -v dtc || true"
  run_cmd "command -v ethtool || true"
  run_cmd "command -v i2cdetect || true"
  run_cmd "command -v bluetoothctl || true"
  run_cmd "command -v btmgmt || true"
  run_cmd "command -v hciconfig || true"
  run_cmd "command -v rfkill || true"
  run_cmd "command -v gpioinfo || true"

  if [ "$SKIP_INSTALL" = "1" ]; then
    echo "LANTEST_SKIP_INSTALL=1, apt install skipped"
    return
  fi

  local need=()
  command -v dtc >/dev/null 2>&1 || need+=("device-tree-compiler")
  command -v ethtool >/dev/null 2>&1 || need+=("ethtool")
  command -v i2cdetect >/dev/null 2>&1 || need+=("i2c-tools")
  command -v bluetoothctl >/dev/null 2>&1 || need+=("bluez")
  command -v btmgmt >/dev/null 2>&1 || need+=("bluez")
  command -v hciconfig >/dev/null 2>&1 || need+=("bluez")
  command -v rfkill >/dev/null 2>&1 || need+=("rfkill")
  command -v gpioinfo >/dev/null 2>&1 || need+=("gpiod")

  if [ ${#need[@]} -eq 0 ]; then
    echo "tools already installed"
    return
  fi

  local apt_prefix=""
  if [ "$(id -u)" -eq 0 ]; then
    apt_prefix="apt-get"
  elif command -v sudo >/dev/null 2>&1; then
    apt_prefix="sudo apt-get"
  fi

  if [ -z "$apt_prefix" ]; then
    echo "cannot install tools automatically: no root and no sudo"
    return
  fi

  run_cmd "$apt_prefix update"
  run_cmd "$apt_prefix install -y ${need[*]}"
}

find_lan_ifaces() {
  local out=""
  if [ -d /sys/bus/platform/devices/5030000.ethernet/net ]; then
    out+=" $(ls -1 /sys/bus/platform/devices/5030000.ethernet/net 2>/dev/null)"
  fi
  if [ -d /sys/bus/platform/devices/5020000.ethernet/net ]; then
    out+=" $(ls -1 /sys/bus/platform/devices/5020000.ethernet/net 2>/dev/null)"
  fi
  if [ -z "${out// /}" ]; then
    out="$(ls -1 /sys/class/net 2>/dev/null | grep -E '^(end|eth)[0-9]+' || true)"
  fi
  echo "$out" | xargs -n1 2>/dev/null | sort -u
}

collect_base() {
  section "BASE"
  run_cmd "date -Is"
  run_cmd "uname -a"
  run_cmd "uptime"
  run_cmd "cat /etc/os-release 2>/dev/null || true"
  run_cmd "cat /proc/cmdline"
  run_cmd "ip -br link"
  run_cmd "ip -br addr"
  run_cmd "ls -l /boot 2>/dev/null || true"
  run_cmd "cat /boot/armbianEnv.txt 2>/dev/null || true"
  run_cmd "cat /boot/extlinux/extlinux.conf 2>/dev/null || true"
  run_cmd "dmesg -T | grep -Ei 'dwmac|stmmac|gmac|ethernet@50|5030000|5020000|mdio|phy|reset timeout|Cannot attach|Link is Up|probe with driver' | tail -n 400"
}

collect_dt_runtime_node() {
  local n="$1"
  section "RUNTIME_DT_${n##*/}"
  dump_str_prop "$n/status"
  dump_str_prop "$n/compatible"
  dump_str_prop "$n/phy-mode"
  dump_str_prop "$n/interrupt-names"
  dump_str_prop "$n/clock-names"
  dump_str_prop "$n/reset-names"
  dump_hex_prop "$n/reg"
  dump_hex_prop "$n/interrupts"
  dump_hex_prop "$n/clocks"
  dump_hex_prop "$n/resets"
  dump_hex_prop "$n/syscon"
  dump_hex_prop "$n/pinctrl-0"
  dump_hex_prop "$n/phy-supply"
  dump_hex_prop "$n/phy-io-supply"
}

collect_dt_runtime() {
  collect_dt_runtime_node "/proc/device-tree/soc/ethernet@5030000"
  collect_dt_runtime_node "/proc/device-tree/soc/ethernet@5020000"
}

collect_clk() {
  section "CLOCKS"
  run_cmd "mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true"
  run_cmd "grep -Ei 'emac|gmac|stmmac|ephy|25m|rmii|mdio|pll|periph' /sys/kernel/debug/clk/clk_summary 2>/dev/null || true"
}

collect_regulator() {
  section "REGULATORS"
  run_cmd "for r in /sys/class/regulator/regulator*; do [ -d \"\$r\" ] || continue; n=\$(cat \"\$r/name\" 2>/dev/null || echo noname); s=\$(cat \"\$r/state\" 2>/dev/null || echo nostate); v=\$(cat \"\$r/microvolts\" 2>/dev/null || echo novolt); echo \"\$r name=\$n state=\$s uV=\$v\"; done"
  run_cmd "for r in /sys/class/regulator/regulator*; do [ -d \"\$r\" ] || continue; n=\$(cat \"\$r/name\" 2>/dev/null || true); echo \"\$n\" | grep -Eqi 'phy|emac|gmac|aldo|dldo|vcc' && { echo \"--- \$r ---\"; cat \"\$r/name\" 2>/dev/null; cat \"\$r/state\" 2>/dev/null; cat \"\$r/microvolts\" 2>/dev/null; }; done"
}

collect_syscon_regmap() {
  section "SYSCON_REGMAP"
  run_cmd "mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true"
  run_cmd "ls -d /sys/kernel/debug/regmap/*syscon* 2>/dev/null || true"
  run_cmd "for d in /sys/kernel/debug/regmap/*syscon*; do [ -d \"\$d\" ] || continue; echo \"--- \$d ---\"; if [ -f \"\$d/registers\" ]; then grep -Ei '^(030|034|500|580|4bf|4be):' \"\$d/registers\" 2>/dev/null || true; fi; done"
}

collect_sanity() {
  section "SANITY"
  local phy_supply_hex
  local ifaces
  phy_supply_hex="$(dt_first_u32_hex8 /proc/device-tree/soc/ethernet@5030000/phy-supply)"
  ifaces="$(find_lan_ifaces)"
  echo "PHY_SUPPLY_PHANDLE_HEX=${phy_supply_hex}"
  echo "SANITY_LAN_IFACES=${ifaces:-none}"
  dump_hex_prop "/proc/device-tree/soc/ethernet@5030000/phy-supply"
  run_cmd "if [ \"$phy_supply_hex\" != \"na\" ]; then for p in \$(find /proc/device-tree \\( -name phandle -o -name linux,phandle \\) 2>/dev/null); do v=\$(od -An -tx4 -v \"\$p\" 2>/dev/null | awk '{for(i=1;i<=NF;i++) {print tolower(\$i); exit}}'); [ \"\$v\" = \"$phy_supply_hex\" ] && echo \"PHY_SUPPLY_MATCH=\$p\"; done; fi"
  run_cmd "dtc -I dtb -O dts /boot/dtb/allwinner/vontar-h618-running.dtb 2>/dev/null | sed -n '/ethernet@5030000 {/,/^[[:space:]]*};$/p' | sed -n '1,80p'"
  run_cmd "dtc -I dtb -O dts /boot/dtb/allwinner/vontar-h618-running.dtb 2>/dev/null | grep -n -B2 -A5 'phandle = <0x${phy_supply_hex}>' || true"
  run_cmd "grep -Ei '3000034|03000034|3000000|syscon|5030000' /proc/iomem || true"
  run_cmd "dmesg -T | grep -Ei 'dummy regulator|phy-supply|reg_aldo1|aldo1|5030000|gmac|emac-25m|bus-emac1' | tail -n 200"
  run_cmd "for r in /sys/class/regulator/regulator*; do [ -d \"\$r\" ] || continue; n=\$(cat \"\$r/name\" 2>/dev/null || true); s=\$(cat \"\$r/state\" 2>/dev/null || true); v=\$(cat \"\$r/microvolts\" 2>/dev/null || true); echo \"\$r name=\$n state=\$s uV=\$v\"; done | grep -Ei 'aldo1|vcc1v8|phy|gmac|emac' || true"
  run_cmd "mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true"
  run_cmd "grep -Ei 'emac|gmac|25m|ephy' /sys/kernel/debug/clk/clk_summary 2>/dev/null || true"
  local i=""
  for i in $ifaces; do
    echo "--- sanity ifup: $i ---"
    run_cmd "ip link set '$i' up 2>/dev/null || ip link set '$i' up || true"
  done
  run_cmd "sleep 2"
  run_cmd "for r in /sys/class/regulator/regulator*; do [ -d \"\$r\" ] || continue; n=\$(cat \"\$r/name\" 2>/dev/null || true); s=\$(cat \"\$r/state\" 2>/dev/null || true); v=\$(cat \"\$r/microvolts\" 2>/dev/null || true); echo \"\$r name=\$n state=\$s uV=\$v\"; done | grep -Ei 'aldo1|vcc1v8|phy|gmac|emac' || true"
  run_cmd "grep -Ei 'emac|gmac|25m|ephy' /sys/kernel/debug/clk/clk_summary 2>/dev/null || true"
}

collect_i2c() {
  section "I2C"
  run_cmd "ls -l /dev/i2c-* 2>/dev/null || true"
  run_cmd "i2cdetect -l 2>/dev/null || true"
  run_cmd "dmesg -T | grep -Ei 'i2c|twi|axp|pmic' | tail -n 200"

  local dev=""
  for dev in /dev/i2c-*; do
    [ -e "$dev" ] || continue
    local bus="${dev##*/i2c-}"
    echo "--- i2c bus $bus scan ---"
    run_cmd "i2cdetect -y '$bus' 2>/dev/null || true"
    run_cmd "for a in 0x34 0x35 0x36 0x3a; do i2cget -y '$bus' \$a 0x00 2>/dev/null && i2cget -y '$bus' \$a 0x03 2>/dev/null; done || true"
  done
}

collect_mdio() {
  section "MDIO_PHY"
  run_cmd "ls -la /sys/bus/mdio_bus/devices 2>/dev/null || true"
  local dev=""
  for dev in /sys/bus/mdio_bus/devices/*; do
    [ -e "$dev" ] || continue
    echo "--- $dev ---"
    run_cmd "cat '$dev/uevent' 2>/dev/null || true"
    run_cmd "cat '$dev/phy_id' 2>/dev/null || true"
    run_cmd "cat '$dev/name' 2>/dev/null || true"
    run_cmd "cat '$dev/supported' 2>/dev/null || true"
    run_cmd "cat '$dev/advertising' 2>/dev/null || true"
    run_cmd "cat '$dev/lp_advertising' 2>/dev/null || true"
  done
}

collect_port() {
  section "PORT_LINK"
  local ifaces
  ifaces="$(find_lan_ifaces)"
  echo "LAN_IFACES: ${ifaces:-none}"
  run_cmd "ls -l /sys/bus/platform/devices/5030000.ethernet/net 2>/dev/null || true"
  run_cmd "ls -l /sys/bus/platform/devices/5020000.ethernet/net 2>/dev/null || true"
  local i=""
  for i in $ifaces; do
    echo "--- iface: $i ---"
    run_cmd "ip -d link show '$i' 2>/dev/null || true"
    run_cmd "cat /sys/class/net/'$i'/operstate 2>/dev/null || true"
    run_cmd "cat /sys/class/net/'$i'/carrier 2>/dev/null || true"
    run_cmd "ethtool -i '$i' 2>/dev/null || true"
    run_cmd "ethtool '$i' 2>/dev/null || true"
    run_cmd "ethtool -k '$i' 2>/dev/null || true"
    run_cmd "ethtool --show-eee '$i' 2>/dev/null || true"
    run_cmd "ip -s link show '$i' 2>/dev/null || true"
  done
}

collect_irq() {
  section "IRQ"
  run_cmd "cat /proc/interrupts"
  run_cmd "grep -Ei 'dwmac|stmmac|gmac|eth|5030000|5020000' /proc/interrupts || true"
}

collect_ifup_probe() {
  section "IFUP_PROBE"
  local ifaces
  ifaces="$(find_lan_ifaces)"
  echo "LAN_IFACES_FOR_IFUP: ${ifaces:-none}"
  run_cmd "grep -Ei 'dwmac|stmmac|gmac|eth|5030000|5020000' /proc/interrupts || true"
  local i=""
  for i in $ifaces; do
    echo "--- ifup: $i ---"
    run_cmd "ip link set '$i' up 2>/dev/null || ip link set '$i' up || true"
    run_cmd "ip -d link show '$i' 2>/dev/null || true"
    run_cmd "cat /sys/class/net/'$i'/operstate 2>/dev/null || true"
    run_cmd "cat /sys/class/net/'$i'/carrier 2>/dev/null || true"
    run_cmd "ethtool '$i' 2>/dev/null || true"
    run_cmd "dmesg -T | grep -Ei '5030000|5020000|dwmac|stmmac|Cannot attach|validation of rmii|reset timeout|Link is Up|No PHY' | tail -n 120"
  done
  run_cmd "grep -Ei 'dwmac|stmmac|gmac|eth|5030000|5020000' /proc/interrupts || true"
}

collect_gpio() {
  section "GPIO_PINCTRL"
  run_cmd "mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true"
  run_cmd "gpioinfo 2>/dev/null | grep -Ei 'PA[0-9]+|emac|rmii|mii|rgmii|eth|gmac' || true"
  run_cmd "grep -R -nEi 'PA[0-9]+|emac|rmii|mii|rgmii|eth|gmac' /sys/kernel/debug/pinctrl/*/pinmux-pins /sys/kernel/debug/pinctrl/*/pins /sys/kernel/debug/pinctrl/*/pinconf-pins 2>/dev/null || true"
}

collect_bt() {
  section "BT"
  run_cmd "mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true"
  run_cmd "date -Is"
  run_cmd "uname -a"
  run_cmd "cat /etc/os-release 2>/dev/null || true"
  run_cmd "command -v bluetoothctl || true; command -v btmgmt || true; command -v hciconfig || true; command -v rfkill || true; command -v gpioinfo || true"
  run_cmd "ls -l /dev/gpiochip* 2>/dev/null || true"
  run_cmd "ls -l /sys/class/bluetooth 2>/dev/null || true"
  run_cmd "find /sys/class/bluetooth /sys/devices /sys/bus -maxdepth 6 2>/dev/null | grep -Ei 'hci|bluetooth|bt_hostwake|bt_wake|bt_rst|wlan_hostwake|wlan_regon|PG1[6-9]|uart1|5000400' | sort -u || true"
  run_cmd "rfkill list 2>/dev/null || true"
  run_cmd "ls -l /sys/class/rfkill 2>/dev/null || true"
  run_cmd "for d in /sys/class/rfkill/rfkill*; do [ -d \"\$d\" ] || continue; echo \"--- \$d ---\"; for f in name type state soft hard device; do [ -e \"\$d/\$f\" ] && { printf '%s=' \"\$f\"; cat \"\$d/\$f\" 2>/dev/null || readlink -f \"\$d/\$f\" 2>/dev/null; }; done; done"
  run_cmd "systemctl is-enabled bluetooth 2>/dev/null || true"
  run_cmd "systemctl is-active bluetooth 2>/dev/null || true"
  run_cmd "systemctl status bluetooth --no-pager -l 2>/dev/null || true"
  run_cmd "systemctl cat bluetooth 2>/dev/null || true"
  run_cmd "systemctl list-unit-files | grep -Ei '^bluetooth\\.service|bluetooth' || true"
  run_cmd "cat /etc/default/bluetooth 2>/dev/null || true"
  run_cmd "cat /etc/bluetooth/main.conf 2>/dev/null || true"
  run_cmd "grep -RniE 'bluetooth|hci|bcm|brcm|ttyAS1|ttyS1|rfkill|vendor.bluetooth|bluetooth_port|bdaddr|bt_rst|bt_wake|bt_hostwake' /etc/systemd /lib/systemd /usr/lib/systemd /etc/init.d /etc/udev/rules.d /lib/udev/rules.d /usr/lib/udev/rules.d /etc 2>/dev/null | head -n 400 || true"
  run_cmd "journalctl -b -u bluetooth --no-pager 2>/dev/null | grep -Ei 'bluetooth|hci|bcm|brcm|rfkill|ttyAS1|ttyS1|bt_|wakeup|reset|firmware' | tail -n 400 || true"
  run_cmd "journalctl -b --no-pager 2>/dev/null | grep -Ei 'bluetooth|hci|bcm|brcm|rfkill|ttyAS1|ttyS1|bt_|wakeup|reset|firmware' | tail -n 400 || true"
  run_cmd "dmesg -T | grep -Ei 'bluetooth|hci|bcm|brcm|rfkill|ttyAS1|ttyS1|bt_|wakeup|reset|firmware' | tail -n 400"
  run_cmd "cat /proc/bluetooth/sleep 2>/dev/null || true"
  run_cmd "getent passwd bluetooth 2>/dev/null || true"
  run_cmd "modinfo hci_uart 2>/dev/null || true"
  run_cmd "modinfo hci_bcm 2>/dev/null || true"
  run_cmd "lsmod 2>/dev/null | grep -Ei 'bluetooth|hci|bcm' || true"
  run_cmd "gpioinfo 2>/dev/null | grep -Ei 'bt_|wlan_|uart1|PG1[6-9]|PG[6-9]' || true"
  run_cmd "grep -R -nEi 'bt_|wlan_|uart1|PG1[6-9]|PG[6-9]|5000400' /sys/kernel/debug/pinctrl/*/pinmux-pins /sys/kernel/debug/pinctrl/*/pins /sys/kernel/debug/pinctrl/*/pinconf-pins 2>/dev/null || true"
  run_cmd "find /lib/firmware /usr/lib/firmware /vendor/firmware /etc/firmware 2>/dev/null | grep -iE '4334|ap6334|brcm|bcm|hcd|nvram|bluetooth' | sort -u || true"
  run_cmd "for d in /lib/firmware /usr/lib/firmware /vendor/firmware /etc/firmware; do [ -d \"\$d\" ] && { echo \"--- \$d ---\"; ls -l \"\$d\" 2>/dev/null | grep -Ei '4334|ap6334|brcm|bcm|hcd|nvram|bluetooth' || true; }; done"
  run_cmd "apt-cache policy bluez gpiod rfkill 2>/dev/null || true"
}

usage() {
  cat <<'__USAGE__'
Usage:
  ./lantest.sh quick [OUTDIR]
  ./lantest.sh irq   [OUTDIR]
  ./lantest.sh gpio  [OUTDIR]
  ./lantest.sh port  [OUTDIR]
  ./lantest.sh mdio  [OUTDIR]
  ./lantest.sh i2c   [OUTDIR]
  ./lantest.sh sanity [OUTDIR]
  ./lantest.sh all   [OUTDIR]
Env:
  LANTEST_SKIP_INSTALL=1   # skip apt-get phase
  LANTEST_WITH_I2C=1       # include I2C section in all mode
__USAGE__
}

section "LANTEST_START"
echo "MODE=$MODE"
echo "LOG=$LOG"
echo "META_RESET=0x$RST_HEX META_CLOCK=0x$CLK_HEX META_SYSCON=0x$SYSCON_HEX"

ensure_tools

case "$MODE" in
  quick)
    collect_base
    collect_port
    collect_mdio
    collect_ifup_probe
    collect_irq
    ;;
  irq)
    collect_base
    collect_irq
    ;;
  gpio)
    collect_base
    collect_gpio
    ;;
  port)
    collect_base
    collect_port
    collect_ifup_probe
    ;;
  mdio)
    collect_base
    collect_mdio
    ;;
  sanity)
    collect_base
    collect_dt_runtime
    collect_sanity
    ;;
  i2c)
    collect_base
    collect_i2c
    ;;
  bt)
    collect_base
    collect_bt
    ;;
  all)
    collect_base
    collect_dt_runtime
    collect_sanity
    collect_clk
    collect_regulator
    collect_syscon_regmap
    if [ "$WITH_I2C" = "1" ]; then
      collect_i2c
    else
      section "I2C"
      echo "skipped in all mode (set LANTEST_WITH_I2C=1 to enable)"
    fi
    collect_port
    collect_mdio
    collect_ifup_probe
    collect_irq
    collect_gpio
    collect_bt
    ;;
  *)
    usage
    exit 2
    ;;
esac

section "LANTEST_DONE"
echo "Saved: $LOG"
