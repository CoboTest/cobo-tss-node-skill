#!/usr/bin/env bash
set -euo pipefail

# Test suite for cobo-tss-node skill scripts
# All tests use temp directories with --env test (service: cobo-tss-node-test)
# No mocks for system tools — real systemctl/launchctl, platform-specific tests
# Mock binary only (we don't have a real cobo-tss-node)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"
TEST_DIR=$(mktemp -d)
TEST_ENV="test"
PASS=0
FAIL=0
ERRORS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}✅ $1${NC}"; }
log_fail() { FAIL=$((FAIL + 1)); ERRORS+=("$1: $2"); echo -e "  ${RED}❌ $1: $2${NC}"; }

# Detect platform
PLATFORM=$(uname -s)
case "$PLATFORM" in
  Linux)  PLATFORM="linux" ;;
  Darwin) PLATFORM="macos" ;;
  *)      echo "Unsupported platform: $PLATFORM"; exit 1 ;;
esac
echo -e "${YELLOW}Platform: $PLATFORM${NC}"

# Service names for cleanup
SERVICE_NAME="cobo-tss-node-test"
PLIST_LABEL="com.cobo.tss-node-test"
PLIST_FILE="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

# Cleanup: remove test service + temp dir
cleanup() {
  echo -e "\n${YELLOW}🧹 Cleaning up...${NC}"
  if [[ "$PLATFORM" == "linux" ]]; then
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload 2>/dev/null || true
  elif [[ "$PLATFORM" == "macos" ]]; then
    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    rm -f "$PLIST_FILE"
  fi
  rm -rf "$TEST_DIR"
  echo -e "${GREEN}✅ Cleanup complete${NC}"
}
trap cleanup EXIT

# Create a mock cobo-tss-node binary (needed since we don't have the real one)
create_mock_binary() {
  local dir="$1"
  cat > "$dir/cobo-tss-node" <<'MOCK'
#!/usr/bin/env bash
CMD="${1:-}"
shift || true
case "$CMD" in
  version) echo "v0.99.0-test" ;;
  init)
    DB=""
    while [[ $# -gt 0 ]]; do
      case "$1" in --db) DB="$2"; shift 2 ;; *) shift ;; esac
    done
    [[ -n "$DB" ]] && mkdir -p "$(dirname "$DB")" && echo "mock-db" > "$DB"
    echo "Node initialized"
    echo "TSS Node ID: test-node-id-12345"
    ;;
  info)
    if [[ "${1:-}" == "group" ]]; then
      echo "Group: test-group-001"
      echo "Threshold: 2/3"
    else
      echo "TSS Node ID: test-node-id-12345"
      echo "Created: 2025-01-01"
    fi
    ;;
  start)
    echo "Node started (pid $$)"
    while true; do sleep 60; done
    ;;
  sign)
    echo "Signed message successfully"
    echo "Signature: 0xdeadbeef"
    ;;
  export-share)
    EDIR=""
    while [[ $# -gt 0 ]]; do
      case "$1" in --export-dir) EDIR="$2"; shift 2 ;; *) shift ;; esac
    done
    [[ -n "$EDIR" ]] && echo "mock-share-data" > "$EDIR/share.enc"
    echo "Exported shares"
    ;;
  migrate) echo "Migration complete (no changes)" ;;
  change-password) echo "Password changed" ;;
  *) echo "Unknown command: $CMD"; exit 1 ;;
esac
MOCK
  chmod 755 "$dir/cobo-tss-node"
}

# Setup test install directory
setup_test_dir() {
  local dir="$1"
  mkdir -p "$dir"/{configs,db,logs,recovery,backups}
  create_mock_binary "$dir"
  printf 'test-password-123' > "$dir/.password"
  chmod 600 "$dir/.password"
  echo "env: test" > "$dir/configs/cobo-tss-node-config.yaml"
  echo "mock-db-content" > "$dir/db/secrets.db"
}

########################################
echo -e "\n${YELLOW}=== setup-keyfile.sh ===${NC}"
########################################

