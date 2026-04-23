#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PS1_SRC="${SCRIPT_DIR}/com6-uboot.ps1"
WIN_PS1="/mnt/c/Windows/Temp/com6-uboot.ps1"

PORT_NAME="${TVBOX_SERIAL_PORT:-}"
BAUD="115200"
CHAR_DELAY_MS="18"
WAIT_LOOPS="32"
WAIT_MS="250"
INTERRUPT=0
ALLOW_LIVE_SHELL=0

usage() {
  cat <<'__USAGE__'
Usage:
  ./com6-uboot.sh --port <COMx> [options] [--] [u-boot command...]

Options:
  --baud 115200
  --char-delay-ms 18
  --wait-loops 32
  --wait-ms 250
  --interrupt
  --allow-live-shell

Environment:
  TVBOX_SERIAL_PORT can provide the default --port value.

Note:
  This helper requires Windows + WSL because it uses powershell.exe and the
  Windows COM port API. It refuses to send commands unless --interrupt or
  --allow-live-shell is explicitly provided.
__USAGE__
}

args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --port) PORT_NAME="$2"; shift 2 ;;
    --baud) BAUD="$2"; shift 2 ;;
    --char-delay-ms) CHAR_DELAY_MS="$2"; shift 2 ;;
    --wait-loops) WAIT_LOOPS="$2"; shift 2 ;;
    --wait-ms) WAIT_MS="$2"; shift 2 ;;
    --interrupt) INTERRUPT=1; shift ;;
    --allow-live-shell) ALLOW_LIVE_SHELL=1; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

while [ $# -gt 0 ]; do
  args+=("$1")
  shift
done

if [ -z "$PORT_NAME" ]; then
  usage >&2
  echo "set TVBOX_SERIAL_PORT or pass --port" >&2
  exit 2
fi

cp "$PS1_SRC" "$WIN_PS1"

pwsh_args=(
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Windows\Temp\com6-uboot.ps1'
  -PortName "$PORT_NAME"
  -Baud "$BAUD"
  -CharDelayMs "$CHAR_DELAY_MS"
  -WaitLoops "$WAIT_LOOPS"
  -WaitMs "$WAIT_MS"
)

if [ "$INTERRUPT" -eq 1 ]; then
  pwsh_args+=( -Interrupt )
fi

if [ ${#args[@]} -gt 0 ] && [ "$INTERRUPT" -ne 1 ] && [ "$ALLOW_LIVE_SHELL" -ne 1 ]; then
  echo "refusing to send serial commands without --interrupt or --allow-live-shell" >&2
  echo "use com6-capture.sh for passive Linux runtime capture" >&2
  exit 3
fi

if [ ${#args[@]} -gt 0 ]; then
  joined=""
  for cmd in "${args[@]}"; do
    if [ -n "$joined" ]; then
      joined+=$'\n'
    fi
    joined+="$cmd"
  done
  pwsh_args+=( -Commands "$joined" )
fi

"${pwsh_args[@]}"
