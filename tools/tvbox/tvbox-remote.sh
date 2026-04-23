#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

# Defaults can be overridden by env. TVBOX_PASS is intentionally required.
HOST="${TVBOX_HOST:-}"
USER_NAME="${TVBOX_USER:-root}"
PASS="${TVBOX_PASS:-}"
KNOWN_HOSTS="${TVBOX_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}"
TOOLS_DIR="${TVBOX_TOOLS_DIR:-$SCRIPT_DIR}"
REMOTE_DIR="${TVBOX_REMOTE_DIR:-/root}"
LOCAL_LOG_DIR="${TVBOX_LOG_DIR:-$REPO_DIR/logs/lantest}"
AUTH_BACKEND="${TVBOX_AUTH_BACKEND:-auto}" # auto|sshpass|expect

SUBCMD="${1:-all}"
MODE="${2:-all}"

shift $(( $# > 0 ? 1 : 0 )) || true
if [ "$SUBCMD" = "run" ] || [ "$SUBCMD" = "all" ]; then
  shift $(( $# > 0 ? 1 : 0 )) || true
fi
EXTRA_CMD="$*"

SSH_COMMON_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$KNOWN_HOSTS"
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o ConnectTimeout=8
)

usage() {
  cat <<'__USAGE__'
Usage:
  ./tvbox-remote.sh push
  ./tvbox-remote.sh run [quick|all|port|mdio|irq|gpio|i2c|bt]
  ./tvbox-remote.sh pull
  ./tvbox-remote.sh all [quick|all|port|mdio|irq|gpio|i2c|bt]
  ./tvbox-remote.sh bt
  ./tvbox-remote.sh cmd '<remote command>'

Override with env:
  TVBOX_HOST, TVBOX_USER, TVBOX_PASS, TVBOX_LOG_DIR, TVBOX_TOOLS_DIR,
  TVBOX_AUTH_BACKEND=auto|sshpass|expect
__USAGE__
}

case "$SUBCMD" in
  -h|--help|help)
    usage
    exit 0
    ;;
esac

backend=""

detect_backend() {
  if [ -z "$HOST" ] || [ -z "$PASS" ]; then
    echo "set TVBOX_HOST and TVBOX_PASS in the environment" >&2
    exit 2
  fi

  if [ "$AUTH_BACKEND" = "sshpass" ] || [ "$AUTH_BACKEND" = "expect" ]; then
    backend="$AUTH_BACKEND"
  elif [ "$AUTH_BACKEND" = "auto" ]; then
    if command -v sshpass >/dev/null 2>&1; then
      backend="sshpass"
    elif command -v expect >/dev/null 2>&1; then
      backend="expect"
    else
      echo "need sshpass or expect on host"
      exit 2
    fi
  else
    echo "invalid TVBOX_AUTH_BACKEND=$AUTH_BACKEND"
    exit 2
  fi

  if [ "$backend" = "sshpass" ] && ! command -v sshpass >/dev/null 2>&1; then
    echo "sshpass backend selected but sshpass not found"
    exit 2
  fi
  if [ "$backend" = "expect" ] && ! command -v expect >/dev/null 2>&1; then
    echo "expect backend selected but expect not found"
    exit 2
  fi
}

reset_host_key() {
  mkdir -p "$(dirname "$KNOWN_HOSTS")"
  touch "$KNOWN_HOSTS"
  ssh-keygen -f "$KNOWN_HOSTS" -R "$HOST" >/dev/null 2>&1 || true
}

ssh_run_sshpass() {
  local cmd="$1"
  sshpass -p "$PASS" ssh "${SSH_COMMON_OPTS[@]}" "$USER_NAME@$HOST" "$cmd"
}

scp_to_sshpass() {
  local src="$1"
  local dst="$2"
  sshpass -p "$PASS" scp "${SSH_COMMON_OPTS[@]}" "$src" "$dst"
}

scp_from_sshpass() {
  local src="$1"
  local dst="$2"
  sshpass -p "$PASS" scp "${SSH_COMMON_OPTS[@]}" "$src" "$dst"
}

ssh_run_expect() {
  local cmd="$1"
  expect - "$PASS" "$USER_NAME@$HOST" "$cmd" "$KNOWN_HOSTS" <<'__EXPECT_SSH__'
set timeout -1
set pass [lindex $argv 0]
set target [lindex $argv 1]
set cmd [lindex $argv 2]
set known [lindex $argv 3]
spawn ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=8 $target $cmd
expect {
  -re "yes/no" { send "yes\r"; exp_continue }
  -re "(?i)password:" { send "$pass\r"; exp_continue }
  eof
}
catch wait result
exit [lindex $result 3]
__EXPECT_SSH__
}

scp_to_expect() {
  local src="$1"
  local dst="$2"
  expect - "$PASS" "$src" "$dst" "$KNOWN_HOSTS" <<'__EXPECT_SCP_TO__'
set timeout -1
set pass [lindex $argv 0]
set src [lindex $argv 1]
set dst [lindex $argv 2]
set known [lindex $argv 3]
spawn scp -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=8 $src $dst
expect {
  -re "yes/no" { send "yes\r"; exp_continue }
  -re "(?i)password:" { send "$pass\r"; exp_continue }
  eof
}
catch wait result
exit [lindex $result 3]
__EXPECT_SCP_TO__
}

scp_from_expect() {
  local src="$1"
  local dst="$2"
  expect - "$PASS" "$src" "$dst" "$KNOWN_HOSTS" <<'__EXPECT_SCP_FROM__'
set timeout -1
set pass [lindex $argv 0]
set src [lindex $argv 1]
set dst [lindex $argv 2]
set known [lindex $argv 3]
spawn scp -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known -o PreferredAuthentications=password -o PubkeyAuthentication=no -o ConnectTimeout=8 $src $dst
expect {
  -re "yes/no" { send "yes\r"; exp_continue }
  -re "(?i)password:" { send "$pass\r"; exp_continue }
  eof
}
catch wait result
exit [lindex $result 3]
__EXPECT_SCP_FROM__
}

ssh_run() {
  local cmd="$1"
  if [ "$backend" = "sshpass" ]; then
    ssh_run_sshpass "$cmd"
  else
    ssh_run_expect "$cmd"
  fi
}

scp_to() {
  local src="$1"
  local dst="$2"
  if [ "$backend" = "sshpass" ]; then
    scp_to_sshpass "$src" "$dst"
  else
    scp_to_expect "$src" "$dst"
  fi
}

scp_from() {
  local src="$1"
  local dst="$2"
  if [ "$backend" = "sshpass" ]; then
    scp_from_sshpass "$src" "$dst"
  else
    scp_from_expect "$src" "$dst"
  fi
}

push_tools() {
  reset_host_key
  scp_to "$TOOLS_DIR/lantest.sh" "$USER_NAME@$HOST:$REMOTE_DIR/"
  scp_to "$TOOLS_DIR/porttest.sh" "$USER_NAME@$HOST:$REMOTE_DIR/"
  scp_to "$TOOLS_DIR/gpiotest.sh" "$USER_NAME@$HOST:$REMOTE_DIR/"
  scp_to "$TOOLS_DIR/irqtest.sh" "$USER_NAME@$HOST:$REMOTE_DIR/"
  ssh_run "chmod +x $REMOTE_DIR/lantest.sh $REMOTE_DIR/porttest.sh $REMOTE_DIR/gpiotest.sh $REMOTE_DIR/irqtest.sh 2>/dev/null || true"
}

run_lantest() {
  local mode="$1"
  ssh_run "LANTEST_SKIP_INSTALL='${LANTEST_SKIP_INSTALL:-0}' LANTEST_WITH_I2C='${LANTEST_WITH_I2C:-0}' $REMOTE_DIR/lantest.sh $mode /tmp"
}

run_bt_audit() {
  ssh_run "LANTEST_SKIP_INSTALL='${LANTEST_SKIP_INSTALL:-0}' LANTEST_WITH_I2C='${LANTEST_WITH_I2C:-0}' $REMOTE_DIR/lantest.sh bt /tmp"
}

pull_logs() {
  mkdir -p "$LOCAL_LOG_DIR"
  scp_from "$USER_NAME@$HOST:/tmp/lantest_*.log*" "$LOCAL_LOG_DIR/" || true
  ls -1t "$LOCAL_LOG_DIR"/lantest_*.log* 2>/dev/null | head -n "${TVBOX_PULL_LIST_LIMIT:-20}" || true
}

cmd_remote() {
  local cmd="$1"
  ssh_run "$cmd"
}

detect_backend
echo "auth backend: $backend"

case "$SUBCMD" in
  push)
    push_tools
    ;;
  run)
    if [ "$MODE" = "bt" ]; then
      run_bt_audit
    else
      run_lantest "$MODE"
    fi
    ;;
  pull)
    pull_logs
    ;;
  all)
    push_tools
    if [ "$MODE" = "bt" ]; then
      run_bt_audit
    else
      run_lantest "$MODE"
    fi
    pull_logs
    ;;
  bt)
    push_tools
    run_bt_audit
    pull_logs
    ;;
  cmd)
    if [ -z "$EXTRA_CMD" ]; then
      echo "empty remote command"
      usage
      exit 2
    fi
    cmd_remote "$EXTRA_CMD"
    ;;
  *)
    usage
    exit 2
    ;;
esac