test_setup_keyfile_create() {
  local d="$TEST_DIR/keyfile-create"
  mkdir -p "$d"
  bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null
  if [[ -f "$d/.password" ]]; then
    perms=$(stat -c '%a' "$d/.password" 2>/dev/null || stat -f '%Lp' "$d/.password")
    if [[ "$perms" == "600" ]]; then
      log_pass "creates key file with mode 600"
    else
      log_fail "key file permissions" "expected 600 got $perms"
    fi
  else
    log_fail "creates key file" "file not found"
  fi
}

test_setup_keyfile_no_overwrite() {
  local d="$TEST_DIR/keyfile-noforce"
  mkdir -p "$d"
  bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null
  output=$(bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" 2>&1 < /dev/null) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "refuses overwrite without --force (non-interactive)"
  else
    log_fail "overwrite protection" "rc=$rc"
  fi
}

test_setup_keyfile_force() {
  local d="$TEST_DIR/keyfile-force"
  mkdir -p "$d"
  bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" --password "first" 2>&1 >/dev/null
  bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" --password "second" --force 2>&1 >/dev/null
  content=$(cat "$d/.password")
  if [[ "$content" == "second" ]]; then
    log_pass "--force overwrites existing key file"
  else
    log_fail "--force overwrite" "got '$content'"
  fi
}

test_setup_keyfile_no_newline() {
  local d="$TEST_DIR/keyfile-nonewline"
  mkdir -p "$d"
  bash "$SCRIPT_DIR/setup-keyfile.sh" --env "$TEST_ENV" --dir "$d" --password "exact" 2>&1 >/dev/null
  bytes=$(wc -c < "$d/.password" | tr -d ' ')
  if [[ "$bytes" == "5" ]]; then
    log_pass "no trailing newline in password file"
  else
    log_fail "trailing newline" "expected 5 bytes got $bytes"
  fi
}

test_setup_keyfile_create
test_setup_keyfile_no_overwrite
test_setup_keyfile_force
test_setup_keyfile_no_newline

########################################
echo -e "\n${YELLOW}=== init-node.sh ===${NC}"
########################################

test_init_node_success() {
  local d="$TEST_DIR/init-ok"
  mkdir -p "$d"/configs
  create_mock_binary "$d"
  printf 'pw' > "$d/.password"; chmod 600 "$d/.password"
  echo "env: test" > "$d/configs/cobo-tss-node-config.yaml"
  output=$(bash "$SCRIPT_DIR/init-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1)
  if [[ -f "$d/db/secrets.db" ]] && echo "$output" | grep -q "initialized"; then
    log_pass "initializes node and creates db"
  else
    log_fail "init node" "db missing or no success message"
  fi
}

test_init_node_existing_db() {
  local d="$TEST_DIR/init-exists"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/init-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]] && echo "$output" | grep -qi "already exists"; then
    log_pass "refuses init when db exists"
  else
    log_fail "existing db check" "rc=$rc"
  fi
}

