#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PS1_SRC="${SCRIPT_DIR}/com6-capture.ps1"
WIN_PS1="/mnt/c/Windows/Temp/com6-capture.ps1"
PORT_NAME="${TVBOX_SERIAL_PORT:-}"
BAUD="115200"
SECONDS="20"
OUTFILE='C:\Windows\Temp\com6-capture.log'

usage() {
  cat <<'__USAGE__'
Usage:
  ./com6-capture.sh --port <COMx> [--seconds 20] [--outfile C:\Windows\Temp\com6-capture.log]

Environment:
  TVBOX_SERIAL_PORT can provide the default --port value.

Note:
  This helper requires Windows + WSL because it uses powershell.exe and the
  Windows COM port API.
__USAGE__
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --port) PORT_NAME="$2"; shift 2 ;;
    --baud) BAUD="$2"; shift 2 ;;
    --seconds) SECONDS="$2"; shift 2 ;;
    --outfile) OUTFILE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$PORT_NAME" ]; then
  usage >&2
  echo "set TVBOX_SERIAL_PORT or pass --port" >&2
  exit 2
fi

cp "$PS1_SRC" "$WIN_PS1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Windows\Temp\com6-capture.ps1' \
  -PortName "$PORT_NAME" \
  -Baud "$BAUD" \
  -Seconds "$SECONDS" \
  -OutFile "$OUTFILE"