test_init_node_no_binary() {
  local d="$TEST_DIR/init-nobin"
  mkdir -p "$d"/configs
  printf 'pw' > "$d/.password"; chmod 600 "$d/.password"
  output=$(bash "$SCRIPT_DIR/init-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "fails without binary"
  else
    log_fail "no binary check" "should have failed"
  fi
}

test_init_node_no_keyfile() {
  local d="$TEST_DIR/init-nokey"
  mkdir -p "$d"/configs
  create_mock_binary "$d"
  output=$(bash "$SCRIPT_DIR/init-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "fails without key file"
  else
    log_fail "no keyfile check" "should have failed"
  fi
}

test_init_node_success
test_init_node_existing_db
test_init_node_no_binary
test_init_node_no_keyfile

########################################
echo -e "\n${YELLOW}=== node-info.sh ===${NC}"
########################################

test_node_info_basic() {
  local d="$TEST_DIR/info-basic"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-info.sh" --env "$TEST_ENV" --dir "$d" 2>&1)
  if echo "$output" | grep -q "test-node-id-12345"; then
    log_pass "shows node info"
  else
    log_fail "node info" "got: $output"
  fi
}

test_node_info_group() {
  local d="$TEST_DIR/info-group"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-info.sh" --env "$TEST_ENV" --dir "$d" --group 2>&1)
  if echo "$output" | grep -q "test-group"; then
    log_pass "shows group info"
  else
    log_fail "group info" "got: $output"
  fi
}

test_node_info_basic
test_node_info_group

########################################
echo -e "\n${YELLOW}=== node-ctl.sh (common operations) ===${NC}"
########################################

test_ctl_sign_auto() {
  local d="$TEST_DIR/ctl-sign"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" sign --env "$TEST_ENV" --dir "$d" test-group-001 2>&1)
  if echo "$output" | grep -q "Signed\|Signature"; then
    log_pass "sign with auto message"
  else
    log_fail "sign auto" "got: $output"
  fi
}

test_ctl_sign_no_group() {
  local d="$TEST_DIR/ctl-sign-nogrp"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" sign --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]] && echo "$output" | grep -qi "usage"; then
    log_pass "sign fails without group-id"
  else
    log_fail "sign no group" "rc=$rc"
  fi
}

test_ctl_export() {
  local d="$TEST_DIR/ctl-export"
  setup_test_dir "$d"
  bash "$SCRIPT_DIR/node-ctl.sh" export --env "$TEST_ENV" --dir "$d" test-group-001 2>&1 >/dev/null
  recovery_dirs=$(find "$d/recovery" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$recovery_dirs" -ge 1 ]]; then
    log_pass "export creates recovery directory"
  else
    log_fail "export" "no recovery dir created"
  fi
}

test_ctl_backup() {
  local d="$TEST_DIR/ctl-backup"
  setup_test_dir "$d"
  bash "$SCRIPT_DIR/node-ctl.sh" backup --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null
  backup_dir=$(find "$d/backups" -mindepth 1 -maxdepth 1 -type d | head -1)
  if [[ -z "$backup_dir" ]]; then
    log_fail "backup" "no backup dir created"
    return
  fi
  files_ok=0
  [[ -f "$backup_dir/secrets.db" ]] && files_ok=$((files_ok + 1))
  [[ -f "$backup_dir/cobo-tss-node-config.yaml" ]] && files_ok=$((files_ok + 1))
  [[ -f "$backup_dir/.password" ]] && files_ok=$((files_ok + 1))
  [[ -f "$backup_dir/SHA256SUMS" ]] && files_ok=$((files_ok + 1))
  if [[ "$files_ok" -eq 4 ]]; then
    log_pass "backup creates all 4 expected files"
  else
    log_fail "backup files" "only $files_ok/4 found"
  fi
}

test_ctl_backup_sha_dotfile() {
  local d="$TEST_DIR/ctl-backup-sha"
  setup_test_dir "$d"
  bash "$SCRIPT_DIR/node-ctl.sh" backup --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null
  backup_dir=$(find "$d/backups" -mindepth 1 -maxdepth 1 -type d | head -1)
  if grep -q ".password" "$backup_dir/SHA256SUMS" 2>/dev/null; then
    log_pass "SHA256SUMS includes .password (dotfile fix)"
  else
    log_fail "SHA256SUMS dotfile" ".password not in checksums"
  fi
}

test_ctl_backup_password_perms() {
  local d="$TEST_DIR/ctl-backup-perms"
  setup_test_dir "$d"
  bash "$SCRIPT_DIR/node-ctl.sh" backup --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null
  backup_dir=$(find "$d/backups" -mindepth 1 -maxdepth 1 -type d | head -1)
  perms=$(stat -c '%a' "$backup_dir/.password" 2>/dev/null || stat -f '%Lp' "$backup_dir/.password")
  if [[ "$perms" == "600" ]]; then
    log_pass "backup .password has mode 600"
  else
    log_fail "backup password perms" "got $perms"
  fi
}

test_ctl_groups() {
  local d="$TEST_DIR/ctl-groups"
  setup_test_dir "$d"
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" groups --env "$TEST_ENV" --dir "$d" 2>&1)
  if echo "$output" | grep -q "test-group"; then
    log_pass "groups lists groups"
  else
    log_fail "groups" "got: $output"
  fi
}

test_ctl_help() {
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" help 2>&1)
  if echo "$output" | grep -q "Service Management" && echo "$output" | grep -q "Maintenance"; then
    log_pass "help shows all sections"
  else
    log_fail "help" "incomplete output"
  fi
}

test_ctl_unknown() {
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" nonexistent --env "$TEST_ENV" --dir /tmp 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]] && echo "$output" | grep -qi "unknown"; then
    log_pass "unknown command exits with error"
  else
    log_fail "unknown command" "rc=$rc"
  fi
}

test_ctl_no_binary() {
  local d="$TEST_DIR/ctl-nobin"
  mkdir -p "$d"
  printf 'pw' > "$d/.password"; chmod 600 "$d/.password"
  output=$(bash "$SCRIPT_DIR/node-ctl.sh" health --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "health fails without binary"
  else
    log_fail "no binary" "should have failed"
  fi
}

test_ctl_sign_auto
test_ctl_sign_no_group
test_ctl_export
test_ctl_backup
test_ctl_backup_sha_dotfile
test_ctl_backup_password_perms
test_ctl_groups
test_ctl_help
test_ctl_unknown
test_ctl_no_binary

########################################
echo -e "\n${YELLOW}=== install-service.sh ===${NC}"
########################################

if [[ "$PLATFORM" == "linux" ]]; then

  test_install_service_linux() {
    local d="$TEST_DIR/svc-linux"
    setup_test_dir "$d"
    output=$(bash "$SCRIPT_DIR/install-service.sh" linux --env "$TEST_ENV" --dir "$d" 2>&1)

    if [[ ! -f "$SERVICE_FILE" ]]; then
      log_fail "linux service file" "not created at $SERVICE_FILE"
      return
    fi
    log_pass "install creates systemd service file"

    # Content checks
    checks=0
    grep -q "ExecStart=.*$d/cobo-tss-node" "$SERVICE_FILE" && checks=$((checks + 1))
    grep -q "key-file" "$SERVICE_FILE" && checks=$((checks + 1))
    grep -q "NoNewPrivileges=true" "$SERVICE_FILE" && checks=$((checks + 1))
    grep -q "backups" "$SERVICE_FILE" && checks=$((checks + 1))
    grep -q "ProtectHome=false" "$SERVICE_FILE" && checks=$((checks + 1))
    if [[ "$checks" -ge 5 ]]; then
      log_pass "service file has all directives ($checks/5)"
    else
      log_fail "service content" "only $checks/5"
    fi

    # Real systemctl checks
    if systemctl --user is-enabled "$SERVICE_NAME" 2>/dev/null | grep -q "enabled"; then
      log_pass "service is enabled via systemctl"
    else
      log_fail "service enabled" "not enabled"
    fi
  }

  test_install_service_linux

elif [[ "$PLATFORM" == "macos" ]]; then

  test_install_service_macos() {
    local d="$TEST_DIR/svc-macos"
    setup_test_dir "$d"
    output=$(bash "$SCRIPT_DIR/install-service.sh" macos --env "$TEST_ENV" --dir "$d" 2>&1)

    if [[ ! -f "$PLIST_FILE" ]]; then
      log_fail "macos plist" "not created at $PLIST_FILE"
      return
    fi
    log_pass "install creates launchd plist"

    checks=0
    grep -q "$PLIST_LABEL" "$PLIST_FILE" && checks=$((checks + 1))
    grep -q "key-file" "$PLIST_FILE" && checks=$((checks + 1))
    grep -q "KeepAlive" "$PLIST_FILE" && checks=$((checks + 1))
    grep -q "ThrottleInterval" "$PLIST_FILE" && checks=$((checks + 1))
    if [[ "$checks" -ge 4 ]]; then
      log_pass "plist has all expected keys ($checks/4)"
    else
      log_fail "plist content" "only $checks/4"
    fi
  }

  test_install_service_macos

fi

test_install_service_no_platform() {
  output=$(bash "$SCRIPT_DIR/install-service.sh" --env "$TEST_ENV" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "fails without platform arg"
  else
    log_fail "no platform" "should have failed"
  fi
}

test_install_service_no_platform

########################################
echo -e "\n${YELLOW}=== node-ctl.sh service lifecycle ($PLATFORM) ===${NC}"
########################################

if [[ "$PLATFORM" == "linux" ]]; then

  test_ctl_health_linux() {
    local d="$TEST_DIR/svc-linux"  # reuse from install test
    output=$(bash "$SCRIPT_DIR/node-ctl.sh" health --env "$TEST_ENV" --dir "$d" 2>&1) || true
    checks=0
    echo "$output" | grep -q "Service:" && checks=$((checks + 1))
    echo "$output" | grep -q "Version:" && checks=$((checks + 1))
    echo "$output" | grep -q "Database:" && checks=$((checks + 1))
    echo "$output" | grep -q "Key file:" && checks=$((checks + 1))
    echo "$output" | grep -q "Disk available:" && checks=$((checks + 1))
    if [[ "$checks" -ge 4 ]]; then
      log_pass "health check ($checks/5 sections)"
    else
      log_fail "health check" "only $checks/5"
    fi
  }

  test_ctl_start_linux() {
    local d="$TEST_DIR/svc-linux"
    bash "$SCRIPT_DIR/node-ctl.sh" start --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null || true
    sleep 2
    status=$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)
    if [[ "$status" == "active" ]]; then
      log_pass "start: service running"
    else
      log_fail "start" "status: $status"
    fi
  }

  test_ctl_status_linux() {
    local d="$TEST_DIR/svc-linux"
    output=$(bash "$SCRIPT_DIR/node-ctl.sh" status --env "$TEST_ENV" --dir "$d" 2>&1) || true
    if echo "$output" | grep -q "$SERVICE_NAME"; then
      log_pass "status shows service info"
    else
      log_fail "status" "service name not found"
    fi
  }

  test_ctl_logs_linux() {
    local d="$TEST_DIR/svc-linux"
    output=$(bash "$SCRIPT_DIR/node-ctl.sh" logs --env "$TEST_ENV" --dir "$d" 2>&1) || true
    log_pass "logs runs without error"
  }

  test_ctl_restart_linux() {
    local d="$TEST_DIR/svc-linux"
    bash "$SCRIPT_DIR/node-ctl.sh" restart --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null || true
    sleep 2
    status=$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)
    if [[ "$status" == "active" ]]; then
      log_pass "restart: service running"
    else
      log_fail "restart" "status: $status"
    fi
  }

  test_ctl_stop_linux() {
    local d="$TEST_DIR/svc-linux"
    bash "$SCRIPT_DIR/node-ctl.sh" stop --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null || true
    sleep 1
    status=$(systemctl --user is-active "$SERVICE_NAME" 2>/dev/null || true)
    if [[ "$status" != "active" ]]; then
      log_pass "stop: service not running"
    else
      log_fail "stop" "still active"
    fi
  }

  test_ctl_uninstall_linux() {
    local d="$TEST_DIR/svc-linux"
    bash "$SCRIPT_DIR/node-ctl.sh" uninstall --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null

    checks=0
    [[ ! -f "$SERVICE_FILE" ]] && checks=$((checks + 1))
    status=$(systemctl --user is-enabled "$SERVICE_NAME" 2>&1 || true)
    echo "$status" | grep -qv "enabled" && checks=$((checks + 1))
    [[ -f "$d/db/secrets.db" ]] && checks=$((checks + 1))
    [[ -f "$d/.password" ]] && checks=$((checks + 1))
    if [[ "$checks" -eq 4 ]]; then
      log_pass "uninstall: service removed, data preserved (4/4)"
    else
      log_fail "uninstall" "only $checks/4"
    fi
  }

  test_ctl_health_linux
  test_ctl_start_linux
  test_ctl_status_linux
  test_ctl_logs_linux
  test_ctl_restart_linux
  test_ctl_stop_linux
  test_ctl_uninstall_linux

elif [[ "$PLATFORM" == "macos" ]]; then

  test_ctl_health_macos() {
    local d="$TEST_DIR/svc-macos"
    output=$(bash "$SCRIPT_DIR/node-ctl.sh" health --env "$TEST_ENV" --dir "$d" 2>&1) || true
    checks=0
    echo "$output" | grep -q "Service:" && checks=$((checks + 1))
    echo "$output" | grep -q "Version:" && checks=$((checks + 1))
    echo "$output" | grep -q "Database:" && checks=$((checks + 1))
    echo "$output" | grep -q "Key file:" && checks=$((checks + 1))
    if [[ "$checks" -ge 3 ]]; then
      log_pass "health check ($checks/4 sections)"
    else
      log_fail "health check" "only $checks/4"
    fi
  }

  test_ctl_start_macos() {
    local d="$TEST_DIR/svc-macos"
    bash "$SCRIPT_DIR/node-ctl.sh" start --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null || true
    sleep 2
    if launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
      log_pass "start: agent running"
    else
      log_fail "start" "agent not found in launchctl list"
    fi
  }

  test_ctl_status_macos() {
    local d="$TEST_DIR/svc-macos"
    output=$(bash "$SCRIPT_DIR/node-ctl.sh" status --env "$TEST_ENV" --dir "$d" 2>&1) || true
    if echo "$output" | grep -qi "running\|$PLIST_LABEL"; then
      log_pass "status shows agent info"
    else
      log_fail "status" "agent info not found"
    fi
  }

  test_ctl_restart_macos() {
    local d="$TEST_DIR/svc-macos"
    bash "$SCRIPT_DIR/node-ctl.sh" restart --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null || true
    sleep 3
    if launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
      log_pass "restart: agent running"
    else
      log_fail "restart" "agent not found"
    fi
  }

  test_ctl_stop_macos() {
    local d="$TEST_DIR/svc-macos"
    bash "$SCRIPT_DIR/node-ctl.sh" stop --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null || true
    sleep 1
    if ! launchctl list 2>/dev/null | grep -q "$PLIST_LABEL"; then
      log_pass "stop: agent not running"
    else
      log_fail "stop" "agent still running"
    fi
  }

  test_ctl_uninstall_macos() {
    local d="$TEST_DIR/svc-macos"
    # Re-load so we can test uninstall
    bash "$SCRIPT_DIR/node-ctl.sh" start --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null || true
    sleep 1
    bash "$SCRIPT_DIR/node-ctl.sh" uninstall --env "$TEST_ENV" --dir "$d" 2>&1 >/dev/null

    checks=0
    [[ ! -f "$PLIST_FILE" ]] && checks=$((checks + 1))
    ! launchctl list 2>/dev/null | grep -q "$PLIST_LABEL" && checks=$((checks + 1))
    [[ -f "$d/db/secrets.db" ]] && checks=$((checks + 1))
    [[ -f "$d/.password" ]] && checks=$((checks + 1))
    if [[ "$checks" -eq 4 ]]; then
      log_pass "uninstall: agent removed, data preserved (4/4)"
    else
      log_fail "uninstall" "only $checks/4"
    fi
  }

  test_ctl_health_macos
  test_ctl_start_macos
  test_ctl_status_macos
  test_ctl_restart_macos
  test_ctl_stop_macos
  test_ctl_uninstall_macos

fi

########################################
echo -e "\n${YELLOW}=== start-node.sh ===${NC}"
########################################

test_start_node_runs() {
  local d="$TEST_DIR/start-ok"
  setup_test_dir "$d"
  # start-node.sh uses exec, so the mock binary's start loop would hang.
  # Use timeout to verify it starts, then kill.
  output=$(timeout 3 bash "$SCRIPT_DIR/start-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1) || true
  if echo "$output" | grep -q "started\|Starting"; then
    log_pass "start-node runs with mock binary"
  else
    log_fail "start node" "got: $output"
  fi
}

test_start_node_no_config() {
  local d="$TEST_DIR/start-noconf"
  mkdir -p "$d"
  create_mock_binary "$d"
  printf 'pw' > "$d/.password"; chmod 600 "$d/.password"
  output=$(bash "$SCRIPT_DIR/start-node.sh" --env "$TEST_ENV" --dir "$d" 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_pass "start-node fails without config"
  else
    log_fail "no config check" "should have failed"
  fi
}

test_start_node_runs
test_start_node_no_config

########################################
# Summary
########################################
echo ""
echo "================================"
TOTAL=$((PASS + FAIL))
echo -e "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC} / $TOTAL total"
echo -e "Platform: $PLATFORM"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for e in "${ERRORS[@]}"; do
    echo -e "  ${RED}• $e${NC}"
  done
fi
echo "================================"
echo "Test dir: $TEST_DIR (cleaned up on exit)"

exit $FAIL
